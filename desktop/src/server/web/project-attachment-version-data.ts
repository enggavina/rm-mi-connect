import type { SupabaseClient } from '@supabase/supabase-js';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import { projectAttachmentSnapshotSchema, type ProjectAttachmentSnapshot } from './project-attachment-version-policy';
import { MAX_PROJECT_ATTACHMENT_BYTES } from './project-dossier-policy';

const scopes: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.documents.read'];
const unavailable = () => new Error('Não foi possível consultar as versões deste anexo. Recarregue a página para tentar novamente.');
export function createProjectAttachmentVersionData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectAttachment(projectId: string, attachmentId: string, historyPage: unknown = 1): Promise<ProjectAttachmentSnapshot | null> {
    if (capabilities !== undefined && !scopes.every(capability => capabilities.includes(capability))) throw new Error('Acesso não autorizado aos documentos.');
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(attachmentId).success) return null;
    projectId = projectId.toLowerCase(); attachmentId = attachmentId.toLowerCase();
    const page = typeof historyPage === 'string' && /^[1-9]\d{0,5}$/.test(historyPage) ? Number(historyPage) : historyPage;
    if (typeof page !== 'number' || !Number.isInteger(page) || page < 1 || page > 100_000) throw new Error('Confira a página do histórico.');
    let result;
    try { result = await client.rpc('rm_web_project_attachment_snapshot_v1', { p_project_id: projectId, p_attachment_id: attachmentId, p_history_page: page }); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable(); if (result.data === null) return null;
    const parsed = projectAttachmentSnapshotSchema.safeParse(result.data); if (!parsed.success) throw unavailable();
    const data = parsed.data, { series, history, attachment } = data;
    const closed = data.project.data_real_de_entrega !== null || ['cancelado', 'finalizando_para_faturar'].includes(data.project.status_pcp ?? '');
    if (data.project.id !== projectId || attachment.id !== attachmentId || attachment.projeto_id !== projectId || data.project.closed !== closed
      || !series && (data.can_replace || history.total !== 0)
      || series && (history.total !== series.head_revision || series.selected_revision > series.head_revision
        || (series.root_id === series.head_id) !== (series.head_revision === 1)
        || (attachment.id === series.root_id) !== (series.selected_revision === 1)
        || (attachment.id === series.head_id) !== (series.selected_revision === series.head_revision)
        || attachment.id === series.head_id && attachment.updated_at !== series.head_updated_at)
      || data.can_replace && (closed || !series || attachment.id !== series.head_id || !attachment.has_file || attachment.visivel_cliente !== false
        || !attachment.filename || !attachment.byte_size || attachment.byte_size > MAX_PROJECT_ATTACHMENT_BYTES)
      || history.page !== Math.min(page, Math.max(1, Math.ceil(history.total / 25)))
      || history.items.length !== Math.min(25, Math.max(0, history.total - (history.page - 1) * 25))
      || new Set(history.items.map(item => item.id)).size !== history.items.length
      || history.items.some((item, index) => item.projeto_id !== projectId || item.revision !== history.total - (history.page - 1) * 25 - index
        || (item.id === series?.head_id) !== (item.revision === series?.head_revision)
        || (item.id === series?.root_id) !== (item.revision === 1)
        || (item.id === attachment.id) !== (item.revision === series?.selected_revision)
        || item.current !== (item.id === series?.head_id && item.revision === series?.head_revision)
        || item.id === attachment.id && Object.keys(attachment).some(key => item[key as keyof typeof attachment] !== attachment[key as keyof typeof attachment])
        || item.id === series?.head_id && item.updated_at !== series.head_updated_at)) throw unavailable();
    return data;
  }
  return { getProjectAttachment };
}
export async function getProjectAttachment(projectId: string, attachmentId: string, historyPage: unknown = 1) {
  const { requireWebUser } = await import('./auth'); const access = await requireWebUser(scopes);
  return createProjectAttachmentVersionData(access.client, access.sso?.capabilities).getProjectAttachment(projectId, attachmentId, historyPage);
}
