import test from 'node:test';
import assert from 'node:assert/strict';
import type { FormReviewerAssignmentSnapshot } from '../src/server/web/form-reviewer-data';
import { assignFormReviewerRequest, canManageFormReviewers, formReviewerAssignedLabel, formReviewerChange, formReviewerChoiceLabel, formReviewerHasDivergence } from '../src/components/web/form-reviewer-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T00:03:24.123456+00:00';
function snapshot(): FormReviewerAssignmentSnapshot {
  return {
    project: { id: id(1), numero: 'OS1', status_pcp: null, data_real_de_entrega: null, updated_at: version, closed: false },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(3), celula_nome: 'Peritagem', status: null, updated_at: version },
    forms: [{ id: id(4), titulo: 'Inspeção', linked: true, assignment: null, records: [], can_assign: true, action_reason: null, context_version: 'a'.repeat(64) }],
    eligible_users: [{ id: id(8), nome: 'Avaliador', matricula: 'EM-008' }, { id: id(9), nome: 'Avaliador', matricula: 'EM-009' }],
    total: 1, complete: true, records_total: 0, records_complete: true, eligible_total: 2, eligible_complete: true,
  };
}
const record = (evaluator: string | null, n = 6) => ({ id: id(n), status: 'em_an_lise', preenchido: true, avaliador_user_id: evaluator, avaliador_nome: evaluator ? 'Nome do registro' : null, updated_at: version });

test('first reviewer assignment needs explicit eligible identity and no synthetic form record', () => {
  const current = snapshot(), request = assignFormReviewerRequest(current, id(4), id(8), false, id(20));
  assert.equal(request.avaliador_user_id, id(8)); assert.equal(request.confirm_replace, false);
  assert.equal(request.form_id, id(4)); assert.equal(request.celula_projeto_id, id(2));
  assert.ok(!('registro_formulario_id' in request)); assert.ok(!('assignment_id' in request));
  assert.ok(!('status' in request)); assert.ok(!('aprovadores_ids' in request)); assert.ok(!('actor_id' in request));
  assert.throws(() => assignFormReviewerRequest(current, id(4), id(99), false, id(20)), /elegível/);
  assert.throws(() => assignFormReviewerRequest(current, id(99), id(8), false, id(20)), /Recarregue/);
});

test('reviewer attempts freeze exact revisions and target independently from later input changes', () => {
  const current = snapshot(), request = assignFormReviewerRequest(current, id(4), id(8), false, id(20));
  current.project.updated_at = 'later'; current.allocation.updated_at = 'later'; current.forms[0].context_version = 'b'.repeat(64); current.eligible_users[0].id = id(99);
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_allocation_updated_at, version);
  assert.equal(request.expected_context_version, 'a'.repeat(64)); assert.equal(request.avaliador_user_id, id(8)); assert.equal(request.submissionId, id(20));
  assert.equal(Object.isFrozen(request), true);
});

test('changing or reapplying a reviewer confirms all existing records while unchanged assignments need no write', () => {
  const current = snapshot(), form = current.forms[0];
  form.assignment = { id: id(5), avaliador_user_id: id(8), avaliador_nome: 'Avaliador', updated_at: version, eligible: true };
  assert.equal(formReviewerChange(form, id(8)).needsChange, false);
  assert.throws(() => assignFormReviewerRequest(current, id(4), id(8), true, id(20)), /já está aplicado/);
  assert.throws(() => assignFormReviewerRequest(current, id(4), id(9), false, id(20)), /Confirme/);
  const changed = assignFormReviewerRequest(current, id(4), id(9), true, id(20)); assert.equal(changed.confirm_replace, true);
  form.records = [record(null), record(id(9), 7), record(id(8), 10)]; current.records_total = 3;
  assert.equal(formReviewerHasDivergence(form), true);
  const reapply = formReviewerChange(form, id(8));
  assert.equal(reapply.reapply, true); assert.equal(reapply.differentRecords, 2); assert.equal(reapply.unassignedRecords, 1); assert.equal(reapply.requiresConfirmation, true);
  assert.throws(() => assignFormReviewerRequest(current, id(4), id(8), false, id(20)), /Confirme/);
  assert.equal(assignFormReviewerRequest(current, id(4), id(8), true, id(20)).avaliador_user_id, id(8));
});

