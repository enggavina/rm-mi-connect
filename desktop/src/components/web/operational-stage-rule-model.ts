import type { OperationalStageRule, OperationalStageRulePerson, OperationalStageRuleSnapshot } from '@/server/web/operational-stage-rule-data';
import type { ManageStageRulesInput } from '@/server/web/operational-stage-rule-policy';
import { freezeEngineeringRequest } from './engineering-model';
import { formReviewerChoiceLabel } from './form-reviewer-model';

export type StageRuleConfig = {
  celula_destino_id: string; status_cel_proj: string; bloquear_avanco_sem_aprov: boolean; aprovadores_ids: string[]; aprovadores_retorno_ids: string[];
};
export type StageRuleMode = { action: 'create'; id: string } | { action: 'replace'; ruleId: string; replacementId: string } | { action: 'retire' | 'restore'; ruleId: string };
export const emptyStageRuleConfig = (): StageRuleConfig => ({ celula_destino_id: '', status_cel_proj: '', bloquear_avanco_sem_aprov: false, aprovadores_ids: [], aprovadores_retorno_ids: [] });
export const stageRuleConfig = (rule: OperationalStageRule): StageRuleConfig => ({
  celula_destino_id: rule.celula_destino_id ?? '', status_cel_proj: rule.status_cel_proj ?? '', bloquear_avanco_sem_aprov: rule.bloquear_avanco_sem_aprov,
  aprovadores_ids: [...rule.aprovadores_ids], aprovadores_retorno_ids: [...rule.aprovadores_retorno_ids],
});
export const stageRuleDestinationChanged = (config: StageRuleConfig, destination: string): StageRuleConfig => config.celula_destino_id === destination ? config
  : { ...config, celula_destino_id: destination, aprovadores_retorno_ids: [] };
export function canManageStageRules(snapshot: OperationalStageRuleSnapshot, permitted: boolean) {
  return permitted && snapshot.complete && snapshot.allocations_complete && snapshot.eligible_complete && snapshot.memberships_complete
    && !snapshot.project.closed && snapshot.allocation.status !== 'n_a';
}
export function stageRuleConfigChanged(rule: OperationalStageRule, config: StageRuleConfig) {
  const equal = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every(id => b.includes(id));
  return rule.aprovador_id !== null || rule.celula_destino_id !== config.celula_destino_id || rule.status_cel_proj !== config.status_cel_proj
    || rule.bloquear_avanco_sem_aprov !== config.bloquear_avanco_sem_aprov || !equal(rule.aprovadores_ids, config.aprovadores_ids) || !equal(rule.aprovadores_retorno_ids, config.aprovadores_retorno_ids);
}
export function stageRulePeople(snapshot: OperationalStageRuleSnapshot, cellId: string) {
  return snapshot.eligible_users.filter(user => user.celula_ids.includes(cellId));
}
export function stageRulePage(rules: readonly OperationalStageRule[], retired: boolean, requested = 1) {
  const rows = rules.filter(rule => rule.ativo !== retired), pages = Math.max(1, Math.ceil(rows.length / 25));
  const page = Math.min(pages, Math.max(1, Number.isInteger(requested) ? requested : 1));
  return { rows: rows.slice((page - 1) * 25, page * 25), total: rows.length, page, pages };
}
export function stageRulePersonLabel(person: Pick<OperationalStageRulePerson, 'id' | 'nome' | 'matricula'>, people: readonly Pick<OperationalStageRulePerson, 'id' | 'nome' | 'matricula'>[]) {
  return formReviewerChoiceLabel({ ...person, nome: person.nome || 'Identidade não disponível' }, people.map(user => ({ ...user, nome: user.nome || 'Identidade não disponível' })));
}
export function stageRuleRequest(snapshot: OperationalStageRuleSnapshot, mode: StageRuleMode, config: StageRuleConfig, confirmed: boolean, submissionId: string): ManageStageRulesInput {
  if (!canManageStageRules(snapshot, true)) throw new Error('Recarregue as regras desta célula antes de alterar o planejamento.');
  if ((mode.action === 'create' || mode.action === 'replace') && snapshot.total >= 1000) throw new Error('Este projeto atingiu o limite de versões de regras nesta tela.');
  const common = { submissionId, projeto_id: snapshot.project.id, celula_projeto_id: snapshot.allocation.id,
    expected_project_updated_at: snapshot.project.updated_at, expected_allocation_updated_at: snapshot.allocation.updated_at, expected_rules_version: snapshot.rules_version };
  const rule = mode.action !== 'create' ? snapshot.rules.find(item => item.id === mode.ruleId) : undefined;
  if (mode.action !== 'create') {
    const allowed = mode.action === 'replace' ? rule?.can_edit : mode.action === 'retire' ? rule?.can_retire : rule?.can_restore;
    if (!rule || !allowed) throw new Error('Esta regra não permite a alteração solicitada. Recarregue as etapas.');
    if (!confirmed) throw new Error('Confirme a alteração da regra antes de continuar.');
    if (mode.action === 'retire' || mode.action === 'restore') return freezeEngineeringRequest({ ...common, action: mode.action, etapa_id: rule.id, expected_etapa_updated_at: rule.updated_at, confirm_change: true });
  }
  const status = snapshot.statuses.find(item => item.key === config.status_cel_proj);
  if (!status) throw new Error('Selecione um status válido para a liberação.');
  const destination = snapshot.destinations.find(item => item.celula_id === config.celula_destino_id && item.can_select);
  if (!destination || destination.celula_id === snapshot.allocation.celula_id || ['finalizado', 'n_a'].includes(destination.status ?? '')) throw new Error('Selecione uma célula de destino disponível deste projeto.');
  for (const [ids, cell, label] of [[config.aprovadores_ids, snapshot.allocation.celula_id, 'origem'], [config.aprovadores_retorno_ids, destination.celula_id, 'retorno']] as const) {
    if (!ids.length || ids.length > 100 || new Set(ids).size !== ids.length || ids.some(id => !stageRulePeople(snapshot, cell).some(user => user.id === id))) {
      throw new Error(`Selecione entre 1 e 100 aprovadores diferentes e elegíveis na célula de ${label}.`);
    }
  }
  const fields = { celula_destino_id: destination.celula_id, status_cel_proj: status.key, bloquear_avanco_sem_aprov: config.bloquear_avanco_sem_aprov,
    aprovadores_ids: [...config.aprovadores_ids], aprovadores_retorno_ids: [...config.aprovadores_retorno_ids] };
  if (mode.action === 'create') return freezeEngineeringRequest({ ...common, action: 'create', id: mode.id, config: fields });
  if (!rule || mode.action !== 'replace' || mode.replacementId === rule.id) throw new Error('A substituição precisa criar uma nova regra.');
  if (!stageRuleConfigChanged(rule, config)) throw new Error('Altere a configuração antes de substituir esta regra.');
  return freezeEngineeringRequest({ ...common, action: 'replace', etapa_id: rule.id, expected_etapa_updated_at: rule.updated_at, replacement_id: mode.replacementId, config: fields, confirm_change: true });
}
