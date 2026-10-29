import { transitionStageApprovalSchema } from './stage-approval-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

export function createStageApprovalActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function transitionStageApproval(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.approvals.decide');
    if ('ok' in access) return access;
    // Operational eligibility is checked against the authenticated RM identity
    // under the project's transaction lock, using the same rules as mobile.
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)) return { ok: false, code: '42501', error: 'Seu perfil permite apenas consultar as aprovações.' };
    const parsed = transitionStageApprovalSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira a ação e a observação da etapa.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'transition_stage_approval', parsed.data, 'em.approvals.decide', access.sso);
    if (!result.ok) return result;
    // Do not forward receipt/private metadata or raw rows from the SQL envelope.
    const data = result.data;
    if (data.operation !== 'transition_stage_approval' || data.id !== parsed.data.aprovacao_etapa_id
      || typeof data.projeto_id !== 'string' || typeof data.updated_at !== 'string') {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a alteração. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id,
      updated_at: data.updated_at, idempotent_replay: data.idempotent_replay, record: {} } };
  }
  return { transitionStageApproval };
}