test('legacy record reviewers remain separate from prospective assignment and require confirmation only when replaced', () => {
  const current = snapshot(), form = current.forms[0]; form.records = [record(null), record(id(9), 7)]; current.records_total = 2;
  assert.equal(formReviewerHasDivergence(form), true); assert.equal(formReviewerChange(form, id(8)).requiresConfirmation, true);
  assert.throws(() => assignFormReviewerRequest(current, id(4), id(8), false, id(20)), /Confirme/);
  assert.equal(assignFormReviewerRequest(current, id(4), id(9), false, id(20)).confirm_replace, false, 'First designation may match legacy evaluators without replacing a different non-null evaluator.');
  assert.equal(formReviewerChange(form, id(9)).needsChange, true, 'An explicit prospective assignment must still be created.');
});

test('any approved record, unlinked historical form, terminal context or incomplete set blocks reviewer writes', () => {
  const current = snapshot(); assert.equal(canManageFormReviewers(current, false), false);
  for (const patch of [{ complete: false }, { records_complete: false }, { eligible_complete: false }, { project: { ...current.project, closed: true } },
    { allocation: { ...current.allocation, status: 'finalizado' } }, { allocation: { ...current.allocation, status: 'n_a' } }]) {
    const changed = { ...current, ...patch }; assert.equal(canManageFormReviewers(changed, true), false);
    assert.throws(() => assignFormReviewerRequest(changed, id(4), id(8), false, id(20)), /Recarregue/);
  }
  for (const patch of [{ linked: false }, { can_assign: false }, { records: [record(null), { ...record(id(9), 7), status: 'aprovado' }] }]) {
    const changed = { ...current, forms: [{ ...current.forms[0], ...patch }] };
    assert.throws(() => assignFormReviewerRequest(changed, id(4), id(8), true, id(20)), /Recarregue/);
  }
});

test('equal reviewer names remain distinct eligible identities and lost eligibility never reappears by name', () => {
  const current = snapshot();
  assert.notEqual(formReviewerChoiceLabel(current.eligible_users[0], current.eligible_users), formReviewerChoiceLabel(current.eligible_users[1], current.eligible_users));
  assert.match(formReviewerChoiceLabel(current.eligible_users[0], current.eligible_users), /matrícula EM-008/);
  const unnamed = current.eligible_users.map(user => ({ ...user, matricula: null }));
  assert.notEqual(formReviewerChoiceLabel(unnamed[0], unnamed), formReviewerChoiceLabel(unnamed[1], unnamed));
  assert.ok(!formReviewerChoiceLabel(unnamed[0], unnamed).includes(unnamed[0].id));
  const collision = [{ ...unnamed[0], id: '11111111-0000-4000-8000-000000000008' }, unnamed[0]];
  assert.notEqual(formReviewerChoiceLabel(collision[0], collision), formReviewerChoiceLabel(collision[1], collision));
  assert.equal(formReviewerAssignedLabel(current.forms[0], current.eligible_users), null);
  assert.equal(assignFormReviewerRequest(current, id(4), id(9), false, id(20)).avaliador_user_id, id(9));
  current.forms[0].assignment = { id: id(5), avaliador_user_id: id(8), avaliador_nome: 'Avaliador', updated_at: version, eligible: true };
  assert.match(formReviewerAssignedLabel(current.forms[0], current.eligible_users)!, /matrícula EM-008/);
  current.eligible_users = [current.eligible_users[1]]; current.eligible_total = 1;
  current.forms[0].assignment.eligible = false;
  assert.equal(formReviewerAssignedLabel(current.forms[0], current.eligible_users), 'Avaliador', 'A missing historical identity must not match another person by name.');
  assert.throws(() => assignFormReviewerRequest(current, id(4), id(8), true, id(20)), /elegível/);
  assert.equal(assignFormReviewerRequest(current, id(4), id(9), true, id(20)).avaliador_user_id, id(9));
});
