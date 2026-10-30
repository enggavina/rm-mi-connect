import test from 'node:test';
import assert from 'node:assert/strict';
import type { OperationalStageRuleSnapshot } from '../src/server/web/operational-stage-rule-data';
import { canManageStageRules, emptyStageRuleConfig, stageRuleConfig, stageRuleConfigChanged, stageRuleDestinationChanged, stageRulePage, stageRulePeople, stageRulePersonLabel, stageRuleRequest } from '../src/components/web/operational-stage-rule-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T03:22:10.123456+00:00';
function snapshot(): OperationalStageRuleSnapshot {
  const person = (n: number) => ({ id: id(n), nome: 'Aprovador', matricula: `EM-${n}`, eligible: true });
  const rule = { id: id(6), projeto_id: id(1), celula_projeto_id: null, celula_origem_id: id(3), celula_destino_id: id(4), celula_destino_nome: 'Montagem',
    status: null, status_cel_proj: 'finalizado', bloquear_avanco_sem_aprov: false, ativo: true,
    aprovador_id: null, aprovadores_ids: [id(20)], aprovadores_retorno_ids: [id(21)], aprovado_por_id: null, data_aprovacao: null,
    created_at: version, updated_at: version, approvers: [person(20)], return_approvers: [person(21)], used: false, history_ambiguous: false,
    related_return_ids: [], pair_ambiguous: false, managed_birth: false, family_ids: [id(6)], supersedes_id: null, can_edit: true, can_retire: true, can_restore: false, action_reason: null };
  return {
    project: { id: id(1), numero: 'OS1', status_pcp: null, data_real_de_entrega: null, updated_at: version, closed: false },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(3), celula_nome: 'Peritagem', status: 'finalizado', updated_at: version },
    rules: [rule, { ...rule, id: id(7), family_ids: [id(7)], ativo: false, can_edit: false, can_retire: false, can_restore: true }],
    statuses: [{ key: 'finalizado', label: 'Finalizado' }, { key: 'em_dia', label: 'Executando' }],
    destinations: [{ allocation_id: id(12), celula_id: id(4), nome: 'Montagem', status: 'pendente', updated_at: version, can_select: true, reason: null },
      { allocation_id: id(13), celula_id: id(5), nome: 'Destino encerrado', status: 'finalizado', updated_at: version, can_select: false, reason: 'Encerrada' }],
    eligible_users: [{ id: id(20), nome: 'Aprovador', matricula: 'EM-20', celula_ids: [id(3)] }, { id: id(21), nome: 'Aprovador', matricula: 'EM-21', celula_ids: [id(4)] }],
    rules_version: 'a'.repeat(64), total: 2, selected_total: 2, complete: true, allocations_total: 3, allocations_complete: true,
    eligible_total: 2, eligible_complete: true, memberships_total: 2, memberships_complete: true,
  };
}

test('creating a release uses project-scoped destination and correct-cell approvers without decision or actor fields', () => {
  const current = snapshot(), config = stageRuleConfig(current.rules[0]);
  const request = stageRuleRequest(current, { action: 'create', id: id(30) }, config, false, id(40));
  assert.ok(request.action === 'create'); assert.equal(request.id, id(30)); assert.equal(request.config.celula_destino_id, id(4));
  assert.deepEqual(request.config.aprovadores_ids, [id(20)]); assert.deepEqual(request.config.aprovadores_retorno_ids, [id(21)]);
  for (const field of ['status', 'aprovado_por_id', 'data_aprovacao', 'actor_id', 'celula_origem_id', 'ativo']) assert.ok(!(field in request));
  assert.equal(stageRulePeople(current, id(3)).length, 1); assert.equal(stageRulePeople(current, id(99)).length, 0);
  for (const patch of [{ status_cel_proj: 'retornado' }, { status_cel_proj: 'arbitrary' }, { celula_destino_id: id(3) }, { celula_destino_id: id(5) }, { celula_destino_id: id(99) },
    { aprovadores_ids: [] }, { aprovadores_ids: [id(21)] }, { aprovadores_ids: [id(20), id(20)] }, { aprovadores_retorno_ids: [id(20)] }, { aprovadores_retorno_ids: [] }]) {
    assert.throws(() => stageRuleRequest(current, { action: 'create', id: id(30) }, { ...config, ...patch }, false, id(40)));
  }
});

test('replacement preserves the original configuration and freezes new IDs, exact versions and nested fields for retry', () => {
  const current = snapshot(), config = stageRuleConfig(current.rules[0]); config.bloquear_avanco_sem_aprov = true;
  const before = JSON.stringify(current.rules[0]);
  assert.throws(() => stageRuleRequest(current, { action: 'replace', ruleId: id(6), replacementId: id(30) }, config, false, id(40)), /Confirme/);
  const request = stageRuleRequest(current, { action: 'replace', ruleId: id(6), replacementId: id(30) }, config, true, id(40));
  assert.ok(request.action === 'replace'); assert.equal(request.etapa_id, id(6)); assert.equal(request.replacement_id, id(30));
  assert.equal(request.config.bloquear_avanco_sem_aprov, true); assert.equal(JSON.stringify(current.rules[0]), before);
  current.project.updated_at = 'later'; current.allocation.updated_at = 'later'; current.rules_version = 'b'.repeat(64); config.aprovadores_ids[0] = id(99);
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_allocation_updated_at, version); assert.equal(request.expected_etapa_updated_at, version);
  assert.equal(request.expected_rules_version, 'a'.repeat(64)); assert.equal(request.submissionId, id(40)); assert.deepEqual(request.config.aprovadores_ids, [id(20)]);
  assert.equal(Object.isFrozen(request.config.aprovadores_ids), true); assert.equal(Object.isFrozen(request.config), true); assert.equal(Object.isFrozen(request), true);
});

