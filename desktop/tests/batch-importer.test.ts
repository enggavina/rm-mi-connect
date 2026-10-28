import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { BatchImporter } from '../src/server/bridge/batch-importer';
import { Bridge } from '../src/server/bridge/engine';
import { BubbleClient } from '../src/server/bridge/client';
import { getEntity, type Row } from '../src/server/bridge/mapping';

type Result = { data: any; error: { code: string; message: string } | null };
class Database {
  tables = new Map<string, Row[]>();
  calls: { table: string; operation: string; rows?: Row[]; options?: Row }[] = [];
  rpcCalls: { name: string; args: Row }[] = [];
  error: { code: string; message: string } | null = null;
  sequence = 0;
  rows(table: string) { if (!this.tables.has(table)) this.tables.set(table, []); return this.tables.get(table)!; }
  from(table: string) { return new Query(this, table); }
  async rpc(name: string, args: Row) { this.rpcCalls.push({ name, args }); return { data: true, error: null }; }
}
class Query implements PromiseLike<Result> {
  private operation = 'select'; private columns = '*'; private filters: ((row: Row) => boolean)[] = [];
  private bounds?: [number, number]; private limitSize?: number; private payload: Row[] = []; private options: Row = {};
  private singleton = false;
  constructor(private db: Database, private table: string) {}
  select(columns = '*') { this.columns = columns; return this; }
  order(_column: string) { return this; }
  range(start: number, end: number) { this.bounds = [start, end]; return this; }
  limit(count: number) { this.limitSize = count; return this; }
  eq(key: string, value: unknown) { this.filters.push(row => row[key] === value); return this; }
  neq(key: string, value: unknown) { this.filters.push(row => row[key] !== value); return this; }
  is(key: string, value: unknown) { this.filters.push(row => (row[key] ?? null) === value); return this; }
  in(key: string, values: unknown[]) { this.filters.push(row => values.includes(row[key])); return this; }
  upsert(rows: Row | Row[], options: Row) { this.operation = 'upsert'; this.payload = Array.isArray(rows) ? rows : [rows]; this.options = options; return this; }
  update(row: Row) { this.operation = 'update'; this.payload = [row]; return this; }
  single() { this.singleton = true; return this; }
  maybeSingle() { this.singleton = true; return this; }
  private execute(): Result {
    this.db.calls.push({ table: this.table, operation: this.operation, rows: this.payload, options: this.options });
    const storage = this.db.rows(this.table);
    let selected: Row[];
    if (this.operation === 'upsert') {
      if (this.db.error) return { data: null, error: this.db.error };
      if (this.payload.some(row => row.nome === 'invalid-database-row')) return { data: null, error: { code: '23514', message: 'fixture check constraint' } };
      selected = this.payload.map(row => {
        const existing = storage.find(value => value[String(this.options.onConflict)] === row[String(this.options.onConflict)]);
        if (existing) { Object.assign(existing, row); return existing; }
        const inserted = { ...(this.table === 'rm_forms' ? { ativo: true } : {}), ...row, id: row.id || `generated-${++this.db.sequence}` };
        storage.push(inserted); return inserted;
      });
    } else {
      selected = storage.filter(row => this.filters.every(filter => filter(row)));
      if (this.operation === 'update') for (const row of selected) Object.assign(row, this.payload[0]);
    }
    if (this.bounds) selected = selected.slice(this.bounds[0], this.bounds[1] + 1);
    if (this.limitSize !== undefined) selected = selected.slice(0, this.limitSize);
    const projected = selected.map(row => this.columns === '*' ? { ...row } : Object.fromEntries(this.columns.split(',').map(key => [key, row[key]])));
    return { data: this.singleton ? projected[0] || null : projected, error: null };
  }
  then<TResult1 = Result, TResult2 = never>(fulfilled?: ((value: Result) => TResult1 | PromiseLike<TResult1>) | null,
    rejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null): PromiseLike<TResult1 | TResult2> {
    return Promise.resolve().then(() => this.execute()).then(fulfilled, rejected);
  }
}
const date = '2026-10-27T12:00:00.000Z';
function fixture() {
  const db = new Database();
  db.tables.set('rm_option_sets', [
    { option_set_key: 'tipo_quest_o', option_key: 'texto_curto', bubble_display: 'Texto Curto' },
    { option_set_key: 'tipo_de_usu_rio', option_key: 'mobile', bubble_display: 'Mobile' },
  ]);
  const bridge = new Bridge(db as unknown as SupabaseClient, {} as BubbleClient);
  return { db, bridge, importer: new BatchImporter(bridge) };
}

