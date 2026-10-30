import test from 'node:test';
import assert from 'node:assert/strict';
import { manageCellAvailabilitySchema } from '../src/server/web/cell-availability-policy';
import { createCellAvailabilityActions } from '../src/server/web/cell-availability-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T13:00:01.123456+00:00';
const common = { submissionId: id(1), projeto_id: id(2), celula_projeto_id: id(3), expected_project_updated_at: version,
  expected_allocation_updated_at: version, expected_context_version: 'a'.repeat(64), confirm_change: true as const };
const hide = { ...common, action: 'set_visibility' as const, visibilidade: false };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.planning.manage'];
function fixture(options: { role?: string; capabilities?: CorporateCapability[]; failure?: string; patch?: (result: WebActionResult) => WebActionResult } = {}) {
  const calls: any[][] = [], auth: string[] = [], capabilities = options.capabilities || caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), perfil: options.role || 'administrador', nome: 'Pessoa' },
    sso: { sessionHash: 'hash', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createCellAvailabilityActions({ actionUser: async capability => {
    auth.push(capability); return capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' };
  }, mutate: async (...args) => {
    calls.push(args); const body: any = args[2];
    const result: WebActionResult = options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
      operation: 'manage_cell_availability', id: id(3), projeto_id: id(2), updated_at: version, idempotent_replay: false,
      record: { projeto_id: id(2), celula_projeto_id: id(3), action: body.action, retirada: body.action === 'retire',
        visibilidade: body.action === 'set_visibility' ? body.visibilidade : false, context_version: 'b'.repeat(64), changed_ids: [id(3)],
        private_evidence: 'excluded' },
    } };
    return options.patch ? options.patch(result) : result;
  } });
  return { ...actions, calls, auth };
}
test('availability requests cannot inject lifecycle, ordering, actor or configuration and require literal confirmation', () => {
  for (const input of [hide, { ...hide, visibilidade: true }, { ...common, action: 'retire' }, { ...common, action: 'restore' }]) assert.deepEqual(manageCellAvailabilitySchema.parse(input), input);
  for (const input of [{ ...hide, confirm_change: false }, { ...hide, confirm_change: undefined },
    { ...hide, visibilidade: 'false' }, { ...hide, expected_context_version: 'short' },
    { ...hide, expected_allocation_updated_at: 'yesterday' },
    ...['actor_id', 'posicao', 'indice', 'prioridade', 'retirada', 'forms_ids', 'status'].map(key => ({ ...hide, [key]: id(9) })),
    { ...hide, action: 'retire' }, { ...hide, action: 'restore' }]) assert.equal(manageCellAvailabilitySchema.safeParse(input).success, false);
});
test('allocation availability requires scoped planning access without borrowing engineering or approval privileges', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ role: 'mobile' }), ...caps.map(capability => fixture({ capabilities: caps.filter(value => value !== capability) })),
    fixture({ capabilities: [...caps.filter(c => c !== 'em.planning.manage'), 'em.engineering.manage', 'em.approvals.decide'] })]) {
    assert.equal((await f.manageCellAvailability(hide)).ok, false); assert.deepEqual(f.auth, ['em.planning.manage']); assert.equal(f.calls.length, 0);
  }
  const planner = fixture({ role: 'padr_o' }); assert.equal((await planner.manageCellAvailability(hide)).ok, true);
  assert.equal(planner.calls[0][1], 'manage_cell_availability'); assert.equal(planner.calls[0][3], 'em.planning.manage');
});
test('all lifecycle actions retain exact attempts and sanitize evidence while preserving gateway errors', async () => {
  const f = fixture();
  for (const input of [hide, { ...hide, visibilidade: true }, { ...common, action: 'retire' }, { ...common, action: 'restore' }]) {
    const result = await f.manageCellAvailability(input); assert.ok(result.ok); assert.equal(result.data.record.private_evidence, undefined);
    assert.deepEqual(f.calls.at(-1)?.[2], input);
  }
  await f.manageCellAvailability(hide); assert.deepEqual(f.calls[0], f.calls[4]);
  for (const code of ['PT409', 'UNAVAILABLE', 'CORP_UNAVAILABLE', '42501']) {
    const result = await fixture({ failure: code }).manageCellAvailability(hide); assert.ok(!result.ok); assert.equal(result.code, code);
  }
});
test('availability confirmation must identify the exact context, action, lifecycle and affected allocation', async () => {
  const retired = { ...common, action: 'retire' };
  for (const patch of [{ operation: 'plan_cell' }, { id: id(99) }, { projeto_id: id(99) }, { updated_at: 'bad' }, { idempotent_replay: null }, { record: null },
    ...['projeto_id', 'celula_projeto_id'].map(key => ({ nested: { [key]: id(99) } })),
    { nested: { action: 'restore' } }, { nested: { changed_ids: [id(99)] } }, { nested: { changed_ids: [id(3), id(3)] } },
    { nested: { retirada: false } }, { nested: { visibilidade: true } }, { nested: { context_version: '' } }]) {
    const f = fixture({ patch: value => value.ok ? { ok: true, data: { ...value.data, ...patch,
      ...('nested' in patch ? { record: { ...value.data.record, ...patch.nested } } : {}) } } as unknown as WebActionResult : value });
    const result = await f.manageCellAvailability(retired); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
  for (const input of [hide, { ...common, action: 'restore' }]) {
    const f = fixture({ patch: value => value.ok ? { ok: true, data: { ...value.data, record: { ...value.data.record, retirada: true } } } : value });
    const result = await f.manageCellAvailability(input); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
});
