import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { editProjectCommentSchema, projectCommentResultSchema } from './project-comment-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });
export function createProjectCommentActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function editProjectComment(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.projects.manage'); if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.projects.read', 'em.history.read'] as const).every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar este comentário.' };
    }
    const parsed = editProjectCommentSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o comentário, informe o motivo e confirme a correção.', fieldErrors: parsed.error.flatten().fieldErrors };
    const value = parsed.data, result = await dependencies.mutate(access.client, 'edit_project_comment', value, 'em.projects.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = projectCommentResultSchema.safeParse(data.record);
    if (data.operation !== 'edit_project_comment' || data.id !== value.comentario_id || data.projeto_id !== value.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !record.success
      || record.data.projeto_id !== value.projeto_id || record.data.comentario_id !== value.comentario_id
      || record.data.changed && record.data.revision < 1) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a correção. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: record.data } };
  }
  return { editProjectComment };
}
