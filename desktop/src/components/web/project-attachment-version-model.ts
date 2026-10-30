import type { ProjectAttachmentSnapshot, ProjectAttachmentVersionInput } from '@/server/web/project-attachment-version-policy';
import { dossierAttachmentRequest, dossierExpiry, dossierFileError } from './project-dossier-model';
import { freezeEngineeringRequest } from './engineering-model';

export type AttachmentVersionDraft = { nome: string; descricao: string; status: string; expiry: string; motivo: string };
export function attachmentVersionDraft(snapshot: ProjectAttachmentSnapshot): AttachmentVersionDraft {
  const attachment = snapshot.attachment;
  return { nome: attachment.nome ?? '', descricao: attachment.descricao ?? '', status: attachment.status ?? '',
    expiry: attachment.data_vencimento?.slice(0, 10) ?? '', motivo: '' };
}
export function attachmentVersionEligible(snapshot: ProjectAttachmentSnapshot) {
  return snapshot.can_replace && !snapshot.project.closed && !!snapshot.series
    && snapshot.attachment.projeto_id === snapshot.project.id && snapshot.attachment.id === snapshot.series.head_id
    && snapshot.series.selected_revision === snapshot.series.head_revision
    && snapshot.attachment.updated_at === snapshot.series.head_updated_at && snapshot.attachment.has_file && snapshot.attachment.visivel_cliente === false;
}
export function attachmentVersionValidation(file: Pick<File, 'name' | 'size' | 'type'> | null, draft: AttachmentVersionDraft) {
  if (!file) return 'Selecione o novo arquivo PDF, JPEG ou PNG.';
  const error = dossierFileError(file); if (error) return error;
  if (!draft.nome.trim() || draft.nome.trim().length > 200 || draft.nome.includes('\u0000')) return 'Informe um título de até 200 caracteres para o anexo.';
  if (draft.descricao.trim().length > 2000 || draft.descricao.includes('\u0000')) return 'A observação deve ter até 2.000 caracteres.';
  if (!['No prazo', 'Vencido'].includes(draft.status)) return 'Selecione o status do documento.';
  try { dossierExpiry(draft.expiry); } catch { return 'Confira a data de vencimento.'; }
  if (!draft.motivo.trim() || draft.motivo.trim().length > 2000 || draft.motivo.includes('\u0000')) return 'Informe o motivo da substituição com até 2.000 caracteres.';
  return '';
}
export function attachmentVersionRequest(snapshot: ProjectAttachmentSnapshot, file: Pick<File, 'name' | 'size' | 'type'>,
  draft: AttachmentVersionDraft, sha256: string, submissionId: string): ProjectAttachmentVersionInput {
  if (!attachmentVersionEligible(snapshot)) throw new Error('Este anexo está disponível somente para consulta. Abra a versão atual para conferir a substituição.');
  const error = attachmentVersionValidation(file, draft); if (error) throw new Error(error);
  const base = dossierAttachmentRequest(snapshot.project.id, snapshot.project.updated_at, file, draft, sha256, submissionId);
  return freezeEngineeringRequest({ ...base, mime_type: file.type as ProjectAttachmentVersionInput['mime_type'], source_attachment_id: snapshot.attachment.id,
    expected_attachment_updated_at: snapshot.attachment.updated_at, expected_context_version: snapshot.context_version,
    motivo: draft.motivo.trim(), confirm_change: true });
}
export function attachmentHistoryPage(value: string | string[] | undefined) {
  return typeof value === 'string' && /^[1-9]\d{0,5}$/.test(value) && Number(value) <= 100_000 ? Number(value) : 1;
}
export function attachmentFileSize(value: number | null) {
  if (value === null) return 'Tamanho não informado';
  return value < 1024 * 1024 ? `${Math.max(1, Math.ceil(value / 1024)).toLocaleString('pt-BR')} KiB`
    : `${(value / 1024 / 1024).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} MiB`;
}
