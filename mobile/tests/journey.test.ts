import test from 'node:test';
import assert from 'node:assert/strict';
import type { Operator, OutboxRow, Row } from '../src/core/types';
import { allowedCells, assignedForms, canAccessCell, canEditPhoto, canOpenForm, canReviseRecord, cellAllocations, pendingProjectPhotos, projectPhotos, requiredPhotoProgress, resolveJourneyContext } from '../src/domain/journey';

const operator: Operator = { operador_id: 'person', matricula: '42', nome: 'Operador', perfil: 'mobile', perfil_assinante: [], celulas_vinculadas: [{ celula_id: 'c1', nome: 'Mecânica' }], authenticated_at: '2026-10-27T12:00:00Z' };
const cells: Row[] = [{ id: 'c2', nome: 'Elétrica', indice: 2 }, { id: 'c1', nome: 'Mecânica', indice: 1 }];
const projects: Row[] = [{ id: 'p1', numero: '1200', status_pcp: null }, { id: 'p2', numero: '1300' }];
const allocation: Row = { id: 'a1', projeto_id: 'p1', celula_id: 'c1', visibilidade: true, bloqueada: 'n_o', forms_ids: ['f2', 'f1', 'f2'] };
const context = () => resolveJourneyContext(operator, 'c1', 'p1', cells, projects, [allocation]);

test('cell selection uses operator identity links and preserves explicit administrator access', () => {
  assert.deepEqual(allowedCells(operator, cells).map(c => c.id), ['c1']);
  assert.equal(canAccessCell(operator, 'c2'), false);
  assert.deepEqual(allowedCells({ ...operator, perfil: 'administrador', celulas_vinculadas: [] }, cells).map(c => c.id), ['c1', 'c2']);
  assert.deepEqual(allowedCells({ ...operator, celulas_vinculadas: [] }, cells), []);
  assert.deepEqual(allowedCells(null, cells), []);
  assert.equal(canAccessCell({ ...operator, perfil: 'administrador' }, undefined), false);
});

test('cell project list excludes invisible, delivered, cancelled and billing-ready projects', () => {
  const catalog: Row[] = [...projects, { id: 'cancelled', status_pcp: 'cancelado' }, { id: 'billing', status_pcp: 'finalizando_para_faturar' }, { id: 'delivered', data_real_de_entrega: '2026-10-20' }];
  const rows = catalog.map(p => ({ ...allocation, id: `a-${p.id}`, projeto_id: p.id, visibilidade: p.id !== 'p2' }));
  assert.deepEqual(cellAllocations(operator, 'c1', catalog, rows).map(a => a.projeto_id), ['p1']);
  assert.deepEqual(cellAllocations(operator, 'c2', catalog, rows), []);
});

test('deep links require a permitted cell and a visible allocation of the selected active project', () => {
  assert.equal(context().ok, true);
  assert.equal(resolveJourneyContext(operator, undefined, 'p1', cells, projects, [allocation]).ok, false);
  assert.equal(resolveJourneyContext(operator, 'c2', 'p1', cells, projects, [{ ...allocation, celula_id: 'c2' }]).ok, false);
  assert.equal(resolveJourneyContext(operator, 'c1', 'p2', cells, projects, [allocation]).ok, false);
  assert.equal(resolveJourneyContext(operator, 'c1', 'p1', cells, projects, [{ ...allocation, visibilidade: false }]).ok, false);
});

test('forms come only from the project-cell forms_ids with stable order and no model fallback', () => {
  const models: Row[] = [{ id: 'global', ativo: true }, { id: 'f1', ativo: true }, { id: 'f2', ativo: false }, { id: 'other-cell', ativo: true }];
  assert.deepEqual(assignedForms(allocation, models).map(f => f.id), ['f2', 'f1']);
  assert.deepEqual(assignedForms({ ...allocation, forms_ids: [] }, models), []);
  assert.deepEqual(assignedForms({ ...allocation, forms_ids: null }, models), []);
  assert.deepEqual(assignedForms({ ...allocation, forms_ids: ['missing'] }, models), []);
  assert.equal(canOpenForm(context(), 'global'), false);
  assert.equal(canOpenForm(context(), 'f1'), true);
});

test('a revision link cannot move a record between projects, cells or unassigned forms', () => {
  const record: Row = { id: 'r1', projeto_id: 'p1', celula_id: 'c1', form_id: 'f1', status: 'direcionado' };
  assert.equal(canReviseRecord(context(), record), true);
  for (const patch of [{ projeto_id: 'p2' }, { celula_id: 'c2' }, { form_id: 'global' }, { status: 'aprovado' }]) assert.equal(canReviseRecord(context(), { ...record, ...patch }), false);
  assert.equal(canReviseRecord(context(), undefined), false);
});

test('gallery separates current-cell mandatory and complementary photos from read-only project photos', () => {
  const own: Row = { id: 'required', projeto_id: 'p1', celula_id: 'c1', celula_projeto_id: 'a1', categoria_foto: 'obrigat_ria' };
  const complementary = { ...own, id: 'complementary', categoria_foto: 'complementar' };
  const otherCell = { ...own, id: 'other', celula_id: 'c2' };
  const wrongAllocation = { ...own, id: 'other-allocation', celula_projeto_id: 'a2' };
  const gallery = projectPhotos(context(), [own, complementary, otherCell, wrongAllocation, { ...own, id: 'deleted', lixeira: true }, { ...own, id: 'another-project', projeto_id: 'p2' }]);
  assert.deepEqual(gallery.required.map(p => p.id), ['required']);
  assert.deepEqual(gallery.complementary.map(p => p.id), ['complementary']);
  assert.deepEqual(gallery.others.map(p => p.id), ['other', 'other-allocation']);
  assert.equal(canEditPhoto(context(), own), true);
  assert.equal(canEditPhoto(context(), complementary), true);
  assert.equal(canEditPhoto(context(), otherCell), false);
  assert.equal(canEditPhoto(context(), wrongAllocation), false);
});

