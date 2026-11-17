import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createExecutionData } from '../src/server/web/execution-data';
import { createExecutionActions } from '../src/server/web/execution-mutations';
import { reviewExecutionSessionSchema } from '../src/server/web/execution-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const stamp = '2026-11-17T16:30:00.123456+00:00', later = '2026-11-17T17:30:00.654321+00:00', version = 'a'.repeat(64);
const caps: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.projects.read', 'em.planning.manage'];
const filters = { project_id: null, cell_id: null, session_id: id(5), include_closed: false };
const allocation = { id: id(1), project_id: id(2), cell_id: id(3), numero_projeto: 'OS local', cliente_nome: 'Cliente', cell_name: 'Ensaios', status: 'em_dia', retired: false, project_closed: false, visible: true, blocked: false, planned_start: stamp, planned_end: later, updated_at: stamp };
const session = { id: id(5), allocation_id: id(1), project_id: id(2), cell_id: id(3), numero_projeto: 'OS local', cell_name: 'Ensaios', operator_id: id(4), operator_name: 'Operador local', state: 'finished', needs_review: false, last_event_id: id(7), last_captured_at: later, last_received_at: later, version, confirmed_minutes: 60, effort_source: 'operator', clock_warning: false, has_review: false };
const first = { id: id(6), session_id: id(5), previous_event_id: null, kind: 'start', occurred_at: stamp, received_at: stamp, pause_reason: null, note: null, effort_minutes: null, disposition: 'accepted', review_reason: null, operator_id: id(4), operator_name: 'Operador local' };
const last = { ...first, id: id(7), previous_event_id: id(6), kind: 'finish', occurred_at: later, received_at: later, effort_minutes: 60 };
const snapshot = () => ({ as_of: later, filters: { ...filters }, complete: true, total: 1, allocations: [{ ...allocation }], sessions: [{ ...session }], detail: { session: { ...session }, events: [{ ...first }, { ...last }], events_total: 2, events_complete: true, reviews: [], reviews_total: 0, reviews_complete: true } });
const input = { submissionId: id(99), session_id: id(5), expected_version: version, action: 'confirm_finished', reported_finished_at: later, effort_minutes: 60, note: 'Conferido com o operador', reason: 'Conciliação do apontamento recebido' };
function read(data: unknown, capabilities = caps) {
  const calls: unknown[][] = [], client = { rpc: async (...args: unknown[]) => { calls.push(args); return { data, error: null }; } } as unknown as SupabaseClient;
  return { ...createExecutionData(client, capabilities), calls };
}
function write(profile = 'administrador', capabilities = caps, supplied?: WebActionResult) {
  const calls: unknown[][] = [], access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Gestão', perfil: profile }, sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  return { ...createExecutionActions({ actionUser: async () => access, mutate: async (...args) => { calls.push(args); return supplied ?? { ok: true, data: { operation: 'review_execution_session', id: id(5), projeto_id: id(2), updated_at: later, idempotent_replay: false, record: { review_id: id(9) } } }; } }), calls };
}