test('one page of 100 questions uses cached form IDs and one upsert', async () => {
  const { db, importer } = fixture();
  db.rows('rm_forms').push({ id: 'form-id', bubble_id: 'remote-form' });
  await importer.preload(); db.calls = [];
  const rows = Array.from({ length: 100 }, (_, i) => ({ _id: `question-${i}`, 'Modified Date': date, Form: 'remote-form', Enunciado: `Q${i}`, Tipo: 'Texto Curto' }));
  assert.deepEqual(await importer.importPage(getEntity('rm_questoes'), rows, () => assert.fail('unexpected quarantine')), { loaded: 100, unchanged: 0 });
  assert.equal(db.calls.filter(call => call.operation === 'upsert').length, 1);
  assert.equal(db.calls.filter(call => call.table === 'rm_forms').length, 0);
  assert.equal(db.rows('rm_questoes')[0].form_id, 'form-id');
});

test('data errors bisect a page and quarantine only the invalid row', async () => {
  const { db, importer } = fixture(); await importer.preload();
  const quarantined: Row[] = [];
  const rows = Array.from({ length: 8 }, (_, i) => ({ _id: `client-${i}`, 'Modified Date': date, Nome: i === 3 ? 'invalid-database-row' : `Client ${i}` }));
  const result = await importer.importPage(getEntity('rm_clientes'), rows, raw => { quarantined.push(raw); });
  assert.deepEqual(result, { loaded: 7, unchanged: 0 });
  assert.deepEqual(quarantined.map(row => row._id), ['client-3']);
  assert.equal(db.rows('rm_clientes').length, 7);
});

test('different shapes retain server defaults and explicit false values', async () => {
  const { db, importer } = fixture(); await importer.preload();
  await importer.importPage(getEntity('rm_forms'), [
    { _id: 'default', 'Modified Date': date, Titulo: 'Default' },
    { _id: 'disabled', 'Modified Date': date, Titulo: 'Disabled', Ativo: false },
  ], () => assert.fail('unexpected quarantine'));
  assert.equal(db.rows('rm_forms').find(row => row.bubble_id === 'default')?.ativo, true);
  assert.equal(db.rows('rm_forms').find(row => row.bubble_id === 'disabled')?.ativo, false);
  assert.equal(db.calls.filter(call => call.operation === 'upsert').length, 2);
  assert.ok(db.calls.filter(call => call.operation === 'upsert').every(call => call.options?.defaultToNull === false));
});

