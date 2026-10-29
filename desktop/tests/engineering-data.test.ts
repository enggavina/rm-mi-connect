import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createEngineeringData, photoTitleScope } from '../src/server/web/engineering-data';
import type { WebRow } from '../src/server/web/data';
import type { CorporateCapability } from '../src/server/web/sso-policy';
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
class Fixture {
  tables: Record<string, WebRow[]> = {}; snapshot: any = null; rpcCalls: any[] = []; calls: any[] = [];
  from(table: string) { return new Query(this, table); }
  async rpc(name: string, args: unknown) { this.rpcCalls.push({ name, args }); return { data: this.snapshot, error: null }; }
}
class Query {
  columns = ''; filters: [string, unknown][] = []; rangeBounds?: [number, number]; counted = false; single = false;
  constructor(readonly db: Fixture, readonly table: string) {}
  select(columns: string, options?: { count?: string }) { this.columns = columns; this.counted = !!options?.count; return this; }
  eq(key: string, value: unknown) { this.filters.push([key, value]); return this; }
  is(key: string, value: unknown) { return this.eq(key, value); }
  in(key: string, values: unknown[]) { return this.eq(key, values); }
  order(_key: string) { return this; }
  or(_value: string) { return this; }
  range(from: number, to: number) { this.rangeBounds = [from, to]; return this; }
  maybeSingle() { this.single = true; return this; }
  async then(resolve: (result: any) => unknown) {
    this.db.calls.push({ table: this.table, columns: this.columns, filters: this.filters, range: this.rangeBounds, counted: this.counted });
    let rows = (this.db.tables[this.table] || []).filter(row => this.filters.every(([key, value]) => Array.isArray(value) ? value.includes(row[key]) : (row[key] ?? null) === value));
    const count = rows.length;
    if (this.rangeBounds) rows = rows.slice(this.rangeBounds[0], this.rangeBounds[1] + 1);
    const data = rows.map(row => Object.fromEntries(this.columns.split(',').map(key => [key, row[key]])));
    return resolve({ error: null, data: this.single ? data[0] ?? null : data, count: this.counted ? count : null });
  }
}
function setup(capabilities: readonly CorporateCapability[] = ['em.portal.read', 'em.engineering.read']) {
  const db = new Fixture(); const data = createEngineeringData(db as unknown as SupabaseClient, capabilities); return { db, data };
}
test('engineering read guard rejects unrelated catalog grants before querying anything', async () => {
  for (const caps of [[], ['em.catalogs.read', 'em.catalogs.manage', 'em.portal.read'], ['em.engineering.read']] as CorporateCapability[][]) {
    const { db, data } = setup(caps);
    await assert.rejects(data.getEngineeringMatrix(), /Acesso/); await assert.rejects(data.getEngineeringEntry(id(1)), /Acesso/);
    await assert.rejects(data.getEngineeringChoices(), /Acesso/); await assert.rejects(data.listPhotoTitles(), /Acesso/);
    assert.deepEqual(db.calls, []); assert.deepEqual(db.rpcCalls, []);
  }
});
test('matrix counts only active template relationships, excluding operational photos and stages', async () => {
  const { db, data } = setup();
  db.tables.rm_tipos_equipamento = [{ id: id(1), nome: 'Motor' }];
  db.tables.rm_celulas = [{ id: id(2), nome: 'Oficina' }];
  db.tables.rm_celula_tipos_equipamento = [{ id: id(3), tipo_equipamento_id: id(1), celula_id: id(2), ativo: true }];
  db.tables.rm_celula_form_tipos_equipamento = [true, false].map((ativo, i) => ({ id: id(10 + i), celula_tipo_equipamento_id: id(3), ativo }));
  db.tables.rm_fotos = [null, id(100)].map((projeto_id, i) => ({ id: id(20 + i), celula_tipo_equipamento_id: id(3), projeto_id, lixeira: false }));
  db.tables.rm_aprovacoes_etapas = [{ id: id(30), celula_tipo_equipamento_id: id(3), projeto_id: null, ativo: true }, { id: id(31), celula_tipo_equipamento_id: id(3), projeto_id: null, ativo: false }, { id: id(32), celula_tipo_equipamento_id: id(3), projeto_id: id(100), ativo: true }];
  db.tables.rm_fotos.push({ id: id(22), celula_tipo_equipamento_id: id(3), projeto_id: null, celula_projeto_id: id(101), lixeira: false });
  db.tables.rm_aprovacoes_etapas.push({ id: id(33), celula_tipo_equipamento_id: id(3), projeto_id: null, celula_projeto_id: id(101), ativo: true });
  const result = await data.getEngineeringMatrix();
  assert.equal(result.rows[0].form_count, 1); assert.equal(result.rows[0].photo_count, 1); assert.equal(result.rows[0].stage_count, 1);
  assert.ok(!db.calls.some(call => /foto_url|email|auth_user_id/.test(call.columns)));
});
test('snapshot uses one atomic RPC and strips operational and media columns while preserving legacy configuration exactly', async () => {
  const { db, data } = setup(); const version = '2026-10-29T12:00:01.123456+00:00';
  db.snapshot = { matrix: { id: id(1), updated_at: version, bubble_id: 'private', numero_fotos: 37 }, form_ids: [id(2)],
    photos: [{ id: id(3), cadastro_foto_id: null, numero: -1, descricao: ' legacy ', foto_url: 'https://private.invalid/p' }],
    stages: [{ id: id(4), celula_destino_id: null, status_cel_proj: null, aprovador_id: id(5), aprovadores_ids: [], aprovadores_retorno_ids: [], aprovado_por_id: id(99) }] };
  const result = await data.getEngineeringEntry(id(1)); assert.ok(result);
  assert.equal(result.matrix.updated_at, version); assert.equal(result.photos[0].numero, -1); assert.equal(result.photos[0].descricao, ' legacy ');
  assert.equal(result.stages[0].aprovador_id, id(5)); assert.equal(result.stages[0].aprovado_por_id, undefined);
  assert.equal(result.photos[0].foto_url, undefined); assert.equal(result.matrix.bubble_id, undefined);
  assert.equal(result.matrix.numero_fotos, undefined, 'Retired quantity remains in SQL history, outside the active web DTO.');
  assert.deepEqual(db.calls, []); assert.deepEqual(db.rpcCalls, [{ name: 'rm_web_engineering_snapshot_v1', args: { p_id: id(1) } }]);
  assert.equal(await data.getEngineeringEntry('invalid'), null); assert.equal(db.rpcCalls.length, 1);
});
test('choices preserve selected inactive/missing records but offer only linked active operators and no credentials', async () => {
  const { db, data } = setup();
  db.tables.rm_forms = [{ id: id(1), ativo: true, titulo: 'Active' }, { id: id(2), ativo: false, titulo: 'Retired' }];
  db.tables.rm_users = [{ id: id(4), status: 'ativo', nome: 'Linked', email: 'secret' }, { id: id(5), status: 'ativo', nome: 'Unlinked' }, { id: id(6), status: 'inativo', nome: 'Legacy' }];
  db.tables.rm_tablet_celula_users = [{ id: id(8), celula_id: id(9), identidade_id: id(4), usuario_id: 'private-auth' }];
  const result = await data.getEngineeringChoices({ matrix: { id: id(10) }, form_ids: [id(2), id(3)], photos: [], stages: [{ id: id(11), aprovadores_ids: [id(6), id(7)], aprovadores_retorno_ids: [] }] });
  assert.deepEqual(result.forms.map(row => row.id), [id(1), id(2), id(3)]); assert.equal(result.forms[2].missing, true);
  assert.deepEqual(result.users.map(row => row.id), [id(4), id(6), id(7)]); assert.equal(result.users[2].missing, true);
  assert.ok(!JSON.stringify(result).includes('secret')); assert.ok(!JSON.stringify(result).includes('private-auth'));
});
test('photo-title list has true pagination/count and legacy unknown or ambiguous scope never becomes global', async () => {
  const { db, data } = setup();
  db.tables.rm_cadastro_fotos = Array.from({ length: 63 }, (_, n) => ({ id: id(n + 100), titulo: `Photo${n}`, celula_nome: null }));
  const result = await data.listPhotoTitles({ page: 2 }); assert.equal(result.total, 63); assert.equal(result.rows.length, 13);
  assert.equal(result.rows[0].titulo, 'Photo50'); assert.equal(result.rows[0].celula_id, null);
  const cells = [{ id: id(1), nome: 'Duplicate' }, { id: id(2), nome: 'Duplicate' }, { id: id(3), nome: 'Unique' }];
  assert.equal(photoTitleScope({ id: id(4), celula_nome: 'Unique' }, cells).celula_id, id(3));
  assert.equal(photoTitleScope({ id: id(4), celula_nome: ' unique ' }, cells).celula_id, id(3));
  for (const name of ['Duplicate', 'Missing']) {
    const row = photoTitleScope({ id: id(4), celula_nome: name }, cells); assert.equal(row.scope_resolved, false); assert.equal(Object.hasOwn(row, 'celula_id'), false);
  }
  for (const name of [null, '', '   ', '\t', ' \n\t ']) {
    const row = photoTitleScope({ id: id(4), celula_nome: name }, cells);
    assert.equal(row.celula_id, null); assert.equal(row.scope_resolved, true); assert.equal(row.scope_ambiguous, false);
  }
});
