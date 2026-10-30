import test from 'node:test';
import assert from 'node:assert/strict';
import { manageStageRulesSchema } from '../src/server/web/operational-stage-rule-policy';
import { createOperationalStageRuleActions } from '../src/server/web/operational-stage-rule-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T13:00:01.123456+00:00';
const common = { submissionId: id(1), projeto_id: id(2), celula_projeto_id: id(3), expected_project_updated_at: version,
  expected_allocation_updated_at: version, expected_rules_version: 'a'.repeat(64) };
const config = { celula_destino_id: id(4), status_cel_proj: 'finalizado' as const, bloquear_avanco_sem_aprov: false,
  aprovadores_ids: [id(5)], aprovadores_retorno_ids: [id(6)] };
const create = { ...common, action: 'create' as const, id: id(7), config };
const target = { ...common, etapa_id: id(7), expected_etapa_updated_at: version, confirm_change: true as const };
const replacement = { ...target, action: 'replace' as const, replacement_id: id(8), config };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.planning.manage', 'em.approvals.read'];

function fixture(options: { role?: string; capabilities?: CorporateCapability[]; failure?: string; patch?: (value: WebActionResult) => WebActionResult } = {}) {
  const calls: any[][] = [], auth: string[] = [], capabilities = options.capabilities || caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role || 'administrador' },
    sso: { sessionHash: 'hash', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createOperationalStageRuleActions({
    actionUser: async capability => {
      auth.push(capability); return capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' };
    },
    mutate: async (...args) => {
      calls.push(args); const body: any = args[2], previous = body.action === 'replace' ? body.etapa_id : null;
      const resultId = body.action === 'create' ? body.id : body.action === 'replace' ? body.replacement_id : body.etapa_id;
      const value: WebActionResult = options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'manage_stage_rules', id: resultId, projeto_id: id(2), updated_at: version, idempotent_replay: false,
        record: { projeto_id: id(2), celula_projeto_id: id(3), action: body.action, etapa_id: resultId,
          previous_etapa_id: previous, rules_version: 'b'.repeat(64), changed_ids: previous ? [previous, resultId] : [resultId], private_journal: 'excluded' },
      } };
      return options.patch ? options.patch(value) : value;
    },
  });
  return { ...actions, calls, auth };
}

test('stage rule payloads require complete configurations, new replacement identities and explicit destructive confirmation', () => {
  for (const body of [create, replacement, { ...target, action: 'retire' }, { ...target, action: 'restore' }]) assert.deepEqual(manageStageRulesSchema.parse(body), body);
  for (const body of [{ ...create, config: { ...config, status_cel_proj: 'retornado' } }, { ...create, config: { ...config, aprovadores_ids: [] } },
    { ...create, config: { ...config, aprovadores_retorno_ids: [id(6), id(6)] } },
    { ...create, config: { ...config, aprovadores_ids: Array.from({ length: 101 }, (_, i) => id(i + 100)) } },
    { ...create, config: { ...config, status: 'aprovado' } }, { ...create, actor_id: id(10) },
    { ...replacement, replacement_id: replacement.etapa_id }, { ...replacement, confirm_change: false },
    { ...target, action: 'retire', confirm_change: undefined }, { ...target, action: 'restore', config },
    { ...create, expected_project_updated_at: version.slice(0, 19) }]) assert.equal(manageStageRulesSchema.safeParse(body).success, false);
});

test('deciding approvals does not authorize configuration; management requires scoped reads and a writing profile', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ role: 'mobile' }),
    ...caps.map(capability => fixture({ capabilities: caps.filter(value => value !== capability) })),
    fixture({ capabilities: [...caps.filter(value => value !== 'em.planning.manage'), 'em.approvals.decide'] })]) {
    assert.equal((await f.manageStageRules(create)).ok, false); assert.deepEqual(f.auth, ['em.planning.manage']); assert.equal(f.calls.length, 0);
  }
  const planner = fixture({ role: 'padr_o' }); assert.equal((await planner.manageStageRules(create)).ok, true);
  assert.equal(planner.calls[0][3], 'em.planning.manage');
});

test('all configuration actions use the common permit gateway, retain exact retry payloads and exclude journal data', async () => {
  const f = fixture();
  for (const body of [create, replacement, { ...target, action: 'retire' }, { ...target, action: 'restore' }]) {
    const result = await f.manageStageRules(body); assert.ok(result.ok); assert.equal(result.data.record.private_journal, undefined);
    assert.equal(f.calls.at(-1)?.[1], 'manage_stage_rules'); assert.deepEqual(f.calls.at(-1)?.[2], body);
  }
  await f.manageStageRules(create); assert.deepEqual(f.calls[0], f.calls[4]);
  for (const code of ['PT409', 'UNAVAILABLE', 'CORP_UNAVAILABLE', '42501']) {
    const result = await fixture({ failure: code }).manageStageRules(create); assert.ok(!result.ok); assert.equal(result.code, code);
  }
});

test('confirmations must identify the exact action, context and complete set of affected immutable versions', async () => {
  for (const patch of [{ operation: 'transition_stage_approval' }, { id: id(99) }, { projeto_id: id(99) }, { updated_at: 'bad' },
    { idempotent_replay: null }, { record: {} },
    ...['projeto_id', 'celula_projeto_id', 'etapa_id', 'previous_etapa_id'].map(key => ({ nested: { [key]: id(99) } })),
    { nested: { action: 'retire' } }, { nested: { changed_ids: [id(7)] } }, { nested: { changed_ids: [id(7), id(7)] } },
    { nested: { changed_ids: [id(7), id(99)] } }]) {
    const f = fixture({ patch: value => value.ok ? { ok: true, data: { ...value.data, ...patch,
      ...('nested' in patch ? { record: { ...value.data.record, ...patch.nested } } : {}) } } as unknown as WebActionResult : value });
    const result = await f.manageStageRules(replacement); assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE');
  }
});