for (const mode of ['single', 'batch'] as const) test(`${mode} document metadata import retains the resolved PDF only for the same source key`, async () => {
  const { db, bridge, importer } = fixture();
  const id = '49c12f88-1074-4c38-814d-3b2b95cb727d';
  const url = `https://example.supabase.co/storage/v1/object/authenticated/rm-documentos/legacy/${id}.pdf`;
  db.rows('rm_projetos').push({ id: 'project-id', bubble_id: 'remote-project' });
  db.rows('rm_documentos').push({ id, projeto_id: 'project-id', bubble_id: 'remote-document', bubble_modified_at: '2026-10-26T00:00:00Z', s3_key: 'original.pdf', arquivo_url: url, nome: 'Original' });
  if (mode === 'batch') await importer.preload();
  const apply = async (raw: Row) => mode === 'single' ? bridge.apply(getEntity('rm_documentos'), raw) : importer.importPage(getEntity('rm_documentos'), [raw], () => assert.fail('unexpected quarantine'));
  await apply({ _id: 'remote-document', 'Modified Date': date, Projeto: 'remote-project', Nome: 'Updated metadata', PDF: 'original.pdf' });
  assert.equal(db.rows('rm_documentos')[0].arquivo_url, url);
  assert.equal(db.rows('rm_documentos')[0].nome, 'Updated metadata');
  await apply({ _id: 'remote-document', 'Modified Date': '2026-10-28T00:00:00Z', Projeto: 'remote-project', Nome: 'New source file', PDF: 'replacement.pdf' });
  assert.equal(db.rows('rm_documentos')[0].arquivo_url, null);
  assert.equal(db.rows('rm_documentos')[0].s3_key, 'replacement.pdf');
});

test('email merge keeps the real Auth link, local administrator role and matricula', async () => {
  const { db, importer } = fixture();
  db.rows('rm_users').push({ id: 'local-admin', bubble_id: null, auth_user_id: 'auth-admin', email: 'digital@example.test',
    email_corporativo: 'digital@example.test', perfil: 'administrador', matricula: 'DIGITAL' });
  await importer.preload();
  await importer.importPage(getEntity('rm_users'), [{ _id: 'new-bubble-user', 'Modified Date': date, Nome: 'Digital',
    email_corporativo: 'Digital@example.test', Matricula: '999', Perfil: 'Mobile', auth_user_id: 'spoofed', palavra_chave: 'must-not-copy' }], () => assert.fail('unexpected quarantine'));
  const [row] = db.rows('rm_users');
  assert.equal(db.rows('rm_users').length, 1);
  assert.equal(row.auth_user_id, 'auth-admin'); assert.equal(row.perfil, 'administrador'); assert.equal(row.matricula, 'DIGITAL');
  assert.equal(row.bubble_id, 'new-bubble-user'); assert.equal(row.palavra_chave, undefined);
});

test('pending project bundle protects new child answers as well as existing records', async () => {
  const { db, importer } = fixture();
  db.rows('rm_registros_formulario').push({ id: 'record-id', bubble_id: 'remote-record', projeto_id: 'project-id' });
  db.rows('rm_questoes').push({ id: 'question-id', bubble_id: 'remote-question' });
  db.rows('rm_sync_outbox').push({ record_id: 'project-id', target_system: 'bubble_data_api', status: 'pending' });
  await importer.preload(); const problems: string[] = [];
  const result = await importer.importPage(getEntity('rm_respostas'), [{ _id: 'response', 'Modified Date': date,
    Registro_Formulario: 'remote-record', Questao: 'remote-question', Resposta: 'remote value' }], (_raw, error) => { problems.push(error.message); });
  assert.deepEqual(result, { loaded: 0, unchanged: 0 }); assert.equal(db.rows('rm_respostas').length, 0);
  assert.match(problems[0], /Conflito pendente/);
});

test('blank optional matriculas become NULL instead of conflicting on empty strings', async () => {
  const { db, importer } = fixture(); await importer.preload();
  const rows = ['', '  '].map((value, i) => ({ _id: `user-${i}`, 'Modified Date': date, Nome: `User ${i}`, Matricula: value }));
  assert.deepEqual(await importer.importPage(getEntity('rm_users'), rows, () => assert.fail('unexpected quarantine')), { loaded: 2, unchanged: 0 });
  assert.ok(db.rows('rm_users').every(row => row.matricula === null));
});

