import test from 'node:test';
import assert from 'node:assert/strict';
import type { OperationalPhotoSnapshot } from '../src/server/web/operational-photo-data';
import { canManageOperationalPhotos, operationalPhotoPage, operationalPhotoRequest, operationalTitleBlockReason } from '../src/components/web/operational-photo-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
function snapshot(): OperationalPhotoSnapshot {
  const photo = { id: id(3), projeto_id: id(1), celula_id: id(4), celula_projeto_id: id(2), cadastro_foto_id: id(11), titulo: 'Frente',
    categoria_foto: 'obrigat_ria', tag: null, numero: null, updated_at: version, captured: false, selected_for_report: false,
    retired: false, can_edit_tag: true, can_retire: true, can_restore: false, action_reason: null };
  return { project: { id: id(1), numero: 'OS', status_pcp: null, data_real_de_entrega: null, updated_at: version, closed: false },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(4), celula_nome: 'Peritagem', status: null, updated_at: version },
    photos: [photo, { ...photo, id: id(5), captured: true, can_retire: false },
      { ...photo, id: id(6), cadastro_foto_id: id(12), retired: true, can_edit_tag: false, can_retire: false, can_restore: true }],
    titles: [{ id: id(10), titulo: 'Novo título', numero: null, updated_at: version, assigned: false, retired_photo_id: null },
      { id: id(11), titulo: 'Frente', numero: null, updated_at: version, assigned: true, retired_photo_id: null },
      { id: id(12), titulo: 'Retirada', numero: null, updated_at: version, assigned: true, retired_photo_id: id(6) },
      { id: id(13), titulo: '  NOVO   TÍTULO ', numero: null, updated_at: version, assigned: false, retired_photo_id: null }],
    photos_version: 'a'.repeat(64), total: 3, complete: true, titles_total: 4, titles_complete: true };
}

test('operational choices prevent repeated titles and point retired slots to restoration instead of new IDs', () => {
  const current = snapshot();
  assert.equal(operationalTitleBlockReason(current.titles[0], [], current.titles), null);
  assert.match(operationalTitleBlockReason(current.titles[1], [], current.titles)!, /vinculado/);
  assert.match(operationalTitleBlockReason(current.titles[2], [], current.titles)!, /restaurá/);
  assert.match(operationalTitleBlockReason(current.titles[3], [id(10)], current.titles)!, /selecionado/);
  assert.throws(() => operationalPhotoRequest(current, { action: 'add', titleIds: [id(10), id(13)] }, id(20), () => id(30)), /cada título/);
  for (const titleIds of [[], [id(10), id(10)], [id(11)], [id(12)], [id(99)]]) {
    assert.throws(() => operationalPhotoRequest(current, { action: 'add', titleIds }, id(20), () => id(30)));
  }
});

test('add freezes generated slot IDs and exact versions with only the permitted context', () => {
  const current = snapshot(), titles = [id(10)];
  const request = operationalPhotoRequest(current, { action: 'add', titleIds: titles }, id(20), () => id(30));
  current.project.updated_at = 'later'; current.allocation.updated_at = 'later'; current.photos_version = 'b'.repeat(64); titles[0] = id(99);
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_allocation_updated_at, version);
  assert.equal(request.expected_photos_version, 'a'.repeat(64)); assert.equal(request.submissionId, id(20));
  assert.ok(request.action === 'add'); assert.deepEqual(request.items, [{ id: id(30), cadastro_foto_id: id(10) }]);
  assert.equal(Object.isFrozen(request.items[0]), true); assert.equal(Object.isFrozen(request), true);
  assert.ok(!JSON.stringify(request).includes('foto_url')); assert.ok(!('actor_id' in request));
});

test('tag preserves whitespace and can change a captured mandatory photo; retire and restore retain the original target ID', () => {
  const current = snapshot();
  const tag = operationalPhotoRequest(current, { action: 'tag', photoId: id(5), tag: '  tag legada  ' }, id(20), () => id(30));
  assert.ok(tag.action === 'tag'); assert.equal(tag.tag, '  tag legada  '); assert.equal(tag.expected_foto_updated_at, version);
  const clear = operationalPhotoRequest(current, { action: 'tag', photoId: id(3), tag: '' }, id(20), () => id(30));
  assert.ok(clear.action === 'tag'); assert.equal(clear.tag, null);
  assert.throws(() => operationalPhotoRequest(current, { action: 'tag', photoId: id(3), tag: 'x'.repeat(2001) }, id(20), () => id(30)), /2.000/);
  assert.throws(() => operationalPhotoRequest(current, { action: 'retire', photoId: id(5) }, id(20), () => id(30)), /não permite/);
  const retired = operationalPhotoRequest(current, { action: 'retire', photoId: id(3) }, id(20), () => id(30));
  const restore = operationalPhotoRequest(current, { action: 'restore', photoId: id(6) }, id(21), () => id(31));
  assert.ok(retired.action === 'retire' && restore.action === 'restore');
  assert.equal(retired.foto_id, id(3)); assert.equal(restore.foto_id, id(6));
  assert.ok(!('tag' in retired)); assert.ok(!('items' in restore));
});

test('closed contexts and photo overflow block management while title overflow blocks add alone', () => {
  const current = snapshot(); assert.equal(canManageOperationalPhotos(current, false), false);
  assert.equal(canManageOperationalPhotos(current, true), true);
  for (const status of ['finalizado', 'n_a']) assert.equal(canManageOperationalPhotos({ ...current, allocation: { ...current.allocation, status } }, true), false);
  assert.equal(canManageOperationalPhotos({ ...current, project: { ...current.project, closed: true } }, true), false);
  assert.equal(canManageOperationalPhotos({ ...current, photos: [], total: 2001, complete: false }, true), false);
  const overflow = { ...current, titles: [], titles_total: 1001, titles_complete: false };
  assert.equal(canManageOperationalPhotos(overflow, true), true);
  assert.throws(() => operationalPhotoRequest(overflow, { action: 'add', titleIds: [id(10)] }, id(20), () => id(30)), /lista completa/);
  assert.equal(operationalPhotoRequest(overflow, { action: 'tag', photoId: id(3), tag: 'Atual' }, id(20), () => id(30)).action, 'tag');
});

test('active and retired presentation has stable photo numbering and never mixes collections across pages', () => {
  const current = snapshot();
  const rows = Array.from({ length: 26 }, (_, index) => ({ ...current.photos[0], id: id(100 + index), numero: index === 25 ? null : 25 - index }));
  rows.push(current.photos[2]);
  const first = operationalPhotoPage(rows, false), last = operationalPhotoPage(rows, false, 9);
  assert.equal(first.total, 26); assert.equal(first.rows.length, 25); assert.equal(first.rows[0].numero, 1);
  assert.equal(last.page, 2); assert.equal(last.rows.length, 1); assert.equal(last.rows[0].numero, null);
  assert.deepEqual(operationalPhotoPage(rows, true).rows.map(photo => photo.id), [id(6)]);
  assert.equal(rows[0].numero, 25, 'Presentation must not mutate the server snapshot.');
});
