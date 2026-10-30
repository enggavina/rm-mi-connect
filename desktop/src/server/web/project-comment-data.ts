import type { SupabaseClient } from '@supabase/supabase-js';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import { projectCommentSnapshotSchema, type ProjectCommentSnapshot } from './project-comment-policy';

const scopes: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.history.read'];
const unavailable = () => new Error('Não foi possível consultar este comentário. Recarregue a página para tentar novamente.');
export function createProjectCommentData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectComment(projectId: string, commentId: string, historyPage: unknown = 1): Promise<ProjectCommentSnapshot | null> {
    if (capabilities !== undefined && !scopes.every(capability => capabilities.includes(capability))) throw new Error('Acesso não autorizado aos comentários.');
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(commentId).success) return null;
    projectId = projectId.toLowerCase(); commentId = commentId.toLowerCase();
    const page = typeof historyPage === 'string' && /^[1-9]\d{0,5}$/.test(historyPage) ? Number(historyPage) : historyPage;
    if (typeof page !== 'number' || !Number.isInteger(page) || page < 1 || page > 100_000) throw new Error('Confira a página do histórico.');
    let result;
    try { result = await client.rpc('rm_web_project_comment_snapshot_v1', { p_project_id: projectId, p_comment_id: commentId, p_history_page: page }); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable(); if (result.data === null) return null;
    const parsed = projectCommentSnapshotSchema.safeParse(result.data); if (!parsed.success) throw unavailable();
    const data = parsed.data, history = data.history;
    const closed = data.project.data_real_de_entrega !== null || ['cancelado', 'finalizando_para_faturar'].includes(data.project.status_pcp ?? '');
    if (data.project.id !== projectId || data.comment.id !== commentId || data.comment.projeto_id !== projectId
      || data.project.closed !== closed || data.can_edit && (closed || !data.allocation || data.allocation.retirada || !data.comment.celula_id || !data.comment.cadastrado_por_id)
      || history.page !== Math.min(page, Math.max(1, Math.ceil(history.total / 25)))
      || history.items.length !== Math.min(25, Math.max(0, history.total - (history.page - 1) * 25))
      || new Set(history.items.map(item => item.id)).size !== history.items.length
      || history.items.some((item, index) => item.revision !== history.total - (history.page - 1) * 25 - index)) throw unavailable();
    return data;
  }
  return { getProjectComment };
}
export async function getProjectComment(projectId: string, commentId: string, historyPage: unknown = 1) {
  const { requireWebUser } = await import('./auth'); const access = await requireWebUser(scopes);
  return createProjectCommentData(access.client, access.sso?.capabilities).getProjectComment(projectId, commentId, historyPage);
}
