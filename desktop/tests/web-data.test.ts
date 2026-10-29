import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createWebData, type WebRow } from '../src/server/web/data';
import type { CorporateCapability } from '../src/server/web/sso-policy';

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
function setup(capabilities?: readonly CorporateCapability[]) { const db = new Fixture(); return { db, data: createWebData(db as unknown as SupabaseClient, capabilities) }; }

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

test('portal-only access performs no operational queries and does not invent zero counts', async () => {
  const { db, data } = setup(['em.portal.read']);
  const overview = await data.getOverview();
  assert.deepEqual(overview.access, { projects: false, forms: false, planning: false, documents: false });
  assert.ok(Object.values(overview.counts).every(value => value === null));
  assert.deepEqual(overview.tasks, []); assert.deepEqual(overview.recentProjects, []);
  assert.equal(db.calls.length, 0);
  await assert.rejects(data.listProjects(), /Acesso/);
  await assert.rejects(data.getRecord(id(1)), /Acesso/);
  await assert.rejects(data.listForms(), /Acesso/);
  await assert.rejects(data.listPlanning(), /Acesso/);
  await assert.rejects(data.getCatalogs(), /Acesso/);
  await assert.rejects(data.editorChoices(), /Acesso/);
  assert.equal(db.calls.length, 0);
});

test('project-only scope omits child queries and document URLs from the returned project', async () => {
  const { db, data } = setup(['em.portal.read', 'em.projects.read']);
  db.tables.set('rm_projetos', [{ id: id(1), cliente_id: id(2), numero: 'OS', arquivo_nota_fiscal_url: 'https://private.test/invoice', documento_proposta_url: 'https://private.test/proposal' }]);
  db.tables.set('rm_clientes', [{ id: id(2), nome: 'Cliente' }]);
  const project = await data.getProject(id(1));
  assert.ok(project); assert.equal(project.project.numero, 'OS');
  assert.equal(project.project.arquivo_nota_fiscal_url, undefined); assert.equal(project.project.documento_proposta_url, undefined);
  for (const field of ['allocations', 'cells', 'forms', 'records', 'stages', 'comments', 'users', 'photos', 'documents', 'attachments'] as const) assert.deepEqual(project[field], []);
  assert.ok(db.calls.every(call => ['rm_projetos', 'rm_clientes', 'rm_equipamentos'].includes(call.table)));
  const calls = db.calls.length;
  await assert.rejects(data.listProjects({ cell: id(3) }), /Acesso/);
  assert.equal(db.calls.length, calls);
});

test('form scope redacts media in columns, typed answers and legacy JSON while preserving ordinary answers', async () => {
  const { db, data } = setup(['em.portal.read', 'em.forms.read']);
  db.tables.set('rm_registros_formulario', [{ id: id(1), projeto_id: id(2), form_id: id(3), identidade_user_id: id(4) }]);
  db.tables.set('rm_users', [{ id: id(4), nome: 'Operador', foto_url: 'https://private.test/avatar' }]);
  const answer = (n: number, extra: Record<string, unknown>) => ({ id: id(n), registro_formulario_id: id(1), ...extra });
  db.tables.set('rm_respostas', [
    answer(10, { tipo: 'texto', resposta: 'Conforme', fotos_urls: ['https://private.test/photo'] }),
    answer(11, { tipo: 'foto', resposta: 'opaque-file-key', itens: ['legacy'], itens_questoes_ids: [id(30)] }),
    answer(12, { tipo: 'texto', resposta: { imagens: ['https://private.test/legacy'] } }),
    answer(13, { tipo: 'assinatura', assinatura_url: 'https://private.test/signature' }),
    answer(14, { tipo: 'texto', itens: [{ arquivo: '//private.test/item.jpg' }] }),
    answer(15, { tipo: null, questao_id: id(20), resposta: 'opaque-other-key' }),
  ]);
  db.tables.set('rm_questoes', [{ id: id(20), form_id: id(3), tipo: 'foto_antes_depois' }]);
  const result = await data.getRecord(id(1)); assert.ok(result);
  assert.equal(result.project, null); assert.ok(!db.calls.some(call => call.table === 'rm_projetos'));
  assert.equal(result.users[0].foto_url, undefined);
  assert.equal(result.answers[0].resposta, 'Conforme'); assert.equal(result.answers[0].media_restricted, undefined);
  for (const row of result.answers.slice(1)) { assert.equal(row.media_restricted, true); assert.equal(row.resposta, null); assert.deepEqual(row.itens, []); assert.deepEqual(row.itens_questoes_ids, []); }
  assert.ok(result.answers.every(row => row.fotos_urls === undefined && row.assinatura_url === undefined));
  assert.ok(!JSON.stringify(result).includes('private.test'));
  assert.ok(!db.calls.find(call => call.table === 'rm_respostas')?.columns.includes('fotos_urls'));
});

