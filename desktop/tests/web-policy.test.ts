import assert from 'node:assert/strict';
import test from 'node:test';
import { documentSource, documentTarget, mutationError, pageNumber, planCellSchema, reviewFormSchema, saveProjectSchema, searchTerm } from '../src/server/web/policy';

const id = '49c12f88-1074-4c38-814d-3b2b95cb727d';
const timestamp = '2026-10-29T01:00:00.123456+00:00';
test('web mutations reject actor injection, unknown changes, stale-version omission and invalid planning fields', () => {
  const valid = { submissionId: id, id, expected_updated_at: timestamp, changes: { nome: 'Motor', cliente_id: id } };
  assert.equal(saveProjectSchema.safeParse(valid).success, true);
  assert.equal(saveProjectSchema.safeParse({ ...valid, actor_id: id }).success, false);
  assert.equal(saveProjectSchema.safeParse({ ...valid, changes: { auth_user_id: id } }).success, false);
  assert.equal(saveProjectSchema.safeParse({ ...valid, expected_updated_at: undefined }).success, false);
  const planning = { submissionId: id, projeto_id: id, celula_id: id, expected_updated_at: null, changes: { visibilidade: false, horas_previstas: 0, forms_ids: [id] } };
  assert.equal(planCellSchema.safeParse(planning).success, true);
  assert.equal(planCellSchema.safeParse({ ...planning, changes: { status: 'finalizado' } }).success, false);
  assert.equal(planCellSchema.safeParse({ ...planning, changes: { horas_previstas: -1 } }).success, false);
});
test('return decision requires explicit answers and explanation; approve cannot carry a correction list', () => {
  const input = { submissionId: id, registro_formulario_id: id, expected_updated_at: timestamp, decision: 'return', parecer: 'Conferir medida', resposta_ids: [id] };
  assert.equal(reviewFormSchema.safeParse(input).success, true);
  assert.equal(reviewFormSchema.safeParse({ ...input, resposta_ids: [] }).success, false);
  assert.equal(reviewFormSchema.safeParse({ ...input, parecer: ' ' }).success, false);
  assert.equal(reviewFormSchema.safeParse({ ...input, resposta_ids: [id, id] }).success, false);
  assert.equal(reviewFormSchema.safeParse({ ...input, decision: 'approve' }).success, false);
  assert.equal(reviewFormSchema.safeParse({ ...input, decision: 'approve', resposta_ids: [] }).success, true);
});
test('private documents require the configured Storage origin and safe object path; legacy redirect never accepts arbitrary URLs', () => {
  const base = 'https://project.supabase.co';
  assert.deepEqual(documentTarget(`${base}/storage/v1/object/authenticated/rm-documentos/legacy/${id}.pdf`, base), { kind: 'private', bucket: 'rm-documentos', path: `legacy/${id}.pdf` });
  for (const url of ['http://127.0.0.1/secret', 'https://evil.test/report.pdf', 'https://project.supabase.co.evil.test/storage/v1/object/authenticated/rm-documentos/a.pdf', `${base}/storage/v1/object/authenticated/rm-documentos/%252e%252e/report.pdf?token=x`, `${base}/storage/v1/object/authenticated/rm-documentos/%2fetc`, `${base}/storage/v1/object/authenticated/rm-documentos/a%5cb.pdf`, `${base}/storage/v1/object/public/rm-documentos/a.pdf`]) assert.equal(documentTarget(url, base), null);
  const legacy = 'https://files.cdn.bubble.io/a.pdf';
  assert.deepEqual(documentTarget(legacy, base), { kind: 'external', url: legacy });
  assert.equal(documentTarget('https://u:p@files.cdn.bubble.io/a.pdf', base), null);
  assert.equal(documentTarget('https://files.cdn.bubble.io.evil.test/a.pdf', base), null);
  assert.equal(documentTarget(`${base}/storage/v1/object/authenticated/rm-documentos/%252e%252e/report.pdf`, base), null);
  assert.deepEqual(documentSource('invoice'), { table: 'rm_projetos', column: 'arquivo_nota_fiscal_url' });
  assert.deepEqual(documentSource('docs'), { table: 'rm_docs', column: 'arquivo_url' });
  assert.deepEqual(documentSource(null), { table: 'rm_documentos', column: 'arquivo_url' });
  assert.equal(documentSource('rm_users'), null);
});
test('filter syntax and pagination cannot be supplied through the search field', () => {
  assert.equal(pageNumber(-1), 1); assert.equal(pageNumber('2'), 2); assert.equal(pageNumber(Infinity), 1);
  assert.equal(pageNumber(1_000_000), 10_000);
  assert.equal(/[,%_()*"\\.]/.test(searchTerm('motor),status.eq.cancelado,*')), false);
  assert.equal(searchTerm('  OS 2026-10-18030 #1 '), 'OS 2026-10-18030 #1');
  assert.equal(mutationError('40001').code, '40001');
  assert.equal(mutationError('PT409').code, 'PT409');
  assert.equal(mutationError('PT409').error, mutationError('40001').error);
  assert.equal(mutationError('SENSITIVE_DATABASE_ERROR').code, 'UNAVAILABLE');
});
