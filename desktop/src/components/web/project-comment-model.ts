import type { EditProjectCommentInput, ProjectCommentSnapshot } from '@/server/web/project-comment-policy';
import { freezeEngineeringRequest } from './engineering-model';

export type ProjectCommentDraft = { evento: string; motivo: string };
export const projectCommentDraft = (snapshot: ProjectCommentSnapshot): ProjectCommentDraft => ({ evento: snapshot.comment.evento ?? '', motivo: '' });
export const projectCommentChanged = (snapshot: ProjectCommentSnapshot, draft: ProjectCommentDraft) => {
  const original = snapshot.comment.evento ?? '';
  return draft.evento !== original && draft.evento.trim() !== original;
};
export function projectCommentValidation(draft: ProjectCommentDraft) {
  if (!draft.evento.trim() || draft.evento.trim().length > 10_000 || draft.evento.includes('\u0000')) return 'Informe um comentário de até 10.000 caracteres.';
  if (!draft.motivo.trim() || draft.motivo.trim().length > 2_000 || draft.motivo.includes('\u0000')) return 'Informe o motivo da correção com até 2.000 caracteres.';
  return '';
}
export function projectCommentRequest(snapshot: ProjectCommentSnapshot, draft: ProjectCommentDraft, submissionId: string): EditProjectCommentInput {
  if (!snapshot.can_edit || snapshot.project.closed || snapshot.comment.projeto_id !== snapshot.project.id || !snapshot.allocation || snapshot.allocation.retirada) throw new Error('Este comentário está disponível somente para consulta.');
  const validation = projectCommentValidation(draft); if (validation) throw new Error(validation);
  if (!projectCommentChanged(snapshot, draft)) throw new Error('Altere o texto do comentário antes de confirmar.');
  return freezeEngineeringRequest({ submissionId, projeto_id: snapshot.project.id, comentario_id: snapshot.comment.id,
    expected_project_updated_at: snapshot.project.updated_at, expected_comment_updated_at: snapshot.comment.updated_at,
    expected_context_version: snapshot.context_version, evento: draft.evento.trim(), motivo: draft.motivo.trim(), confirm_change: true });
}
export function commentHistoryPage(value: string | string[] | undefined) {
  return typeof value === 'string' && /^[1-9]\d{0,5}$/.test(value) && Number(value) <= 100_000 ? Number(value) : 1;
}
