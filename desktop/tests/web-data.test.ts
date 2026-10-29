import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createWebData, type WebRow } from '../src/server/web/data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
class Fixture {
  tables = new Map<string, WebRow[]>();
  calls: { table: string; columns: string; filters: [string, string, unknown][]; range?: [number, number]; count?: string; head?: boolean }[] = [];
  from(table: string) { return new Query(this, table); }
}
class Query {
  columns = '*'; filters: [string, string, unknown][] = []; bounds?: [number, number]; maximum?: number;
  counted?: string; head = false; single = false;
  constructor(readonly db: Fixture, readonly table: string) {}
  select(columns = '*', options: { count?: string; head?: boolean } = {}) { this.columns = columns; this.counted = options.count; this.head = !!options.head; return this; }
  eq(key: string, value: unknown) { this.filters.push(['eq', key, value]); return this; }
  neq(key: string, value: unknown) { this.filters.push(['neq', key, value]); return this; }
  is(key: string, value: unknown) { this.filters.push(['eq', key, value]); return this; }
  not(key: string, _operator: string, value: unknown) { return this.neq(key, value); }
  in(key: string, value: unknown[]) { this.filters.push(['in', key, value]); return this; }
  lt(key: string, value: unknown) { this.filters.push(['lt', key, value]); return this; }
  or(_filter: string, _options?: unknown) { return this; }
  order(_key: string, _options?: unknown) { return this; }
  range(from: number, to: number) { this.bounds = [from, to]; return this; }
  limit(value: number) { this.maximum = value; return this; }
  maybeSingle() { this.single = true; return this; }
  async then(resolve: (result: any) => unknown, reject?: (error: unknown) => unknown) {
    try {
      this.db.calls.push({ table: this.table, columns: this.columns, filters: this.filters, range: this.bounds, count: this.counted, head: this.head });
      let rows = (this.db.tables.get(this.table) || []).filter(row => this.filters.every(([op, key, value]) => op === 'eq' ? (row[key] ?? null) === value : op === 'neq' ? (row[key] ?? null) !== value : op === 'in' ? (value as unknown[]).includes(row[key]) : row[key] != null && row[key] < value!));
      const count = rows.length;
      if (this.bounds) rows = rows.slice(this.bounds[0], this.bounds[1] + 1);
      if (this.maximum !== undefined) rows = rows.slice(0, this.maximum);
      const data = rows.map(row => Object.fromEntries(this.columns.split(',').map(column => [column, row[column]])));
      return resolve({ error: null, data: this.head ? null : this.single ? data[0] || null : data, count: this.counted ? count : null });
    } catch (error) { if (reject) return reject(error); throw error; }
  }
}
function setup() { const db = new Fixture(); return { db, data: createWebData(db as unknown as SupabaseClient) }; }

test('project listing uses a real page/count and paginates reference catalogs beyond 1000 rows', async () => {
  const { db, data } = setup();
  db.tables.set('rm_projetos', Array.from({ length: 63 }, (_, i) => ({ id: id(i + 1), numero: `OS${i}`, cliente_id: id(1000) })));
  db.tables.set('rm_clientes', Array.from({ length: 1001 }, (_, i) => ({ id: id(i + 1000), nome: `Cliente${i}` })));
  const result = await data.listProjects({ page: 2 });
  assert.equal(result.total, 63); assert.equal(result.rows.length, 25); assert.equal(result.rows[0].numero, 'OS25');
  assert.equal(result.clients.length, 1001); assert.equal(result.rows[0].cliente_nome, 'Cliente0');
  assert.deepEqual(db.calls.find(call => call.table === 'rm_projetos')?.range, [25, 49]);
  assert.equal(db.calls.filter(call => call.table === 'rm_clientes').length, 3);
  assert.ok(!db.calls.some(call => call.table === 'rm_respostas'));
});
test('record consultation loads only its answers, including snapshots, across server pages', async () => {
  const { db, data } = setup();
  db.tables.set('rm_registros_formulario', [{ id: id(1), projeto_id: id(2), form_id: id(3), identidade_user_id: id(4) }]);
  db.tables.set('rm_projetos', [{ id: id(2), numero: 'OS' }]); db.tables.set('rm_forms', [{ id: id(3), titulo: 'Form' }]);
  db.tables.set('rm_respostas', [...Array.from({ length: 501 }, (_, i) => ({ id: id(i + 100), registro_formulario_id: id(1), questao_id: null, enunciado: 'Historical', resposta: 'Preserved' })), { id: id(999), registro_formulario_id: id(888), resposta: 'Other record' }]);
  db.tables.set('rm_users', [{ id: id(4), nome: 'Operador', auth_user_id: 'private', email: 'private@example.test', tentativas_login: 4 }]);
  const result = await data.getRecord(id(1));
  assert.equal(result?.answers.length, 501); assert.ok(result?.answers.every(row => row.registro_formulario_id === id(1)));
  assert.equal(result?.answers[0].questao_id, null); assert.equal(result?.answers[0].resposta, 'Preserved');
  assert.equal(result?.users[0].auth_user_id, undefined); assert.equal(result?.users[0].email, undefined);
  assert.ok(db.calls.filter(call => call.table === 'rm_respostas').every(call => call.filters.some(filter => filter[1] === 'registro_formulario_id' && filter[2] === id(1))));
});
test('project detail paginates photos and does not materialize historical answers', async () => {
  const { db, data } = setup();
  db.tables.set('rm_projetos', [{ id: id(1), numero: 'OS' }]);
  db.tables.set('rm_fotos', Array.from({ length: 60 }, (_, i) => ({ id: id(i + 2), projeto_id: id(1), lixeira: false, foto_url: `https://cdn.example/${i}.jpg`, numero: i })));
  const result = await data.getProject(id(1), { photoPage: 2 });
  assert.equal(result?.photoTotal, 60); assert.equal(result?.photos.length, 24); assert.equal(result?.photos[0].numero, 24);
  assert.ok(!db.calls.some(call => call.table === 'rm_respostas'));
  assert.equal(await data.getProject('not-a-uuid'), null);
});
test('overview counts are head-only; recent items remain bounded and no response table is loaded', async () => {
  const { db, data } = setup();
  db.tables.set('rm_projetos', Array.from({ length: 40 }, (_, i) => ({ id: id(i + 1), data_real_de_entrega: null, cliente_id: id(2000), cliente_nome_exportacao: 'Exportação antiga' })));
  db.tables.set('rm_clientes', [{ id: id(2000), nome: 'Cliente vinculado atual' }]);
  db.tables.set('rm_registros_formulario', Array.from({ length: 50 }, (_, i) => ({ id: id(i + 100), status: 'em_an_lise' })));
  const result = await data.getOverview();
  assert.equal(result.counts.projects, 40); assert.equal(result.counts.awaitingReview, 50);
  assert.equal(result.recentProjects.length, 8); assert.equal(result.recentRecords.length, 8);
  assert.equal(result.recentProjects[0].cliente_nome, 'Cliente vinculado atual');
  assert.ok(db.calls.filter(call => call.count).every(call => call.head));
  assert.ok(!db.calls.some(call => call.table === 'rm_respostas'));
});