test('an unresolved foreign key isolates that row while valid neighbors import', async () => {
  const { db, bridge, importer } = fixture();
  db.rows('rm_forms').push({ id: 'form-id', bubble_id: 'valid-form' });
  bridge.bubble.get = async () => { throw new Error('Bubble GET /obj/form/missing-form: HTTP 404'); };
  await importer.preload(); const problems: Row[] = [];
  const rows = ['missing-form', 'valid-form'].map((form, i) => ({ _id: `q${i}`, 'Modified Date': date, Form: form, Enunciado: `Q${i}`, Tipo: 'Texto Curto' }));
  assert.deepEqual(await importer.importPage(getEntity('rm_questoes'), rows, raw => { problems.push(raw); }), { loaded: 1, unchanged: 0 });
  assert.equal(problems.length, 1); assert.equal(problems[0]._id, 'q0');
  assert.equal(db.rows('rm_questoes')[0].bubble_id, 'q1');
});

test('omitted scope fields clear old delivery and terminal status when a project reopens', async () => {
  const { db, importer } = fixture();
  db.rows('rm_projetos').push({ id: 'project-id', bubble_id: 'remote-project', numero: '001',
    bubble_modified_at: '2026-10-26T10:00:00Z', data_real_de_entrega: '2026-10-26T09:00:00Z', status_pcp: 'finalizando_para_faturar' });
  await importer.preload();
  await importer.importPage(getEntity('rm_projetos'), [{ _id: 'remote-project', 'Modified Date': date, Numero: '001' }], () => assert.fail('unexpected quarantine'));
  assert.equal(db.rows('rm_projetos')[0].data_real_de_entrega, null);
  assert.equal(db.rows('rm_projetos')[0].status_pcp, null);
});

test('form sequence advances once per form and unchanged records can repair it', async () => {
  const { db, importer } = fixture();
  db.rows('rm_projetos').push({ id: 'project-id', bubble_id: 'remote-project' });
  db.rows('rm_forms').push({ id: 'form-id', bubble_id: 'remote-form' });
  await importer.preload();
  const rows = [1, 9, 3].map(code => ({ _id: `record-${code}`, 'Modified Date': date,
    ProjetoRM: 'remote-project', Form: 'remote-form', Codigo: code }));
  await importer.importPage(getEntity('rm_registros_formulario'), rows, () => assert.fail('unexpected quarantine'));
  assert.equal(db.rpcCalls.length, 1); assert.equal(db.rpcCalls[0].args.p_code, 9);
  assert.deepEqual(await importer.importPage(getEntity('rm_registros_formulario'), rows, () => assert.fail('unexpected quarantine')),
    { loaded: 0, unchanged: 3 });
  assert.equal(db.rpcCalls[1].args.p_code, 9);
});

test('infrastructure errors stop the page instead of quarantining every record', async () => {
  const { db, importer } = fixture(); await importer.preload(); db.error = { code: '42501', message: 'permission denied' };
  let quarantines = 0;
  await assert.rejects(importer.importPage(getEntity('rm_clientes'), [{ _id: 'client', 'Modified Date': date, Nome: 'Client' }], () => { quarantines++; }), /permission denied/);
  assert.equal(quarantines, 0);
});

test('missing references are validated and resolved once then cached across the page', async () => {
  const { db, bridge, importer } = fixture(); let fetched = 0, applied = 0;
  bridge.bubble.get = async () => { fetched++; return { _id: 'remote-form', 'Modified Date': date, Titulo: 'Missing form' }; };
  bridge.apply = async (_entity, raw) => { applied++; db.rows('rm_forms').push({ id: 'resolved-form', bubble_id: raw._id, bubble_modified_at: date }); return 'resolved-form'; };
  await importer.preload();
  await importer.importPage(getEntity('rm_questoes'), [1, 2, 3].map(i => ({ _id: `q${i}`, 'Modified Date': date,
    Form: 'remote-form', Enunciado: `Q${i}`, Tipo: 'Texto Curto' })), () => assert.fail('unexpected quarantine'));
  assert.equal(fetched, 1); assert.equal(applied, 1);
});
