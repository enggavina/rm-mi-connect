import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createFormReviewerAssignmentData } from '../src/server/web/form-reviewer-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T00:03:24.123456+00:00';
const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.forms.read', 'em.planning.manage'];
function snapshot() {
  return {
    project: { id: id(1), numero: 'OS1', status_pcp: null as string | null, data_real_de_entrega: null, updated_at: version, closed: false, arquivo_url: 'private-file' },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(3), celula_nome: 'Peritagem', status: null as string | null, updated_at: version },
    forms: [{ id: id(4), titulo: 'Inspeção', linked: true,
      assignment: { id: id(5), avaliador_user_id: id(8), avaliador_nome: 'Avaliador', updated_at: version, eligible: true, auth_user_id: 'private-auth' },
      records: [{ id: id(6), status: 'em_an_lise', preenchido: true, avaliador_user_id: null as string | null, avaliador_nome: null as string | null, updated_at: version, respostas: 'private-answers' }],
      can_assign: true, action_reason: null as string | null, context_version: 'a'.repeat(64), private_data: 'private' },
    { id: id(10), titulo: 'Histórico', linked: false, assignment: null,
      records: [{ id: id(11), status: 'aprovado', preenchido: true, avaliador_user_id: id(12), avaliador_nome: 'Avaliador antigo', updated_at: version, respostas: 'private-answers' }],
      can_assign: false, action_reason: 'Formulário fora do vínculo atual.', context_version: 'b'.repeat(64), private_data: 'private' }],
    eligible_users: [{ id: id(8), nome: 'Avaliador', matricula: 'EM-008', email: 'private-email', auth_user_id: 'private-auth' }, { id: id(9), nome: 'Avaliador', matricula: null, email: 'private-email', auth_user_id: 'private-auth' }],
    total: 2, complete: true, records_total: 2, records_complete: true, eligible_total: 2, eligible_complete: true, private_data: 'private',
  };
}
function fixture(caps: readonly CorporateCapability[] = capabilities) {
  let current: unknown = snapshot(), error: unknown = null, thrown = false;
  const calls: { name: string; args: unknown }[] = [];
  const client = { async rpc(name: string, args: unknown) { calls.push({ name, args }); if (thrown) throw new Error('private-upstream'); return { data: current, error }; } } as unknown as SupabaseClient;
  return { reader: createFormReviewerAssignmentData(client, caps), calls, set(value: unknown) { current = value; }, fail(value: unknown) { error = value; }, throw() { thrown = true; } };
}

test('reviewer assignment reads require domain grants and planning management for candidate choices', async () => {
  for (const missing of ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.forms.read'] as CorporateCapability[]) {
    const f = fixture(capabilities.filter(capability => capability !== missing));
    await assert.rejects(f.reader.getFormReviewerAssignments(id(1), id(2)), /Acesso/); assert.deepEqual(f.calls, []);
  }
  const f = fixture(capabilities.filter(capability => capability !== 'em.planning.manage'));
  await assert.rejects(f.reader.getFormReviewerAssignments(id(1), id(2), true), /Acesso/); assert.deepEqual(f.calls, []);
  assert.equal(await f.reader.getFormReviewerAssignments('invalid', id(2)), null); assert.deepEqual(f.calls, []);
  assert.ok(await f.reader.getFormReviewerAssignments(id(1), id(2)));
});

test('one atomic reviewer snapshot preserves legacy divergence and exact revisions but strips global/private data', async () => {
  const f = fixture(), result = await f.reader.getFormReviewerAssignments(id(1), id(2), true); assert.ok(result);
  assert.equal(result.project.updated_at, version); assert.equal(result.allocation.updated_at, version);
  assert.equal(result.forms[0].assignment?.updated_at, version); assert.equal(result.forms[0].records[0].updated_at, version);
  assert.equal(result.forms[0].records[0].avaliador_user_id, null, 'Import metadata must not silently rewrite the record evaluator.');
  assert.equal(result.forms[1].linked, false); assert.equal(result.forms[1].records[0].status, 'aprovado');
  assert.equal(result.eligible_users[0].nome, result.eligible_users[1].nome); assert.notEqual(result.eligible_users[0].id, result.eligible_users[1].id);
  assert.equal(result.eligible_users[0].matricula, 'EM-008'); assert.equal(result.eligible_users[1].matricula, null);
  assert.ok(!JSON.stringify(result).includes('private'));
  assert.deepEqual(f.calls, [{ name: 'rm_web_form_reviewer_assignments_snapshot_v1', args: { p_project_id: id(1), p_allocation_id: id(2), p_include_eligible: true } }]);
  const readonly = await f.reader.getFormReviewerAssignments(id(1), id(2));
  assert.deepEqual(readonly?.eligible_users, []); assert.equal(readonly?.eligible_total, 2);
  assert.equal(readonly?.forms[0].assignment?.avaliador_nome, 'Avaliador');
});