test('execution review uses explicit nullable effort, exact versions and a separate confirmation time', () => {
  assert.ok(reviewExecutionSessionSchema.safeParse(input).success);
  assert.ok(reviewExecutionSessionSchema.safeParse({ ...input, effort_minutes: null }).success);
  assert.ok(reviewExecutionSessionSchema.safeParse({ ...input, action: 'void', reported_finished_at: null, effort_minutes: null }).success);
  for (const patch of [{ action: 'start' }, { expected_version: 'old' }, { reported_finished_at: null }, { effort_minutes: -1 }, { effort_minutes: 1.5 }, { effort_minutes: 1000001 }, { action: 'void' }, { operator_id: id(10) }, { change_allocation_status: true }, { reason: ' ' }, { note: 'x'.repeat(1001) }]) assert.equal(reviewExecutionSessionSchema.safeParse({ ...input, ...patch }).success, false);
});
test('execution reader requires every domain read capability before accessing the backend', async () => {
  for (const missing of caps.slice(0, 3)) { const f = read(snapshot(), caps.filter(cap => cap !== missing)); await assert.rejects(() => f.getExecutionSnapshot(filters), /Acesso/); assert.equal(f.calls.length, 0); }
  const f = read(snapshot()); const result = await f.getExecutionSnapshot(filters); assert.equal(f.calls.length, 1);
  assert.equal(result.detail!.events[0].occurred_at, stamp); assert.equal(result.detail!.events[1].received_at, later); assert.equal(result.sessions[0].confirmed_minutes, 60);
});
test('execution preserves unknown effort, raw clock disagreements and quarantined predecessor claims', async () => {
  const data = snapshot(); data.sessions[0].needs_review = true; data.sessions[0].clock_warning = true; data.detail.session = { ...data.sessions[0] };
  data.detail.events[1] = { ...last, previous_event_id: id(88), occurred_at: '2026-11-17T14:00:00+00:00', disposition: 'review', review_reason: 'previous_mismatch' } as unknown as typeof last;
  const result = await read(data).getExecutionSnapshot(filters); assert.equal(result.detail!.events[1].previous_event_id, id(88)); assert.equal(result.detail!.events[1].occurred_at, '2026-11-17T14:00:00+00:00');
  const empty = { ...snapshot(), sessions: [], detail: null, filters: { ...filters, session_id: null } };
  assert.deepEqual((await read(empty).getExecutionSnapshot(empty.filters)).sessions, []);
});
test('execution refuses foreign contexts, duplicate rows and misleading partial histories', async () => {
  const data = snapshot();
  for (const raw of [{ ...data, complete: false }, { ...data, total: 2 }, { ...data, allocations: [allocation, allocation] }, { ...data, sessions: [session, session] }, { ...data, sessions: [{ ...session, allocation_id: id(55) }] }, { ...data, detail: { ...data.detail, events_total: 3 } }, { ...data, detail: { ...data.detail, events: [first, first] } }, { ...data, detail: { ...data.detail, events: [first, { ...last, session_id: id(55) }] } }, { ...data, detail: { ...data.detail, events: [first, { ...last, operator_id: id(55) }] } }, { ...data, filters: { ...filters, cell_id: id(55) } }]) await assert.rejects(() => read(raw).getExecutionSnapshot(filters), /consultar/);
  const overflow = { ...data, complete: false, total: 2001, allocations: [], sessions: [], detail: null };
  assert.equal((await read(overflow).getExecutionSnapshot(filters)).complete, false);
  await assert.rejects(() => read({ ...data, filters: { ...filters, project_id: id(99) } }).getExecutionSnapshot({ ...filters, project_id: id(99) }), /consultar/);
});
test('execution accepts an explicitly truncated tail while keeping full-stream revision evidence', async () => {
  const data = snapshot(), events = Array.from({ length: 200 }, (_, n) => ({ ...first, id: id(100 + n), previous_event_id: n ? id(99 + n) : id(98) }));
  const detail = { ...data.detail, events, events_total: 201, events_complete: false };
  const result = await read({ ...data, detail }).getExecutionSnapshot(filters); assert.equal(result.detail!.events_complete, false); assert.equal(result.sessions[0].version, version);
});
test('execution reconciliation rechecks active roles and all capabilities, and retries one frozen body', async () => {
  for (const f of [write('auditor'), write('mobile'), ...caps.map(cap => write('administrador', caps.filter(item => item !== cap)))]) { const result = await f.reviewExecutionSession(input); assert.ok(!result.ok); assert.equal(result.code, '42501'); assert.equal(f.calls.length, 0); }
  const f = write(); assert.ok((await f.reviewExecutionSession(input)).ok); assert.ok((await f.reviewExecutionSession(input)).ok); assert.deepEqual(f.calls[0], f.calls[1]); assert.equal(f.calls[0][1], 'review_execution_session'); assert.equal(f.calls[0][3], 'em.planning.manage');
});
test('execution receipts must identify the submitted session and never leak private extras', async () => {
  const receipt = { operation: 'review_execution_session', id: id(5), projeto_id: id(2), updated_at: later, idempotent_replay: false, record: { review_id: id(9) } };
  for (const patch of [{ id: id(55) }, { operation: 'plan_cell' }, { projeto_id: null }, { record: { review_id: 'invalid' } }, { record: { review_id: id(9), private: 'leak' } }, { updated_at: 'invalid' }]) { const result = await write('administrador', caps, { ok: true, data: { ...receipt, ...patch } } as unknown as WebActionResult).reviewExecutionSession(input); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE'); }
  const result = await write('administrador', caps, { ok: true, data: { ...receipt, private: 'strip' } } as unknown as WebActionResult).reviewExecutionSession(input); assert.ok(result.ok); assert.ok(!JSON.stringify(result).includes('strip'));
  for (const code of ['PT409', 'PT410', '42501']) { const failure = { ok: false as const, code, error: 'Mensagem de reconciliação' }; assert.deepEqual(await write('administrador', caps, failure).reviewExecutionSession(input), failure); }
});
