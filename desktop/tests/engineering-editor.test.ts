import test from 'node:test';
import assert from 'node:assert/strict';
import { approversForCell, canManageEngineering, engineeringChanges, engineeringRouteRows, freezeEngineeringRequest, legacyPhoto, legacyStage, nextPhotoNumber, photoDraft, stageDraft, titlesForCell, validateEngineering, type EngineeringChoices, type EngineeringPayload, type EngineeringSnapshot } from '../src/components/web/engineering-model';

const choices: EngineeringChoices = {
  types: [{ id: 'type', nome: 'Motor' }], cells: [{ id: 'origin', nome: '  Montagem  ' }, { id: 'dest', nome: 'Ensaios' }],
  forms: [{ id: 'active-form', titulo: 'Inspeção', ativo: true }, { id: 'old-form', titulo: 'Inspeção antiga', ativo: false }],
  users: [{ id: 'origin-user', nome: 'Operador origem', status: 'ativo' }, { id: 'dest-user', nome: 'Operador destino', status: 'ativo' }, { id: 'tablet-user', nome: 'Conta tablet', status: 'ativo' }, { id: 'inactive-user', nome: 'Inativo', status: 'inativo' }],
  cellUserLinks: [{ id: 'link', celula_id: 'origin', identidade_id: 'origin-user', user_id: 'tablet-user' }, { id: 'link2', celula_id: 'dest', identidade_id: 'dest-user' }, { id: 'link3', celula_id: 'origin', identidade_id: 'inactive-user' }],
  photoTitles: [{ id: 'global-title', titulo: 'Global', celula_nome: null }, { id: 'origin-title', titulo: 'Frente', celula_nome: 'montagem' }, { id: 'dest-title', titulo: 'Ensaio', celula_nome: 'Ensaios' }, { id: 'different-title', titulo: 'Outra', celula_nome: 'Môntagem' }],
  statuses: [{ id: 'finalizado', option_key: 'finalizado', bubble_display: 'Finalizado' }, { id: 'retornado', option_key: 'retornado', bubble_display: 'Retornado' }],
};
const snapshot: EngineeringSnapshot = {
  matrix: { id: 'matrix', celula_id: 'origin', tipo_equipamento_id: 'type', ativo: true, visibilidade: false, numero_fotos: 37, updated_at: '2026-10-29T12:00:00.123456+00:00' },
  form_ids: ['old-form', 'active-form'],
  photos: [{ id: 'legacy-photo', cadastro_foto_id: null, numero: null, descricao: '  Preserve espaços  ', titulo: 'Título antigo', identificador_foto_key: 'legacy-code' }],
  stages: [{ id: 'legacy-stage', celula_destino_id: null, status_cel_proj: 'retornado', bloquear_avanco_sem_aprov: true, aprovador_id: 'old-singular', aprovadores_ids: ['inactive-user'], aprovadores_retorno_ids: [] }],
};
const values = () => ({ ativo: true, visibilidade: false, numero_fotos: '37', form_ids: [...snapshot.form_ids], photos: snapshot.photos.map(photoDraft), stages: snapshot.stages.map(stageDraft) });

test('engineering edit needs administrator and its own capability, never the catalog grant alone', () => {
  assert.equal(canManageEngineering({ profile: { perfil: 'administrador' }, sso: { capabilities: ['em.catalogs.manage', 'em.engineering.read'] } }), false);
  for (const perfil of ['padr_o', 'auditor', 'mobile']) assert.equal(canManageEngineering({ profile: { perfil }, sso: { capabilities: ['em.engineering.manage'] } }), false);
  assert.equal(canManageEngineering({ profile: { perfil: 'administrador' }, sso: { capabilities: ['em.engineering.manage'] } }), true);
});

test('changing a matrix flag does not rewrite legacy children, counts, identifiers or exact versions', () => {
  const current = values(); current.ativo = false;
  assert.deepEqual(engineeringChanges(snapshot, current), { ativo: false });
  assert.deepEqual(engineeringChanges(snapshot, values()), {});
  const nullable = { ...snapshot, matrix: { ...snapshot.matrix, visibilidade: null } };
  assert.deepEqual(engineeringChanges(nullable, values()), {}, 'An unchanged legacy null flag is not silently normalized.');
  assert.equal(validateEngineering({ ativo: false }, choices, 'origin', snapshot), null);
});

test('an edited child array preserves unedited historical rows exactly and retires only deliberate removals', () => {
  const current = values(); current.photos.push({ id: 'new-photo', cadastro_foto_id: 'origin-title', numero: 1, descricao: null });
  const changes = engineeringChanges(snapshot, current);
  assert.deepEqual(changes.photos?.[0], { id: 'legacy-photo', cadastro_foto_id: null, numero: null, descricao: '  Preserve espaços  ' });
  assert.equal('stages' in changes, false); assert.equal('form_ids' in changes, false);
  assert.equal(validateEngineering(changes, choices, 'origin', snapshot), null);
  current.photos = []; assert.deepEqual(engineeringChanges(snapshot, current).photos, []);
  current.stages = []; assert.deepEqual(engineeringChanges(snapshot, current).stages, []);
  const changedLegacy = photoDraft(snapshot.photos[0]); changedLegacy.descricao = 'Nova orientação';
  assert.match(validateEngineering({ photos: [changedLegacy] }, choices, 'origin', snapshot)!, /título.*número/);
});

