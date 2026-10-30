import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createOperationalStageRuleData } from '../src/server/web/operational-stage-rule-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T03:22:10.123456+00:00';
const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.approvals.read', 'em.planning.manage'];
function snapshot() {
  const person = (n: number) => ({ id: id(n), nome: 'Aprovador', matricula: `EM-${n}`, eligible: true, auth_user_id: 'private-auth' });
  const base = { id: id(6), projeto_id: id(1), celula_projeto_id: null as string | null, celula_origem_id: id(3), celula_destino_id: id(4), celula_destino_nome: 'Montagem',
    status: null as string | null, status_cel_proj: 'finalizado', bloquear_avanco_sem_aprov: false, ativo: true,
    aprovador_id: null, aprovadores_ids: [id(20)], aprovadores_retorno_ids: [id(21)], aprovado_por_id: null, data_aprovacao: null,
    created_at: version, updated_at: version, approvers: [person(20)], return_approvers: [person(21)], used: false, history_ambiguous: false,
    related_return_ids: [] as string[], pair_ambiguous: false, managed_birth: false, family_ids: [id(6)], supersedes_id: null as string | null,
    can_edit: true, can_retire: true, can_restore: false, action_reason: null as string | null, private_data: 'private' };
  return {
    project: { id: id(1), numero: 'OS1', status_pcp: null as string | null, data_real_de_entrega: null, updated_at: version, closed: false, arquivo_url: 'private-file' },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(3), celula_nome: 'Peritagem', status: 'finalizado', updated_at: version },
    rules: [base, { ...base, id: id(7), family_ids: [id(7)], ativo: false, can_edit: false, can_retire: false, can_restore: true },
      { ...base, id: id(8), family_ids: [id(8)], status_cel_proj: 'retornado', can_edit: false, can_retire: false },
      { ...base, id: id(9), family_ids: [id(9)], used: true, status: 'nulo', can_edit: false, can_retire: false }],
    statuses: [{ key: 'finalizado', label: 'Finalizado' }, { key: 'em_dia', label: 'Executando' }],
    destinations: [{ allocation_id: id(2), celula_id: id(3), nome: 'Peritagem', status: 'finalizado', updated_at: version, can_select: false, reason: 'Origem' },
      { allocation_id: id(12), celula_id: id(4), nome: 'Montagem', status: 'pendente', updated_at: version, can_select: true, reason: null as string | null }],
    eligible_users: [{ id: id(20), nome: 'Aprovador', matricula: 'EM-20', celula_ids: [id(3)], email: 'private-email' },
      { id: id(21), nome: 'Aprovador', matricula: 'EM-21', celula_ids: [id(4)], email: 'private-email' }],
    rules_version: 'a'.repeat(64), total: 4, selected_total: 4, complete: true, allocations_total: 2, allocations_complete: true,
    eligible_total: 2, eligible_complete: true, memberships_total: 2, memberships_complete: true, private_data: 'private',
  };
}
function fixture(caps: readonly CorporateCapability[] = capabilities) {
  let current: unknown = snapshot(), error: unknown = null, thrown = false; const calls: { name: string; args: unknown }[] = [];
  const client = { async rpc(name: string, args: unknown) { calls.push({ name, args }); if (thrown) throw new Error('private-upstream'); return { data: current, error }; } } as unknown as SupabaseClient;
  return { reader: createOperationalStageRuleData(client, caps), calls, set(value: unknown) { current = value; }, fail(value: unknown) { error = value; }, throw() { thrown = true; } };
}

test('stage configuration reads require independent domain grants and planning management before returning choices', async () => {
  for (const missing of ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.approvals.read'] as CorporateCapability[]) {
    const f = fixture(capabilities.filter(capability => capability !== missing));
    await assert.rejects(f.reader.getOperationalStageRules(id(1), id(2)), /Acesso/); assert.deepEqual(f.calls, []);
  }
  const f = fixture(capabilities.filter(capability => capability !== 'em.planning.manage'));
  await assert.rejects(f.reader.getOperationalStageRules(id(1), id(2), true), /Acesso/); assert.deepEqual(f.calls, []);
  assert.equal(await f.reader.getOperationalStageRules('invalid', id(2)), null); assert.deepEqual(f.calls, []);
  assert.ok(await f.reader.getOperationalStageRules(id(1), id(2)));
});

