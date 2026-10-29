import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createOperationalPhotoData } from '../src/server/web/operational-photo-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.photos.read', 'em.planning.manage'];
function snapshot() {
  const photo = { id: id(3), projeto_id: id(1), celula_id: id(4), celula_projeto_id: id(2), cadastro_foto_id: id(11), titulo: 'Frente',
    categoria_foto: 'obrigat_ria', tag: '  legado  ', numero: 1.25, updated_at: version, captured: false, selected_for_report: false,
    retired: false, can_edit_tag: true, can_retire: true, can_restore: false, action_reason: null, foto_url: 'private-file', private_data: 'private' };
  return {
    project: { id: id(1), numero: 'OS1', status_pcp: null, data_real_de_entrega: null, updated_at: version, closed: false, arquivo_url: 'private' },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(4), celula_nome: 'Peritagem', status: null, updated_at: version, private_data: 'private' },
    photos: [photo, { ...photo, id: id(5), cadastro_foto_id: null, celula_projeto_id: null, captured: true, selected_for_report: true, can_retire: false },
      { ...photo, id: id(6), cadastro_foto_id: id(12), retired: true, can_edit_tag: false, can_retire: false, can_restore: true },
      { ...photo, id: id(7), categoria_foto: 'complementar', captured: true, can_edit_tag: false, can_retire: false }],
    titles: [{ id: id(10), titulo: 'Novo título', numero: 5, updated_at: version, assigned: false, retired_photo_id: null, private_data: 'private' },
      { id: id(11), titulo: 'Frente', numero: 1, updated_at: version, assigned: true, retired_photo_id: null },
      { id: id(12), titulo: 'Retirada', numero: null, updated_at: version, assigned: true, retired_photo_id: id(6) }],
    photos_version: 'a'.repeat(64), total: 4, complete: true, titles_total: 3, titles_complete: true, private_snapshot: 'private',
  };
}
function fixture(caps: readonly CorporateCapability[] = capabilities) {
  let current: unknown = snapshot(), error: unknown = null; const calls: { name: string; args: unknown }[] = [];
  const client = { async rpc(name: string, args: unknown) { calls.push({ name, args }); return { data: current, error }; } } as unknown as SupabaseClient;
  return { reader: createOperationalPhotoData(client, caps), calls, set(value: unknown) { current = value; }, fail(value: unknown) { error = value; } };
}

test('operational photo reads require exact domain grants and writer capability for title choices before querying', async () => {
  for (const missing of ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.photos.read'] as CorporateCapability[]) {
    const f = fixture(capabilities.filter(cap => cap !== missing));
    await assert.rejects(f.reader.getOperationalPhotos(id(1), id(2)), /Acesso/); assert.deepEqual(f.calls, []);
  }
  const f = fixture(capabilities.filter(cap => cap !== 'em.planning.manage'));
  await assert.rejects(f.reader.getOperationalPhotos(id(1), id(2), true), /Acesso/); assert.deepEqual(f.calls, []);
  assert.equal(await f.reader.getOperationalPhotos('invalid', id(2)), null); assert.deepEqual(f.calls, []);
  assert.ok(await f.reader.getOperationalPhotos(id(1), id(2)));
});

test('atomic operational snapshot preserves exact versions, legacy links and fractional numbers while redacting media and private fields', async () => {
  const f = fixture(), result = await f.reader.getOperationalPhotos(id(1), id(2), true); assert.ok(result);
  assert.equal(result.project.updated_at, version); assert.equal(result.allocation.updated_at, version); assert.equal(result.photos[0].updated_at, version);
  assert.equal(result.photos[0].numero, 1.25); assert.equal(result.photos[0].tag, '  legado  ');
  assert.equal(result.photos[1].celula_projeto_id, null); assert.equal(result.photos[1].can_edit_tag, true);
  assert.equal(result.photos[2].retired, true); assert.equal(result.photos[2].can_restore, true);
  assert.equal(result.titles[2].retired_photo_id, id(6)); assert.ok(!JSON.stringify(result).includes('private'));
  assert.deepEqual(f.calls, [{ name: 'rm_web_operational_photos_snapshot_v1', args: { p_project_id: id(1), p_allocation_id: id(2), p_include_titles: true } }]);
  const readonly = await f.reader.getOperationalPhotos(id(1), id(2));
  assert.deepEqual(readonly?.titles, []); assert.equal(readonly?.titles_total, 3);
});

test('crossed scope, corrupt flags, duplicate records and partial collections fail closed', async () => {
  const f = fixture();
  const cases: unknown[] = [
    { ...snapshot(), project: { ...snapshot().project, id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, projeto_id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, id: id(99) } },
    { ...snapshot(), total: 5 }, { ...snapshot(), photos_version: 'not-a-hash' },
    { ...snapshot(), complete: false }, { ...snapshot(), titles_complete: false },
    { ...snapshot(), titles_total: 4 },
    { ...snapshot(), photos: [...snapshot().photos, snapshot().photos[0]], total: 5 },
    { ...snapshot(), titles: [...snapshot().titles, snapshot().titles[0]], titles_total: 4 },
    { ...snapshot(), project: { ...snapshot().project, closed: true } },
    { ...snapshot(), allocation: { ...snapshot().allocation, status: 'finalizado' } },
  ];
  for (const patch of [{ projeto_id: id(99) }, { celula_id: id(99) }, { celula_projeto_id: id(99) },
    { retired: true }, { captured: true }, { selected_for_report: true }, { can_restore: true }, { categoria_foto: null }, { updated_at: 'invalid' }]) {
    const value = snapshot(); value.photos[0] = { ...value.photos[0], ...patch } as typeof value.photos[number]; cases.push(value);
  }
  for (const value of cases) { f.set(value); await assert.rejects(f.reader.getOperationalPhotos(id(1), id(2), true), /Não foi possível/); }
  const wrongRestore = snapshot(); wrongRestore.titles[2].retired_photo_id = id(99);
  f.set(wrongRestore); await assert.rejects(f.reader.getOperationalPhotos(id(1), id(2), true), /Não foi possível/);
});

test('collection limits do not expose truncated editable sets; unavailable errors contain no upstream secrets', async () => {
  const f = fixture();
  f.set({ ...snapshot(), photos: [], total: 2001, complete: false });
  assert.equal((await f.reader.getOperationalPhotos(id(1), id(2), true))?.complete, false);
  f.set({ ...snapshot(), titles: [], titles_total: 1001, titles_complete: false });
  const manyTitles = await f.reader.getOperationalPhotos(id(1), id(2), true); assert.ok(manyTitles);
  assert.equal(manyTitles.titles_complete, false); assert.equal(manyTitles.photos[0].can_edit_tag, true);
  f.set(null); assert.equal(await f.reader.getOperationalPhotos(id(1), id(2)), null);
  f.fail({ message: 'private upstream secret' });
  await assert.rejects(f.reader.getOperationalPhotos(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
});
