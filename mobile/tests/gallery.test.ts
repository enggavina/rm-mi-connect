import test from 'node:test';
import assert from 'node:assert/strict';
import { cellPhotoTitles, galleryPhotos, photoTitle } from '../src/domain/gallery';
import type { JourneyContext } from '../src/domain/journey';
import type { OutboxRow } from '../src/core/types';
const context: JourneyContext = { ok: true, cell: { id: 'cell', nome: 'Peritagem Mecânica', codigo: 'PER' }, project: { id: 'project' }, allocation: { id: 'allocation' }, canEdit: true };
test('gallery shows captured photos only, preserving local pending evidence and original actor', () => {
  const photos = [{ id: 'empty', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'obrigat_ria' }, { id: 'pending', projeto_id: 'project', celula_id: 'cell', categoria_foto: 'obrigat_ria' }, { id: 'registered', projeto_id: 'project', celula_id: 'other-cell', foto_url: 'https://photos.example/real.jpg' }, { id: 'trashed', projeto_id: 'project', foto_url: 'https://photos.example/deleted.jpg', lixeira: true }, { id: 'foreign', projeto_id: 'another-project', foto_url: 'https://photos.example/other.jpg' }];
  const queue = [{ id: 'protocol', rpc_name: 'rm_record_cell_photo_v1', status: 'pending', actor_id: 'original-operator', created_at: '2026-10-28', params_json: JSON.stringify({ p_projeto_id: 'project', p_celula_id: 'cell', p_foto_id: 'pending', p_foto_url: 'file:///saved.jpg', p_legenda: 'Preservada' }) }] as OutboxRow[];
  const gallery = galleryPhotos(context, photos, queue);
  assert.deepEqual(gallery.map(photo => photo.id).sort(), ['pending', 'registered']);
  const pending = gallery.find(photo => photo.id === 'pending')!;
  assert.equal(pending.registered_by, 'original-operator'); assert.equal(pending.operation_id, 'protocol');
  assert.equal(pending.foto_url, 'file:///saved.jpg'); assert.equal(photos[1].foto_url, undefined);
});
test('photo title catalogs respect the current cell and real receiving captions', () => {
  assert.deepEqual(cellPhotoTitles({ id: 'cell', nome: 'Peritagem Mecânica', codigo: 'PER' }, [{ id: 'one', titulo: 'Frente', celula_nome: 'peritagem mecânica' }, { id: 'two', titulo: 'Outra', celula_nome: 'Montagem' }]).map(row => row.id), ['one']);
  assert.equal(photoTitle({ id: 'front', tipo_recebimento: 'frente' }), 'Vista frontal');
  assert.equal(photoTitle({ id: 'back', tipo_recebimento: 'vista_superior' }), 'Vista Traseira');
});
test('project gallery includes pending captures from another cell without changing their scope or author', () => {
  const queue = [{ id: 'other-cell-protocol', rpc_name: 'rm_record_cell_photo_v1', status: 'pending', actor_id: 'operator-A', created_at: '2026-10-28', params_json: JSON.stringify({ p_projeto_id: 'project', p_celula_id: 'another-cell', p_foto_url: 'file:///other-cell.jpg', p_categoria_foto: 'complementar', p_titulo: 'Detalhe' }) }] as OutboxRow[];
  const photos = galleryPhotos(context, [], queue);
  assert.equal(photos.length, 1); assert.equal(photos[0].celula_id, 'another-cell'); assert.equal(photos[0].registered_by, 'operator-A');
  assert.equal(photos[0].operation_id, 'other-cell-protocol');
});
