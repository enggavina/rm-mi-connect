import test from 'node:test';
import assert from 'node:assert/strict';
import { assignFormReviewerSchema } from '../src/server/web/form-reviewer-policy';
import { createFormReviewerActions } from '../src/server/web/form-reviewer-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const timestamp = '2026-10-30T09:18:23.123456+00:00';
const input = { submissionId: id(1), projeto_id: id(2), celula_projeto_id: id(3), form_id: id(4), avaliador_user_id: id(5),
  expected_project_updated_at: timestamp, expected_allocation_updated_at: timestamp, expected_context_version: 'a'.repeat(64), confirm_replace: false };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.planning.manage', 'em.forms.read'];
const record = { assignment_id: id(6), projeto_id: id(2), celula_projeto_id: id(3), celula_id: id(7), form_id: id(4),
  avaliador_user_id: id(5), context_version: 'b'.repeat(64), records_updated_ids: [id(20), id(21)] };

function fixture(options: { role?: string; capabilities?: CorporateCapability[]; failure?: string; patch?: Record<string, unknown> } = {}) {
  const calls: any[][] = [], auth: string[] = [], capabilities = options.capabilities || caps;
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(9), nome: 'Planejamento', perfil: options.role || 'administrador' },
    sso: { sessionHash: 'hash', bindingId: id(10), subject: id(11), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createFormReviewerActions({
    actionUser: async capability => {
      auth.push(capability);
      return capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' };
    },
    mutate: async (...args) => {
      calls.push(args);
      return options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'assign_form_reviewer', id: id(6), projeto_id: id(2), updated_at: timestamp, idempotent_replay: false,
        record: { ...record, private_snapshot: 'excluded' }, ...options.patch,
      } } as WebActionResult;
    },
  });
  return { ...actions, calls, auth };
}

test('assignment input preserves precise versions and explicit confirmation without accepting record creation or actor fields', () => {
  assert.deepEqual(assignFormReviewerSchema.parse(input), input);
  for (const patch of [{ confirm_replace: undefined }, { confirm_replace: 'true' }, { avaliador_user_id: null }, { expected_context_version: 'bad' },
    { expected_project_updated_at: timestamp.slice(0, 19) }, { status: 'aprovado' }, { actor_id: id(8) },
    { registro_formulario_id: id(20) }, { records_updated_ids: [id(20)] }, { resposta: 'injected' }]) {
    assert.equal(assignFormReviewerSchema.safeParse({ ...input, ...patch }).success, false);
  }
});

test('review permission alone does not authorize assignment; planning writers need all contextual reads', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ role: 'mobile' }),
    ...caps.map(capability => fixture({ capabilities: caps.filter(value => value !== capability) })),
    fixture({ capabilities: [...caps.filter(value => value !== 'em.planning.manage'), 'em.forms.review'] })]) {
    assert.equal((await f.assignFormReviewer(input)).ok, false);
    assert.deepEqual(f.auth, ['em.planning.manage']); assert.equal(f.calls.length, 0);
  }
  const planner = fixture({ role: 'padr_o' });
  assert.equal((await planner.assignFormReviewer(input)).ok, true);
  assert.equal(planner.calls[0][3], 'em.planning.manage');
});

test('assignments use the existing gateway and sanitize confirmed data while preserving the exact retry request', async () => {
  const f = fixture(), result = await f.assignFormReviewer(input);
  assert.ok(result.ok); assert.deepEqual(result.data.record, record);
  assert.equal(f.calls[0][1], 'assign_form_reviewer'); assert.deepEqual(f.calls[0][2], input);
  await f.assignFormReviewer(input); assert.deepEqual(f.calls[0], f.calls[1]);
  for (const code of ['PT409', 'UNAVAILABLE', 'CORP_UNAVAILABLE', '42501']) {
    const rejected = await fixture({ failure: code }).assignFormReviewer(input);
    assert.ok(!rejected.ok); assert.equal(rejected.code, code);
  }
});

test('unrelated assignment confirmations and malformed record sets freeze the attempt as unavailable', async () => {
  for (const patch of [{ operation: 'review_form' }, { id: id(99) }, { id: 'bad' }, { projeto_id: id(99) }, { updated_at: null },
    { idempotent_replay: null }, { record: {} },
    ...['projeto_id', 'celula_projeto_id', 'form_id', 'avaliador_user_id'].map(key => ({ record: { ...record, [key]: id(99) } })),
    { record: { ...record, records_updated_ids: [id(20), id(20)] } }, { record: { ...record, records_updated_ids: ['bad'] } },
    { record: { ...record, records_updated_ids: Array.from({ length: 2001 }, (_, index) => id(index + 100)) } }]) {
    const rejected = await fixture({ patch }).assignFormReviewer(input);
    assert.ok(!rejected.ok); assert.equal(rejected.code, 'UNAVAILABLE');
  }
});