test('reviewer snapshot rejects crossed context, duplicate identities/records, misleading flags and partial collections', async () => {
  const f = fixture();
  const cases: unknown[] = [
    { ...snapshot(), project: { ...snapshot().project, id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, projeto_id: id(99) } },
    { ...snapshot(), project: { ...snapshot().project, closed: true } },
    { ...snapshot(), project: { ...snapshot().project, status_pcp: 'cancelado', closed: true } },
    { ...snapshot(), allocation: { ...snapshot().allocation, status: 'finalizado' } },
    { ...snapshot(), total: 3 }, { ...snapshot(), records_total: 3 }, { ...snapshot(), eligible_total: 3 },
    { ...snapshot(), complete: false }, { ...snapshot(), records_complete: false }, { ...snapshot(), eligible_complete: false },
    { ...snapshot(), eligible_users: [...snapshot().eligible_users, snapshot().eligible_users[0]], eligible_total: 3 },
    { ...snapshot(), forms: [...snapshot().forms, snapshot().forms[0]], total: 3, records_total: 3 },
  ];
  for (const patch of [{ linked: false }, { context_version: 'not-a-hash' }, { records: [{ ...snapshot().forms[0].records[0], status: 'aprovado' }] },
    { assignment: { ...snapshot().forms[0].assignment!, eligible: false } }]) {
    const value = snapshot(); value.forms[0] = { ...value.forms[0], ...patch } as typeof value.forms[number]; cases.push(value);
  }
  const repeatedRecord = snapshot(); repeatedRecord.forms[1].records[0].id = repeatedRecord.forms[0].records[0].id; cases.push(repeatedRecord);
  const repeatedAssignment = snapshot(); repeatedAssignment.forms[1].assignment = repeatedAssignment.forms[0].assignment; cases.push(repeatedAssignment);
  for (const value of cases) { f.set(value); await assert.rejects(f.reader.getFormReviewerAssignments(id(1), id(2), true), /Não foi possível/); }
});

test('reviewer snapshot handles empty pre-registration, lost eligibility and hard limits without truncated management', async () => {
  const f = fixture();
  const preregistration = snapshot(); preregistration.forms[0].records = []; preregistration.records_total--;
  f.set(preregistration); assert.equal((await f.reader.getFormReviewerAssignments(id(1), id(2), true))?.forms[0].records.length, 0);
  const invalidReviewer = snapshot(); invalidReviewer.forms[0].assignment!.eligible = false;
  invalidReviewer.eligible_users = [invalidReviewer.eligible_users[1]]; invalidReviewer.eligible_total = 1;
  f.set(invalidReviewer); assert.equal((await f.reader.getFormReviewerAssignments(id(1), id(2), true))?.forms[0].assignment?.eligible, false);
  for (const value of [
    { ...snapshot(), total: 1001, complete: false, forms: [] },
    { ...snapshot(), records_total: 2001, records_complete: false, forms: [] },
    { ...snapshot(), eligible_total: 1001, eligible_complete: false, eligible_users: [], forms: snapshot().forms.map(form => ({ ...form, can_assign: false })) },
  ]) { f.set(value); assert.ok(await f.reader.getFormReviewerAssignments(id(1), id(2), true)); }
  f.set(null); assert.equal(await f.reader.getFormReviewerAssignments(id(1), id(2)), null);
  f.fail({ message: 'private-upstream' });
  await assert.rejects(f.reader.getFormReviewerAssignments(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
  const throws = fixture(); throws.throw();
  await assert.rejects(throws.reader.getFormReviewerAssignments(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
});