test('one atomic stage configuration snapshot preserves exact revisions, null legacy links and history while stripping private fields', async () => {
  const f = fixture(), result = await f.reader.getOperationalStageRules(id(1), id(2), true); assert.ok(result);
  assert.equal(result.project.updated_at, version); assert.equal(result.rules[0].updated_at, version); assert.equal(result.rules[0].celula_projeto_id, null);
  assert.equal(result.allocation.status, 'finalizado'); assert.equal(result.rules[0].can_edit, true, 'Finalizado is a legitimate origin for release configuration.');
  assert.equal(result.rules[2].status_cel_proj, 'retornado'); assert.equal(result.rules[2].can_edit, false);
  assert.equal(result.rules[3].status, 'nulo'); assert.equal(result.rules[3].used, true, 'A reopened null stage must not be treated as unused.');
  assert.ok(!JSON.stringify(result).includes('private'));
  assert.deepEqual(f.calls, [{ name: 'rm_web_stage_rules_snapshot_v1', args: { p_project_id: id(1), p_allocation_id: id(2), p_include_choices: true } }]);
  const readonly = await f.reader.getOperationalStageRules(id(1), id(2));
  assert.deepEqual(readonly?.eligible_users, []); assert.deepEqual(readonly?.statuses, []); assert.deepEqual(readonly?.destinations, []);
  assert.equal(readonly?.rules[0].approvers[0].matricula, 'EM-20');
  const managed = snapshot(); managed.rules[0].managed_birth = true; managed.rules[0].related_return_ids = [id(90), id(91)]; managed.rules[0].pair_ambiguous = true;
  f.set(managed); assert.equal((await f.reader.getOperationalStageRules(id(1), id(2), true))?.rules[0].can_edit, true, 'An unused managed rule remains independent from unrelated historical return paths.');
});

test('stage configuration rejects crossed scope, impossible permissions, duplicate identities and partial editable collections', async () => {
  const f = fixture();
  const cases: unknown[] = [
    { ...snapshot(), project: { ...snapshot().project, id: id(99) } }, { ...snapshot(), allocation: { ...snapshot().allocation, id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, projeto_id: id(99) } }, { ...snapshot(), allocation: { ...snapshot().allocation, status: 'n_a' } },
    { ...snapshot(), project: { ...snapshot().project, status_pcp: 'cancelado', closed: true } },
    { ...snapshot(), total: 3 }, { ...snapshot(), selected_total: 5 }, { ...snapshot(), complete: false }, { ...snapshot(), rules_version: 'invalid' },
    { ...snapshot(), statuses: [{ key: 'retornado', label: 'Retornado' }] }, { ...snapshot(), statuses: [{ key: 'unknown', label: 'Unknown' }] },
    { ...snapshot(), eligible_users: [...snapshot().eligible_users, snapshot().eligible_users[0]], eligible_total: 3 },
    { ...snapshot(), rules: [...snapshot().rules, snapshot().rules[0]], total: 5, selected_total: 5 },
  ];
  for (const patch of [{ projeto_id: id(99) }, { celula_origem_id: id(99) }, { celula_projeto_id: id(99) }, { ativo: false }, { can_restore: true },
    { used: true }, { history_ambiguous: true }, { pair_ambiguous: true }, { related_return_ids: [id(90)] }, { status_cel_proj: 'retornado' }, { status: 'aprovado' }]) {
    const value = snapshot(); value.rules[0] = { ...value.rules[0], ...patch } as typeof value.rules[number]; cases.push(value);
  }
  const invalidDestination = snapshot(); invalidDestination.destinations[1].status = 'finalizado'; cases.push(invalidDestination);
  const activeFamily = snapshot(); activeFamily.rules[1].family_ids = [id(7), id(6)]; cases.push(activeFamily);
  const staleRestore = snapshot(); staleRestore.rules[1].celula_destino_id = id(99); cases.push(staleRestore);
  const invalidRestoreStatus = snapshot(); invalidRestoreStatus.rules[1].status_cel_proj = 'retornado'; cases.push(invalidRestoreStatus);
  for (const value of cases) { f.set(value); await assert.rejects(f.reader.getOperationalStageRules(id(1), id(2), true), /Não foi possível/); }
});

test('stage configuration limits retain consultation without truncated choices and sanitize unavailable responses', async () => {
  const f = fixture();
  const noChoices = { statuses: [], destinations: [], eligible_users: [] };
  for (const value of [
    { ...snapshot(), ...noChoices, total: 1001, complete: false, rules: [] },
    { ...snapshot(), ...noChoices, allocations_total: 1001, allocations_complete: false, rules: [] },
    { ...snapshot(), ...noChoices, eligible_total: 1001, eligible_complete: false, rules: snapshot().rules.map(rule => ({ ...rule, can_edit: false, can_retire: false, can_restore: false })) },
    { ...snapshot(), ...noChoices, memberships_total: 5001, memberships_complete: false, rules: snapshot().rules.map(rule => ({ ...rule, can_edit: false, can_retire: false, can_restore: false })) },
  ]) { f.set(value); assert.ok(await f.reader.getOperationalStageRules(id(1), id(2), true)); }
  f.set({ ...snapshot(), total: 1000, rules: snapshot().rules.map(rule => ({ ...rule, can_edit: false })) });
  assert.equal((await f.reader.getOperationalStageRules(id(1), id(2), true))?.rules[0].can_retire, true);
  f.set(null); assert.equal(await f.reader.getOperationalStageRules(id(1), id(2)), null);
  f.fail({ message: 'private-upstream' }); await assert.rejects(f.reader.getOperationalStageRules(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
  const throws = fixture(); throws.throw(); await assert.rejects(throws.reader.getOperationalStageRules(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
});