test('photo titles match global or lower-trim cell names; numbering is independent of reference count', () => {
  assert.deepEqual(titlesForCell(choices, 'origin').map(row => row.id), ['global-title', 'origin-title']);
  assert.deepEqual(titlesForCell(choices, ''), []);
  assert.equal(nextPhotoNumber(snapshot.photos.map(photoDraft)), 1);
  assert.equal(nextPhotoNumber([{ id: 'p', cadastro_foto_id: null, numero: 24, descricao: null }]), 25);
  assert.equal(nextPhotoNumber([{ id: 'p', cadastro_foto_id: null, numero: 1000, descricao: null }]), null);
  for (const numero of [null, 0, -1, 1001, 1.2]) assert.equal(legacyPhoto({ id: 'p', cadastro_foto_id: 'origin-title', numero, descricao: null }, choices, 'origin'), true);
  assert.equal(legacyPhoto({ id: 'p', cadastro_foto_id: 'dest-title', numero: 1, descricao: null }, choices, 'origin'), true);
  const spaces = { ...choices, cells: [{ id: 'cell', nome: ' Testes  finais ' }], photoTitles: [{ id: 'title', celula_nome: 'testes finais' }] };
  assert.deepEqual(titlesForCell(spaces, 'cell').map(row => row.id), ['title']);
});

test('route order follows the global cell order without mutating source rows', () => {
  const cells = [{ id: 'c1', ordem: 2, indice: 1 }, { id: 'c2', ordem: 1, indice: 9 }, { id: 'c3', ordem: null, indice: 1 }];
  const rows = [{ id: 'm1', celula_id: 'c1' }, { id: 'm3', celula_id: 'c3' }, { id: 'm2', celula_id: 'c2' }];
  assert.deepEqual(engineeringRouteRows(rows, cells).map(row => row.id), ['m2', 'm1', 'm3']);
  assert.deepEqual(rows.map(row => row.id), ['m1', 'm3', 'm2']);
});

test('approvers are active identities of the specific cell; tablet accounts and other-cell users are excluded', () => {
  assert.deepEqual(approversForCell(choices, 'origin').map(row => row.id), ['origin-user']);
  assert.deepEqual(approversForCell(choices, 'dest').map(row => row.id), ['dest-user']);
  const stage = { id: 'new', celula_destino_id: 'dest', status_cel_proj: 'finalizado', bloquear_avanco_sem_aprov: true, aprovadores_ids: ['origin-user'], aprovadores_retorno_ids: ['dest-user'] };
  assert.equal(legacyStage(stage, choices, 'origin'), false);
  assert.equal(validateEngineering({ stages: [stage] }, choices, 'origin', snapshot), null);
  for (const patch of [{ celula_destino_id: 'origin' }, { status_cel_proj: 'retornado' }, { aprovadores_ids: [] }, { aprovadores_ids: ['tablet-user'] }, { aprovadores_retorno_ids: ['origin-user'] }]) assert.equal(legacyStage({ ...stage, ...patch }, choices, 'origin'), true);
  assert.equal(validateEngineering({ stages: snapshot.stages.map(stageDraft) }, choices, 'origin', snapshot), null, 'Untouched legacy stage may be preserved when another stage changes.');
});

test('inactive forms remain when selected historically but cannot be newly assigned', () => {
  assert.equal(validateEngineering({ form_ids: ['old-form'] }, choices, 'origin', snapshot), null);
  assert.match(validateEngineering({ form_ids: ['old-form'] }, choices, 'origin')!, /ativos/);
  assert.equal(validateEngineering({ form_ids: ['active-form'] }, choices, 'origin'), null);
});

test('retry deeply freezes child arrays and preserves the exact aggregate revision', () => {
  const payload: EngineeringPayload = { submissionId: 'submission', id: 'matrix', celula_id: 'origin', tipo_equipamento_id: 'type', expected_updated_at: snapshot.matrix.updated_at,
    changes: { photos: snapshot.photos.map(photoDraft), stages: snapshot.stages.map(stageDraft), form_ids: [...snapshot.form_ids] } };
  const first = freezeEngineeringRequest(payload);
  payload.changes.photos![0].descricao = 'New text'; payload.changes.stages![0].aprovadores_ids.push('another'); payload.changes.form_ids!.reverse(); payload.expected_updated_at = 'later';
  assert.equal(first.expected_updated_at, '2026-10-29T12:00:00.123456+00:00');
  assert.deepEqual(first.changes.stages![0].aprovadores_ids, ['inactive-user']);
  assert.deepEqual(first.changes.form_ids, ['old-form', 'active-form']);
  assert.equal(first.changes.photos![0].descricao, '  Preserve espaços  ');
  assert.equal(Object.isFrozen(first.changes.stages![0].aprovadores_ids), true);
});
