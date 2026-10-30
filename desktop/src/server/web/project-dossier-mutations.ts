import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { addProjectCommentSchema } from './project-dossier-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const version = z.string().datetime({ offset: true });
export function createProjectDossierActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function addProjectComment(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.projects.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.history.read'] as const).every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar os comentários deste projeto.' };
    }
    const parsed = addProjectCommentSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Escolha a célula destinatária e confira o comentário.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'add_project_comment', parsed.data, 'em.projects.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = data.record;
    if (data.operation !== 'add_project_comment' || data.id !== parsed.data.submissionId || data.projeto_id !== parsed.data.projeto_id
      || !version.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean'
      || !record || typeof record !== 'object' || record.projeto_id !== parsed.data.projeto_id || record.celula_projeto_id !== parsed.data.celula_projeto_id
      || record.evento !== parsed.data.evento || record.cadastrado_por_id !== access.profile.id) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar o comentário. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: { projeto_id: record.projeto_id, celula_projeto_id: record.celula_projeto_id,
        cadastrado_por_id: record.cadastrado_por_id, evento: record.evento } } };
  }
  return { addProjectComment };
}
