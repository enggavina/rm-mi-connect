import test from 'node:test';
import assert from 'node:assert/strict';
import { saveCatalogSchema, deleteCatalogSchema, catalogMutationError } from '../src/server/web/catalog-policy';
const id = '00000000-0000-4000-8000-000000000001';
const version = '2026-10-29T18:03:24.123456+00:00';
const base = { submissionId: id, id, kind: 'clients', expected_updated_at: null, changes: { nome: 'Cliente' } };

test('catalog validation preserves timestamp precision, trims fields and distinguishes omission from clearing', () => {
  const result = saveCatalogSchema.parse({ ...base, expected_updated_at: version, changes: { nome: '  Cliente  ', codigo: '   ', descricao: ' Texto ' } });
  assert.equal(result.expected_updated_at, version);
  assert.deepEqual(result.changes, { nome: 'Cliente', codigo: null, descricao: 'Texto' });
  assert.deepEqual(saveCatalogSchema.parse({ ...base, expected_updated_at: version, changes: { codigo: null } }).changes, { codigo: null });
  assert.deepEqual(saveCatalogSchema.parse({ ...base, kind: 'cells', changes: { nome: 'Célula', indice: null } }).changes, { nome: 'Célula', indice: null });
});
test('catalog writes reject actor injection, unknown tables, cross-kind fields and missing concurrency data', () => {
  const { expected_updated_at: _omitted, ...withoutVersion } = base;
  for (const invalid of [withoutVersion, { ...base, actor_id: id }, { ...base, kind: 'users' }, { ...base, kind: 'forms' },
    { ...base, changes: {} }, { ...base, changes: { nome: undefined } }, { ...base, changes: { nome: '   ' } },
    { ...base, changes: { descricao: 'Novo sem nome' } }, { ...base, changes: { nome: 'a'.repeat(201) } },
    { ...base, changes: { nome: 'Cliente', sigla: 'A' } }, { ...base, kind: 'types', changes: { nome: 'Motor', descricao: 'Not allowed' } },
    { ...base, expected_updated_at: '2026-10-29' }, { ...base, id: 'invalid' }]) assert.equal(saveCatalogSchema.safeParse(invalid).success, false);
  for (const number of [-1, 1.2, Infinity, NaN, 1_000_001, '1']) assert.equal(saveCatalogSchema.safeParse({ ...base, kind: 'cells', changes: { nome: 'Célula', ordem: number } }).success, false);
  assert.equal(saveCatalogSchema.safeParse({ ...base, kind: 'types', changes: { nome: 'Motor', sigla: 'x'.repeat(31) } }).success, false);
});
test('delete always requires its exact version and errors distinguish usage, duplication and uncertain delivery', () => {
  const request = { submissionId: id, id, kind: 'clients', expected_updated_at: version };
  assert.equal(deleteCatalogSchema.parse(request).expected_updated_at, version);
  for (const bad of [{ ...request, expected_updated_at: null }, { ...request, changes: {} }, { ...request, kind: 'users' }]) assert.equal(deleteCatalogSchema.safeParse(bad).success, false);
  assert.match(catalogMutationError('23503').error, /vínculos/); assert.match(catalogMutationError('23505').error, /nome/);
  assert.equal(catalogMutationError('PT409').code, 'PT409'); assert.equal(catalogMutationError().code, 'UNAVAILABLE');
});
