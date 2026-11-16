import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createGanttData } from '../src/server/web/gantt-data';
import { createGanttSettingsActions } from '../src/server/web/gantt-settings-mutations';
import { DEFAULT_GANTT_CALENDAR, saveGanttSettingsSchema } from '../src/server/web/gantt-settings-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const stamp = '2026-11-16T18:03:24.123456+00:00';
const caps: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.planning.manage', 'em.projects.read'];
const request = { submissionId: id(9), projeto_id: id(1), expected_updated_at: stamp, expected_plan_version: 'a'.repeat(64), reason: 'Calendário acordado com a oficina',
  calendar: { weekdays: [1, 2, 3, 4, 5], exceptions: [{ date: '2026-11-20', working: false, label: 'Parada programada' }, { date: '2026-11-21', working: true, label: 'Turno adicional' }] },
  milestones: [{ id: id(20), label: 'Inspeção com cliente', date: '2026-11-22' }] };
const receipt = { operation: 'save_gantt_settings', id: id(1), projeto_id: id(1), updated_at: stamp, idempotent_replay: false, record: { settings_changed: true } };

test('settings use an explicit all-day default, civil-date milestones and exact revision proof', () => {
  assert.deepEqual(DEFAULT_GANTT_CALENDAR, { weekdays: [1, 2, 3, 4, 5, 6, 7], exceptions: [] });
  assert.deepEqual(saveGanttSettingsSchema.parse(request), request);
  const parsed = saveGanttSettingsSchema.parse({ ...request, reason: '  Calendário revisado  ', calendar: { ...request.calendar, exceptions: [{ date: '1900-01-01', working: false, label: '  Exceção antiga  ' }] }, milestones: [{ id: id(20), date: '2200-12-31', label: '  Entrega  ' }] });
  assert.equal(parsed.expected_updated_at, stamp);
  assert.equal(parsed.reason, 'Calendário revisado');
  assert.equal(parsed.calendar.exceptions[0].label, 'Exceção antiga');
  assert.equal(parsed.milestones[0].label, 'Entrega');
  assert.equal(saveGanttSettingsSchema.parse({ ...request, milestones: [] }).milestones.length, 0);
});

test('settings reject malformed calendars, duplicate dates/IDs, date rollovers and command injection', () => {
  const calendar = request.calendar, milestone = request.milestones[0];
  for (const invalid of [
    { ...request, actor_id: id(99) }, { ...request, items: [] }, { ...request, operation: 'delete_project' },
    { ...request, expected_plan_version: 'invalid' }, { ...request, expected_updated_at: '2026-11-16' }, { ...request, reason: '  ' },
    { ...request, calendar: { ...calendar, weekdays: [] } }, { ...request, calendar: { ...calendar, weekdays: [1, 1] } },
    { ...request, calendar: { ...calendar, weekdays: [0, 8] } }, { ...request, calendar: { ...calendar, weekdays: [1.5] } },
    { ...request, calendar: { ...calendar, holidays: [] } },
    ...['2026-02-30', '1899-12-31', '2201-01-01', stamp].map(date => ({ ...request, calendar: { ...calendar, exceptions: [{ ...calendar.exceptions[0], date }] } })),
    { ...request, calendar: { ...calendar, exceptions: [calendar.exceptions[0], { ...calendar.exceptions[0], working: true }] } },
    ...['', ' ', 'x'.repeat(121), 'Parada\nindevida'].map(label => ({ ...request, calendar: { ...calendar, exceptions: [{ ...calendar.exceptions[0], label }] } })),
    { ...request, calendar: { ...calendar, exceptions: [{ ...calendar.exceptions[0], working: 'false' }] } },
    { ...request, milestones: [milestone, { ...milestone, date: '2026-12-01' }] },
    { ...request, milestones: [{ ...milestone, date: '2026-02-29' }] }, { ...request, milestones: [{ ...milestone, label: '' }] },
    { ...request, milestones: [{ ...milestone, allocation_id: id(8) }] },
  ]) assert.equal(saveGanttSettingsSchema.safeParse(invalid).success, false, JSON.stringify(invalid));
  const exceptions = Array.from({ length: 367 }, (_, n) => ({ date: new Date(Date.UTC(2026, 0, n + 1)).toISOString().slice(0, 10), working: false, label: 'Parada' }));
  assert.equal(saveGanttSettingsSchema.safeParse({ ...request, calendar: { ...calendar, exceptions } }).success, false);
  assert.equal(saveGanttSettingsSchema.safeParse({ ...request, calendar: { ...calendar, exceptions: exceptions.slice(0, 366) } }).success, true);
  const milestones = Array.from({ length: 101 }, (_, n) => ({ ...milestone, id: id(n + 100) }));
  assert.equal(saveGanttSettingsSchema.safeParse({ ...request, milestones }).success, false);
  assert.equal(saveGanttSettingsSchema.safeParse({ ...request, milestones: milestones.slice(0, 100) }).success, true);
});

function fixture(profile = 'administrador', capabilities = caps, result?: WebActionResult) {
  const calls: unknown[][] = [], auth: string[] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Equipe local', perfil: profile },
    sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createGanttSettingsActions({ actionUser: async capability => { auth.push(capability); return access; },
    mutate: async (...args) => { calls.push(args); return result ?? { ok: true, data: receipt }; } });
  return { ...actions, calls, auth };
}