test('destination changes clear return selections and legacy singular configuration needs an explicit new list', () => {
  const current = snapshot(), config = stageRuleConfig(current.rules[0]);
  assert.equal(stageRuleDestinationChanged(config, id(4)), config);
  const changed = stageRuleDestinationChanged(config, id(5)); assert.deepEqual(changed.aprovadores_retorno_ids, []); assert.deepEqual(config.aprovadores_retorno_ids, [id(21)]);
  assert.equal(stageRuleConfigChanged(current.rules[0], config), false);
  assert.throws(() => stageRuleRequest(current, { action: 'replace', ruleId: id(6), replacementId: id(30) }, config, true, id(40)), /Altere/);
  current.rules[0].aprovador_id = id(20); current.rules[0].aprovadores_ids = [];
  const legacy = stageRuleConfig(current.rules[0]); assert.deepEqual(legacy.aprovadores_ids, []);
  assert.throws(() => stageRuleRequest(current, { action: 'replace', ruleId: id(6), replacementId: id(30) }, legacy, true, id(40)), /origem/);
  legacy.aprovadores_ids = [id(20)]; assert.equal(stageRuleConfigChanged(current.rules[0], legacy), true);
  assert.ok(stageRuleRequest(current, { action: 'replace', ruleId: id(6), replacementId: id(30) }, legacy, true, id(40)));
});

test('retirement and restoration keep the original ID, require confirmation and never create or delete inverse rules', () => {
  const current = snapshot();
  for (const [action, ruleId] of [['retire', id(6)], ['restore', id(7)]] as const) {
    assert.throws(() => stageRuleRequest(current, { action, ruleId }, emptyStageRuleConfig(), false, id(40)), /Confirme/);
    const request = stageRuleRequest(current, { action, ruleId }, emptyStageRuleConfig(), true, id(40));
    assert.equal(request.action, action); assert.ok(request.action === 'retire' || request.action === 'restore'); assert.equal(request.etapa_id, ruleId);
    assert.equal(request.expected_etapa_updated_at, version); assert.equal(request.confirm_change, true); assert.ok(!('config' in request)); assert.ok(!('related_return_ids' in request));
  }
  current.rules[1].can_restore = false; assert.throws(() => stageRuleRequest(current, { action: 'restore', ruleId: id(7) }, emptyStageRuleConfig(), true, id(40)), /não permite/);
});

test('finalizado origin remains configurable while used flags, closed contexts, incomplete sets and version ceilings constrain each action', () => {
  const current = snapshot(); assert.equal(canManageStageRules(current, true), true); assert.equal(canManageStageRules(current, false), false);
  for (const patch of [{ complete: false }, { allocations_complete: false }, { eligible_complete: false }, { memberships_complete: false },
    { allocation: { ...current.allocation, status: 'n_a' } }, { project: { ...current.project, closed: true } }]) {
    const value = { ...current, ...patch }; assert.equal(canManageStageRules(value, true), false);
    assert.throws(() => stageRuleRequest(value, { action: 'retire', ruleId: id(6) }, emptyStageRuleConfig(), true, id(40)), /Recarregue/);
  }
  const unavailable = { ...current, rules: current.rules.map(rule => ({ ...rule, can_edit: false, can_retire: false })) };
  assert.throws(() => stageRuleRequest(unavailable, { action: 'replace', ruleId: id(6), replacementId: id(30) }, stageRuleConfig(current.rules[0]), true, id(40)), /não permite/);
  const ceiling = { ...current, total: 1000 };
  assert.throws(() => stageRuleRequest(ceiling, { action: 'create', id: id(30) }, stageRuleConfig(current.rules[0]), false, id(40)), /limite/);
  assert.ok(stageRuleRequest(ceiling, { action: 'retire', ruleId: id(6) }, emptyStageRuleConfig(), true, id(40)));
});

test('homonym approvers are disambiguated by matrícula and active/retired pagination never mutates snapshot order', () => {
  const current = snapshot();
  const one = stageRulePersonLabel(current.eligible_users[0], current.eligible_users), two = stageRulePersonLabel(current.eligible_users[1], current.eligible_users);
  assert.match(one, /matrícula EM-20/); assert.match(two, /matrícula EM-21/); assert.notEqual(one, two);
  const rows = Array.from({ length: 26 }, (_, index) => ({ ...current.rules[0], id: id(100 + index) })); rows.push(current.rules[1]);
  const before = JSON.stringify(rows), first = stageRulePage(rows, false), last = stageRulePage(rows, false, 9);
  assert.equal(first.rows.length, 25); assert.equal(last.page, 2); assert.equal(last.rows.length, 1); assert.equal(first.total, 26);
  assert.deepEqual(stageRulePage(rows, true).rows.map(rule => rule.id), [id(7)]); assert.equal(JSON.stringify(rows), before);
});
