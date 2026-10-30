import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { manageStageRulesSchema, operationalStageRuleResultSchema } from './operational-stage-rule-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });
const reads = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.approvals.read'] as const;
export function createOperationalStageRuleActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function manageStageRules(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil) || !reads.every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar as regras de etapas.' };
    }
    const parsed = manageStageRulesSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira a configuração, os aprovadores e a confirmação antes de salvar.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'manage_stage_rules', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const value = parsed.data, data = result.data, record = operationalStageRuleResultSchema.safeParse(data.record);
    const target = value.action === 'create' ? value.id : value.action === 'replace' ? value.replacement_id : value.etapa_id;
    const previous = value.action === 'replace' ? value.etapa_id : null;
    const allowed = new Set(value.action === 'replace' ? [value.etapa_id, value.replacement_id] : [target]);
    if (data.operation !== 'manage_stage_rules' || data.id !== target || data.projeto_id !== value.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !record.success
      || record.data.projeto_id !== value.projeto_id || record.data.celula_projeto_id !== value.celula_projeto_id
      || record.data.action !== value.action || record.data.etapa_id !== target || record.data.previous_etapa_id !== previous
      || new Set(record.data.changed_ids).size !== record.data.changed_ids.length || record.data.changed_ids.some(id => !allowed.has(id))
      || (value.action === 'create' || value.action === 'replace') && record.data.changed_ids.length !== allowed.size) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a configuração. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      record: record.data, idempotent_replay: data.idempotent_replay } };
  }
  return { manageStageRules };
}