test('explicit photos capability preserves submitted media for permitted form consultation', async () => {
  const { db, data } = setup(['em.portal.read', 'em.forms.read', 'em.photos.read']);
  db.tables.set('rm_registros_formulario', [{ id: id(1), form_id: id(3) }]);
  db.tables.set('rm_respostas', [{ id: id(10), registro_formulario_id: id(1), tipo: 'foto', resposta: { imagens: ['https://media.test/a.jpg'] }, fotos_urls: ['https://media.test/b.jpg'] }]);
  const result = await data.getRecord(id(1));
  assert.deepEqual(result?.answers[0].resposta, { imagens: ['https://media.test/a.jpg'] });
  assert.deepEqual(result?.answers[0].fotos_urls, ['https://media.test/b.jpg']);
  assert.equal(result?.answers[0].media_restricted, undefined);
});

test('planning without project capability does not join or load the project table', async () => {
  const { db, data } = setup(['em.portal.read', 'em.planning.read']);
  db.tables.set('rm_celulas_projeto', [{ id: id(1), projeto_id: id(2), numero_projeto: 'OS' }]);
  const result = await data.listPlanning({ q: 'OS' });
  assert.equal(result.rows[0].numero_projeto, 'OS'); assert.deepEqual(result.projects, []);
  assert.ok(!db.calls.some(call => call.table === 'rm_projetos' || call.columns.includes('project:')));
});

test('editor reference choices require manage and expose only fields needed by that editor', async () => {
  const readonly = setup(['em.portal.read', 'em.projects.read', 'em.planning.read']);
  await assert.rejects(readonly.data.editorChoices('project'), /Acesso/);
  await assert.rejects(readonly.data.editorChoices('planning'), /Acesso/);
  assert.equal(readonly.db.calls.length, 0);
  const { db, data } = setup(['em.portal.read', 'em.planning.manage']);
  db.tables.set('rm_users', [{ id: id(1), nome: 'Operador', status: 'ativo', matricula: 'private', foto_url: 'https://private.test/photo', auth_user_id: id(2) }]);
  db.tables.set('rm_forms', [{ id: id(3), titulo: 'Modelo', ativo: true, descricao: 'Not needed by editor' }]);
  db.tables.set('rm_form_template_versions', [{ id: id(3), form_id: id(3), version: 2, id_mapping: { private: 'not needed' } }]);
  const choices = await data.editorChoices('planning');
  assert.deepEqual(choices.users, [{ id: id(1), nome: 'Operador', status: 'ativo' }]);
  assert.deepEqual(choices.forms, [{ id: id(3), titulo: 'Modelo · v2', ativo: true, titulo_modelo: 'Modelo', versao_modelo: 2 }]);
  assert.ok(db.calls.every(call => ['rm_users', 'rm_forms', 'rm_form_template_versions'].includes(call.table)));
  assert.equal(db.calls.find(call => call.table === 'rm_form_template_versions')?.columns, 'form_id,version');
});

test('catalog permission alone excludes user images, and every domain still requires portal permission', async () => {
  const { db, data } = setup(['em.portal.read', 'em.catalogs.read']);
  db.tables.set('rm_users', [{ id: id(1), nome: 'Operador', foto_url: 'https://private.test/photo' }]);
  const catalog = await data.getCatalogs({ kind: 'users' });
  assert.equal(catalog.rows[0].foto_url, undefined);
  assert.ok(!db.calls[0].columns.includes('foto_url'));
  const missingPortal = setup(['em.projects.read']);
  await assert.rejects(missingPortal.data.getProject(id(1)), /Acesso/);
  assert.equal(missingPortal.db.calls.length, 0);
});

test('catalog edit lookup uses an explicit supported table and returns exact concurrency version', async () => {
  const { db, data } = setup(['em.portal.read', 'em.catalogs.manage']);
  const version = '2026-10-29T18:03:24.123456+00:00';
  db.tables.set('rm_celulas', [{ id: id(1), nome: 'Célula', indice: 5, ordem: 7, updated_at: version, private_metadata: 'excluded' }]);
  const row = await data.getCatalogEntry('cells', id(1));
  assert.equal(row?.updated_at, version); assert.equal(row?.ordem, 7); assert.equal(row?.private_metadata, undefined);
  const calls = db.calls.length;
  assert.equal(await data.getCatalogEntry('users' as any, id(1)), null);
  assert.equal(await data.getCatalogEntry('clients', 'bad-id'), null);
  assert.equal(db.calls.length, calls);
  const readonly = setup(['em.portal.read', 'em.catalogs.read']);
  await assert.rejects(readonly.data.getCatalogEntry('clients', id(1)), /Acesso/); assert.equal(readonly.db.calls.length, 0);
});