test('settings actions require a current management grant, every read grant and a supported local role', async () => {
  for (const f of [fixture('auditor'), fixture('mobile'), ...caps.map(cap => fixture('administrador', caps.filter(c => c !== cap)))]) {
    const result = await f.saveGanttSettings(request);
    assert.ok(!result.ok); assert.equal(result.code, '42501'); assert.deepEqual(f.calls, []); assert.deepEqual(f.auth, ['em.planning.manage']);
  }
  const denied = createGanttSettingsActions({ actionUser: async () => ({ ok: false, code: 'CORP_FORBIDDEN', error: 'Acesso revogado' }), mutate: async () => { throw new Error('must not run'); } });
  assert.deepEqual(await denied.saveGanttSettings(request), { ok: false, code: 'CORP_FORBIDDEN', error: 'Acesso revogado' });
  for (const profile of ['administrador', 'padr_o']) {
    const f = fixture(profile); assert.ok((await f.saveGanttSettings(request)).ok);
    assert.equal(f.calls[0][1], 'save_gantt_settings'); assert.equal(f.calls[0][3], 'em.planning.manage');
  }
});

test('settings retries retain one protocol and never include date/route edits in the mutation', async () => {
  const f = fixture(); await f.saveGanttSettings(request); await f.saveGanttSettings(request);
  assert.deepEqual(f.calls[0], f.calls[1]); assert.deepEqual(f.calls[0][2], request);
  await f.saveGanttSettings({ ...request, items: [{ id: id(4), changes: { data_inicio: '2026-11-17' } }] });
  assert.equal(f.calls.length, 2);
});

test('settings acknowledge only a matching, typed receipt and pass through conflict/authorization failures', async () => {
  for (const patch of [
    { operation: 'save_gantt_plan' }, { id: id(99) }, { projeto_id: id(99) }, { updated_at: 'invalid' }, { idempotent_replay: undefined },
    { record: { settings_changed: 'yes' } }, { record: { settings_changed: true, private: 'leak' } },
  ]) { const result = await fixture('administrador', caps, { ok: true, data: { ...receipt, ...patch } } as unknown as WebActionResult).saveGanttSettings(request); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE'); }
  const replay = await fixture('administrador', caps, { ok: true, data: { ...receipt, idempotent_replay: true, private: 'strip' } } as unknown as WebActionResult).saveGanttSettings(request);
  assert.ok(replay.ok); assert.equal(replay.data.idempotent_replay, true); assert.ok(!JSON.stringify(replay).includes('strip'));
  for (const code of ['PT409', '42501', 'UNAVAILABLE']) {
    const failure = { ok: false as const, code, error: 'Falha sanitizada' };
    assert.deepEqual(await fixture('administrador', caps, failure).saveGanttSettings(request), failure);
  }
});

function snapshot() {
  return { as_of: stamp, filters: { project_id: null, cell_id: null, include_closed: false }, total: 1, complete: true,
    projects: [{ id: id(1), numero: 'OS', nome: 'Projeto', updated_at: stamp, plan_version: 'a'.repeat(64), closed: false, planned_start: null, planned_end: null, contract_date: null, renegotiated_date: null }],
    cells: [{ id: id(2), nome: 'Célula' }], items: [{ id: id(3), projeto_id: id(1), celula_id: id(2), numero_projeto: 'OS', cliente_nome_export: 'Cliente', celula_nome: 'Célula', status: 'em_dia', bloqueada: 'n_o', motivo_bloqueio: null, visibilidade: true, prioridade: null, indice: 1, posicao: 1, responsavel_nome: null, data_inicio: null, data_limite: null, updated_at: stamp, can_edit: true }],
    links: [], baseline: null, settings: [{ projeto_id: id(1), calendar: request.calendar, milestones: request.milestones, updated_at: stamp }] };
}
function readFixture(data: unknown, capabilities = caps) {
  const calls: unknown[][] = [], client = { rpc: async (...args: unknown[]) => { calls.push(args); return { data, error: null }; } } as unknown as SupabaseClient;
  return { ...createGanttData(client, capabilities), calls };
}

test('snapshot accepts legacy missing settings and exposes typed calendar/milestone data for visible projects', async () => {
  const current = snapshot(), f = readFixture(current);
  assert.deepEqual((await f.getGanttSnapshot(current.filters)).settings, current.settings);
  const { settings: ignored, ...legacy } = current; void ignored;
  assert.deepEqual((await readFixture(legacy).getGanttSnapshot(current.filters)).settings, []);
  const restricted = await readFixture(current, caps.filter(cap => cap !== 'em.projects.read')).getGanttSnapshot(current.filters);
  assert.deepEqual(restricted.settings[0].calendar, request.calendar); assert.deepEqual(restricted.settings[0].milestones, []);
  assert.equal(restricted.items[0].can_edit, false);
});

test('snapshot rejects foreign/duplicated/malformed settings and never acknowledges an oversized partial settings list', async () => {
  const current = snapshot(), settings = current.settings[0];
  for (const data of [
    { ...current, settings: [{ ...settings, projeto_id: id(99) }] }, { ...current, settings: [settings, settings] },
    { ...current, settings: [{ ...settings, calendar: { weekdays: [], exceptions: [] } }] },
    { ...current, settings: [{ ...settings, milestones: [{ ...request.milestones[0], date: '2026-02-30' }] }] },
    { ...current, complete: false, total: 2001, items: [], projects: [], cells: [], links: [] },
  ]) await assert.rejects(readFixture(data).getGanttSnapshot(current.filters), /Não foi possível consultar/);
});
