import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { uuid } from './policy';
import { assignFormReviewerSchema, formReviewerResultSchema } from './form-reviewer-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });
const readCapabilities = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.forms.read'] as const;

export function createFormReviewerActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function assignFormReviewer(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !readCapabilities.every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar os avaliadores dos formulários.' };
    }
    const parsed = assignFormReviewerSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o avaliador e recarregue os dados da célula antes de salvar.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'assign_form_reviewer', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = formReviewerResultSchema.safeParse(data.record);
    if (data.operation !== 'assign_form_reviewer' || !uuid.safeParse(data.id).success || !timestamp.safeParse(data.updated_at).success
      || data.projeto_id !== parsed.data.projeto_id || typeof data.idempotent_replay !== 'boolean' || !record.success
      || data.id !== record.data.assignment_id || record.data.projeto_id !== parsed.data.projeto_id
      || record.data.celula_projeto_id !== parsed.data.celula_projeto_id || record.data.form_id !== parsed.data.form_id
      || record.data.avaliador_user_id !== parsed.data.avaliador_user_id
      || new Set(record.data.records_updated_ids).size !== record.data.records_updated_ids.length) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a atribuição do avaliador. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: record.data } };
  }
  return { assignFormReviewer };
}
