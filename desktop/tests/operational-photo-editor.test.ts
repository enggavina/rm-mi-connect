import test from 'node:test';
import assert from 'node:assert/strict';
import type { OperationalPhotoSnapshot } from '../src/server/web/operational-photo-data';
import { canManageOperationalPhotos, operationalPhotoPage, operationalPhotoRequest, operationalTitleBlockReason, operationalReplacementTitleBlockReason } from '../src/components/web/operational-photo-model';

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

test('unused photo replacement freezes a new slot and never accepts a captured or unavailable source',()=>{
  const current=snapshot();current.photos[0]={...current.photos[0],can_replace:true,numero:1,descricao:'Anterior'};
  const draft={action:'replace' as const,photoId:id(3),titleId:id(10),numero:'2',descricao:'Nova configuração',tag:'TAG',confirmed:true};
  const request=operationalPhotoRequest(current,draft,id(20),()=>id(30));assert.equal(request.action,'replace');if(request.action!=='replace')return;
  assert.equal(request.foto_id,id(3));assert.equal(request.new_id,id(30));assert.equal(request.cadastro_foto_id,id(10));assert.equal(request.numero,2);
  assert.equal(request.descricao,'Nova configuração');assert.equal(request.expected_foto_updated_at,version);assert.equal(Object.isFrozen(request),true);
  assert.throws(()=>operationalPhotoRequest(current,{...draft,confirmed:false},id(20),()=>id(30)),/confirme/);
  assert.throws(()=>operationalPhotoRequest(current,{...draft,titleId:id(12)},id(20),()=>id(30)),/disponível/);
  assert.throws(()=>operationalPhotoRequest(current,{...draft,photoId:id(5)},id(20),()=>id(30)),/não permite/);
});

test('metadata replacements can keep their title through multiple retired predecessors',()=>{
  const value=snapshot();value.photos=[{...value.photos[0],can_replace:true,numero:1,descricao:'Inicial'}];value.total=1;
  const title=value.titles.find(title=>title.id===id(11))!;
  const first=operationalPhotoRequest(value,{action:'replace',photoId:id(3),titleId:title.id,numero:'2',descricao:'Primeira revisão',tag:'',confirmed:true},id(20),()=>id(30));
  assert.equal(first.action,'replace');
  const predecessor={...value.photos[0],retired:true,can_replace:false,can_retire:false,can_edit_tag:false,can_restore:true};
  const active={...value.photos[0],id:id(30),numero:2,descricao:'Primeira revisão'};
  value.photos=[predecessor,active];value.total=2;title.retired_photo_id=predecessor.id;
  assert.equal(operationalReplacementTitleBlockReason(title,active,value.photos),null);
  const second=operationalPhotoRequest(value,{action:'replace',photoId:active.id,titleId:title.id,numero:'3',descricao:'Segunda revisão',tag:'',confirmed:true},id(21),()=>id(31));
  assert.equal(second.action,'replace');if(second.action!=='replace')return;
  assert.equal(second.foto_id,active.id);assert.equal(second.new_id,id(31));assert.equal(second.cadastro_foto_id,title.id);
  assert.equal(second.numero,3);assert.equal(second.descricao,'Segunda revisão');
  value.photos.push({...active,id:id(32)});
  assert.match(operationalReplacementTitleBlockReason(title,active,value.photos)!,/Outro item ativo/);
  assert.throws(()=>operationalPhotoRequest(value,{action:'replace',photoId:active.id,titleId:title.id,numero:'4',descricao:'Recusada',tag:'',confirmed:true},id(22),()=>id(33)),/disponível/);
});

test('legacy name-only title links allow correction but preserve foreign active and retired slots',()=>{
  const value=snapshot(),legacy={...value.photos[0],cadastro_foto_id:null,titulo:'  FRENTE  ',can_replace:true,numero:1};
  value.photos=[legacy];value.total=1;const title=value.titles.find(title=>title.id===id(11))!;
  assert.equal(title.assigned,true);assert.equal(operationalReplacementTitleBlockReason(title,legacy,value.photos),null);
  const request=operationalPhotoRequest(value,{action:'replace',photoId:legacy.id,titleId:title.id,numero:'1',descricao:'Instrução corrigida',tag:'',confirmed:true},id(20),()=>id(30));
  assert.equal(request.action,'replace');if(request.action!=='replace')return;
  assert.equal(request.cadastro_foto_id,title.id);assert.equal(request.descricao,'Instrução corrigida');
  const other={...legacy,id:id(40),titulo:'frente',cadastro_foto_id:id(99)};
  assert.match(operationalReplacementTitleBlockReason(title,legacy,[legacy,other])!,/Outro item ativo/);
  assert.match(operationalReplacementTitleBlockReason(value.titles[2],legacy,value.photos)!,/restaurá/);
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
