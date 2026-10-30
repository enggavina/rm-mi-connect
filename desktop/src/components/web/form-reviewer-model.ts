import type { FormReviewerAssignmentForm, FormReviewerAssignmentSnapshot } from '@/server/web/form-reviewer-data';
import type { AssignFormReviewerInput } from '@/server/web/form-reviewer-policy';
import { freezeEngineeringRequest } from './engineering-model';

export function canManageFormReviewers(snapshot: FormReviewerAssignmentSnapshot, permitted: boolean) {
  return permitted && snapshot.complete && snapshot.records_complete && snapshot.eligible_complete && !snapshot.project.closed
    && !['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '');
}

export function formReviewerChange(form: FormReviewerAssignmentForm, candidateId: string) {
  const differentRecords = form.records.filter(record => record.avaliador_user_id !== candidateId);
  return {
    needsChange: !!candidateId && (form.assignment === null || form.assignment.avaliador_user_id !== candidateId || differentRecords.length > 0),
    requiresConfirmation: form.assignment !== null || form.records.some(record => record.avaliador_user_id !== null && record.avaliador_user_id !== candidateId),
    reapply: form.assignment?.avaliador_user_id === candidateId && differentRecords.length > 0,
    differentRecords: differentRecords.length,
    unassignedRecords: form.records.filter(record => record.avaliador_user_id === null).length,
  };
}

export function formReviewerHasDivergence(form: FormReviewerAssignmentForm) {
  return form.assignment ? form.records.some(record => record.avaliador_user_id !== form.assignment?.avaliador_user_id)
    : new Set(form.records.map(record => record.avaliador_user_id)).size > 1;
}

/** Equal names are not identities: retain both IDs and distinguish them visibly. */
export function formReviewerChoiceLabel(user: FormReviewerAssignmentSnapshot['eligible_users'][number], users: FormReviewerAssignmentSnapshot['eligible_users']) {
  const homonyms = users.filter(other => other.nome.trim().toLocaleLowerCase('pt-BR') === user.nome.trim().toLocaleLowerCase('pt-BR'));
  if (homonyms.length < 2) return user.nome;
  if (user.matricula?.trim()) return `${user.nome} · matrícula ${user.matricula}`;
  const withoutRegistration = homonyms.filter(other => !other.matricula?.trim()).sort((a, b) => a.id.localeCompare(b.id));
  if (withoutRegistration.length < 2) return `${user.nome} · matrícula não informada`;
  // Prefer a short suffix. The ordinal only disambiguates a rare suffix collision.
  const suffix = user.id.replaceAll('-', '').slice(-8);
  const collision = withoutRegistration.filter(other => other.id.replaceAll('-', '').slice(-8) === suffix);
  return `${user.nome} · identidade ${suffix}${collision.length > 1 ? ` (${collision.findIndex(other => other.id === user.id) + 1})` : ''}`;
}

export function formReviewerAssignedLabel(form: FormReviewerAssignmentForm, users: FormReviewerAssignmentSnapshot['eligible_users']): string | null {
  if (!form.assignment) return null;
  const user = form.assignment.eligible ? users.find(candidate => candidate.id === form.assignment?.avaliador_user_id) : undefined;
  return user ? formReviewerChoiceLabel(user, users) : form.assignment.avaliador_nome || 'Identidade não disponível';
}

/** A retry keeps this exact reviewer, protocol and all PostgreSQL revision strings. */
export function assignFormReviewerRequest(snapshot: FormReviewerAssignmentSnapshot, formId: string, candidateId: string, confirmed: boolean, submissionId: string): AssignFormReviewerInput {
  const form = snapshot.forms.find(item => item.id === formId);
  if (!canManageFormReviewers(snapshot, true) || !form?.can_assign || !form.linked || form.records.some(record => record.status === 'aprovado')) {
    throw new Error('Recarregue os formulários desta célula antes de atribuir um avaliador.');
  }
  if (!snapshot.eligible_users.some(user => user.id === candidateId)) throw new Error('Selecione um avaliador elegível desta célula.');
  const change = formReviewerChange(form, candidateId);
  if (!change.needsChange) throw new Error('Este avaliador já está aplicado aos registros e aos próximos envios.');
  if (change.requiresConfirmation && !confirmed) throw new Error('Confirme a troca ou reaplicação do avaliador antes de continuar.');
  return freezeEngineeringRequest({
    submissionId, projeto_id: snapshot.project.id, celula_projeto_id: snapshot.allocation.id, form_id: form.id, avaliador_user_id: candidateId,
    expected_project_updated_at: snapshot.project.updated_at, expected_allocation_updated_at: snapshot.allocation.updated_at,
    expected_context_version: form.context_version, confirm_replace: confirmed,
  });
}
