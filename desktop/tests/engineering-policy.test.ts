import test from 'node:test';
import assert from 'node:assert/strict';
import { deletePhotoTitleSchema, saveEngineeringSchema, savePhotoTitleSchema } from '../src/server/web/engineering-policy';
const id = '00000000-0000-4000-8000-000000000001';
const version = '2026-10-29T18:03:24.123456+00:00';
const base = { submissionId: id, id, celula_id: id, tipo_equipamento_id: id, expected_updated_at: version };
const photo = { id, cadastro_foto_id: null, numero: -1, descricao: '  Legacy unchanged  ' };
const stage = { id, celula_destino_id: null, status_cel_proj: null, bloquear_avanco_sem_aprov: false, aprovadores_ids: [], aprovadores_retorno_ids: [] };

test('engineering preserves exact versions and legacy rows for SQL grandfather checks', () => {
  const input = { ...base, changes: { photos: [photo], stages: [stage], form_ids: [], ativo: false } };
  assert.deepEqual(saveEngineeringSchema.parse(input), input);
  assert.equal(saveEngineeringSchema.parse({ ...base, changes: { ativo: true } }).expected_updated_at, version);
  assert.equal(saveEngineeringSchema.safeParse({ ...base, changes: { photos: [{ ...photo, numero: null }] } }).success, true);
  assert.equal(saveEngineeringSchema.parse({ ...base, changes: { photos: [{ ...photo, descricao: 'x'.repeat(5000) }] } }).changes.photos?.[0].descricao?.length, 5000);
  assert.deepEqual(saveEngineeringSchema.parse({ ...base, changes: { stages: [{ ...stage, aprovadores_ids: [id, id] }] } }).changes.stages?.[0].aprovadores_ids, [id, id]);
});

test('the retired planned photo count is rejected rather than silently accepted or normalized', () => {
  for (const numero_fotos of [0, 37, 1000, null]) {
    assert.equal(saveEngineeringSchema.safeParse({ ...base, changes: { ativo: false, numero_fotos } }).success, false);
  }
});
test('engineering rejects actor/project/media injection, duplicate IDs and invalid payload bounds', () => {
  for (const changes of [{}, { ativo: undefined }, { numero_fotos: -1 }, { numero_fotos: 1001 }, { numero_fotos: 1.5 },
    { form_ids: [id, id] }, { photos: [photo, photo] }, { stages: [stage, stage] },
    { photos: [{ ...photo, foto_url: 'https://example.invalid/private' }] },
    { stages: [{ ...stage, aprovado_por_id: id }] }, { stages: [{ ...stage, projeto_id: id }] }]) {
    assert.equal(saveEngineeringSchema.safeParse({ ...base, changes }).success, false);
  }
  for (const input of [{ ...base, actor_id: id, changes: { ativo: true } }, { ...base, expected_updated_at: 'today', changes: { ativo: true } }]) {
    assert.equal(saveEngineeringSchema.safeParse(input).success, false);
  }
});
test('photo-title creation requires explicit scope while existing unknown scope can be omitted', () => {
  const input = { submissionId: id, id, expected_updated_at: null, changes: { titulo: '  Vista frontal  ', celula_id: null, numero: 0 } };
  assert.deepEqual(savePhotoTitleSchema.parse(input).changes, { titulo: 'Vista frontal', celula_id: null, numero: 0 });
  assert.equal(savePhotoTitleSchema.safeParse({ ...input, changes: { titulo: 'Titulo' } }).success, false);
  assert.equal(savePhotoTitleSchema.safeParse({ ...input, changes: { titulo: 'Titulo', celula_id: undefined } }).success, false);
  assert.deepEqual(savePhotoTitleSchema.parse({ ...input, expected_updated_at: version, changes: { titulo: 'Editado' } }).changes, { titulo: 'Editado' });
  for (const numero of [-1, 1001, 1.5]) assert.equal(savePhotoTitleSchema.safeParse({ ...input, changes: { ...input.changes, numero } }).success, false);
  assert.equal(savePhotoTitleSchema.safeParse({ ...input, changes: { ...input.changes, celula_nome: 'Untrusted' } }).success, false);
});

test('title deletion requires the exact revision and excludes scope, actor and change injection', () => {
  const value = { submissionId: id, id, expected_updated_at: version };
  assert.deepEqual(deletePhotoTitleSchema.parse(value), value);
  for (const input of [{ ...value, expected_updated_at: null }, { ...value, expected_updated_at: 'today' },
    { ...value, changes: {} }, { ...value, actor_id: id }, { ...value, celula_id: id }, { ...value, id: '../id' }]) {
    assert.equal(deletePhotoTitleSchema.safeParse(input).success, false);
  }
});