test('blocked allocations retain project and photo consultation without permitting edits', () => {
  const blocked = resolveJourneyContext(operator, 'c1', 'p1', cells, projects, [{ ...allocation, bloqueada: 'sim' }]);
  assert.equal(blocked.ok, true);
  if (!blocked.ok) throw new Error('Expected readable context');
  assert.equal(blocked.canEdit, false);
  assert.equal(canOpenForm(blocked, 'f1'), true);
  assert.equal(canEditPhoto(blocked, { id: 'photo', projeto_id: 'p1', celula_id: 'c1' }), false);
});

const requiredPhoto: Row = { id: 'required', projeto_id: 'p1', celula_id: 'c1', celula_projeto_id: 'a1', categoria_foto: 'obrigat_ria', foto_url: null };
function photoOperation(params: Record<string, unknown> = {}, patch: Partial<OutboxRow> = {}): OutboxRow {
  return { id: 'submission', rpc_name: 'rm_record_cell_photo_v1', actor_id: 'original-author', token_key: 'private-original-token', draft_id: null, status: 'pending', attempts: 0, next_retry_at: 0, created_at: '2026-10-27T12:00:00Z',
    params_json: JSON.stringify({ p_foto_id: 'required', p_projeto_id: 'p1', p_celula_id: 'c1', p_celula_projeto_id: 'a1', p_foto_url: 'file:///persisted.jpg', p_categoria_foto: 'obrigat_ria', p_operador_id: 'original-author', ...params }), ...patch };
}

test('queued required photo remains visible after switching operators without copying authorship or mutating work', () => {
  const photo = Object.freeze({ ...requiredPhoto }); const operation = Object.freeze(photoOperation());
  const queue = Object.freeze([operation]); const before = JSON.stringify({ photo, queue });
  const another = resolveJourneyContext({ ...operator, operador_id: 'next-person' }, 'c1', 'p1', cells, projects, [allocation]);
  const overlay = pendingProjectPhotos(another, [photo], queue);
  assert.equal(overlay.slots.required.uri, 'file:///persisted.jpg');
  assert.equal(overlay.slots.required.operatorId, 'original-author');
  assert.equal(overlay.slots.required.operationId, 'submission');
  assert.equal('token_key' in overlay.slots.required, false);
  assert.equal('draft_id' in overlay.slots.required, false);
  assert.deepEqual(requiredPhotoProgress([photo], overlay.slots), { registered: 1, confirmed: 0, pending: 1, attention: 0 });
  assert.equal(JSON.stringify({ photo, queue }), before);
});

test('photo overlay ignores other project/cell/allocation, missing slots, completed and malformed operations', () => {
  const queue = [photoOperation({ p_projeto_id: 'p2' }), photoOperation({ p_celula_id: 'c2' }), photoOperation({ p_celula_projeto_id: 'a2' }),
    photoOperation({ p_foto_id: 'unknown' }), photoOperation({}, { status: 'completed' }), photoOperation({}, { params_json: '{broken' }),
    photoOperation({}, { rpc_name: 'rm_submit_form_inspection_v1' }), photoOperation({ p_foto_url: '' })];
  assert.deepEqual(pendingProjectPhotos(context(), [requiredPhoto], queue), { slots: {}, complementary: [] });
});

test('latest queued replacement stays pending, failures require attention, and confirmation removes the overlay', () => {
  const confirmed = { ...requiredPhoto, foto_url: 'https://photos/previous.jpg' };
  const earlier = photoOperation({ p_foto_url: 'file:///first.jpg' });
  const later = photoOperation({ p_foto_url: 'file:///latest.jpg' }, { id: 'later', status: 'failed', last_error: 'Reidentifique o autor.', created_at: '2026-10-27T13:00:00Z' });
  const pending = pendingProjectPhotos(context(), [confirmed], [later, earlier]);
  assert.equal(pending.slots.required.operationId, 'later');
  assert.equal(pending.slots.required.uri, 'file:///latest.jpg');
  assert.equal(pending.slots.required.error, 'Reidentifique o autor.');
  assert.deepEqual(requiredPhotoProgress([confirmed], pending.slots), { registered: 1, confirmed: 0, pending: 1, attention: 1 });
  const synced = pendingProjectPhotos(context(), [confirmed], [{ ...earlier, status: 'completed' }, { ...later, status: 'completed' }]);
  assert.deepEqual(requiredPhotoProgress([confirmed], synced.slots), { registered: 1, confirmed: 1, pending: 0, attention: 0 });
});

test('new complementary uploads are separate records and do not occupy or inflate required slots', () => {
  const queue = [photoOperation({ p_foto_id: null, p_categoria_foto: 'complementar' }), photoOperation({ p_foto_id: null, p_categoria_foto: 'complementar' }, { id: 'another-complementary' })];
  const overlay = pendingProjectPhotos(context(), [requiredPhoto], queue);
  assert.deepEqual(overlay.slots, {});
  assert.deepEqual(overlay.complementary.map(photo => photo.operationId), ['submission', 'another-complementary']);
  assert.deepEqual(requiredPhotoProgress([requiredPhoto], overlay.slots), { registered: 0, confirmed: 0, pending: 0, attention: 0 });
});
