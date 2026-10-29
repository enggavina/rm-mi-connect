import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createFormTemplateData } from '../src/server/web/form-template-data';
import type { CorporateCapability } from '../src/server/web/sso-policy';
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:00:00.123456+00:00';
const content = { titulo: 'Modelo', descricao: null, title: null, description: null, tipo: null, questions: [] };
class Fixture {
  tables: Record<string, any[]> = {}; snapshots: Record<string, any> = {}; calls: any[] = []; rpcCalls: any[] = [];
  from(table: string) { return new Query(this, table); }
  async rpc(name: string, args: any) { this.rpcCalls.push({ name, args }); return { data: this.snapshots[name] ?? null, error: null }; }
}
class Query {
  columns = ''; rangeBounds?: [number, number]; counted = false; filters: [string, any][] = []; orders: string[] = [];
  constructor(readonly db: Fixture, readonly table: string) {}
  select(columns: string, options?: { count?: string }) { this.columns = columns; this.counted = !!options?.count; return this; }
  eq(key: string, value: any) { this.filters.push([key, value]); return this; }
  in(key: string, values: any[]) { return this.eq(key, values); }
  order(key: string) { this.orders.push(key); return this; }
  ilike(key: string, value: string) { this.filters.push([`like:${key}`, value]); return this; }
  or(value: string) { this.filters.push(['or', value]); return this; }
  range(from: number, to: number) { this.rangeBounds = [from, to]; return this; }
  async then(resolve: (value: any) => unknown) {
    this.db.calls.push({ table: this.table, columns: this.columns, range: this.rangeBounds, counted: this.counted, filters: this.filters, orders: this.orders });
    let rows = (this.db.tables[this.table] ?? []).filter(row => this.filters.every(([key, value]) => key.startsWith('like:') || key === 'or' || (Array.isArray(value) ? value.includes(row[key]) : row[key] === value)));
    const count = rows.length;
    if (this.rangeBounds) rows = rows.slice(this.rangeBounds[0], this.rangeBounds[1] + 1);
    // A PostgREST fixture only returns selected columns, including the explicit nested metadata relation.
    const fields = this.columns.replace(',version_info:rm_form_template_versions(version,family_id,legacy)', ',version_info').split(',');
    rows = rows.map(row => Object.fromEntries(fields.map(field => field === 'titulo:content->>titulo' ? ['titulo', row.content?.titulo] : [field, row[field]])));
    return resolve({ error: null, data: rows, count: this.counted ? count : null });
  }
}
function setup(capabilities: readonly CorporateCapability[] = ['em.portal.read','em.form_templates.read']) {
  const db = new Fixture(); return { db, data: createFormTemplateData(db as unknown as SupabaseClient, capabilities) };
}

test('form builder read requires domain capability before every query', async () => {
  for (const caps of [[], ['em.portal.read','em.forms.read','em.engineering.manage'], ['em.form_templates.read']] as CorporateCapability[][]) {
    const { db, data } = setup(caps);
    await assert.rejects(data.listFormTemplates(), /Acesso/); await assert.rejects(data.getFormTemplate(id(1)), /Acesso/);
    await assert.rejects(data.getPublishedFormTemplate(id(1)), /Acesso/); await assert.rejects(data.getFormTemplateChoices(), /Acesso/);
    assert.deepEqual(db.calls, []); assert.deepEqual(db.rpcCalls, []);
  }
});

test('lists use true counts and page bounds, read version metadata without inventing a versions.id column', async () => {
  const { db, data } = setup();
  db.tables.rm_forms = Array.from({ length: 51 }, (_, n) => ({ id: id(n + 1), titulo: `Form${n}`, version_info: n === 25 ? [{ version: 2, family_id: id(500), legacy: false }] : [], imagem_capa_url: 'private' }));
  db.tables.rm_form_template_drafts = Array.from({ length: 27 }, (_, n) => ({ id: id(n + 100), state: 'draft', content: { ...content, titulo: `Draft${n}` }, source_snapshot: { imagem_capa_url: 'private' }, created_by: 'private' }));
  const result = await data.listFormTemplates({ page: 2, q: 'Motor', state: 'draft' });
  assert.equal(result.publishedTotal, 51); assert.equal(result.draftTotal, 27); assert.equal(result.published.length, 25); assert.equal(result.drafts.length, 2);
  assert.equal(result.published[0].version, 2); assert.equal(result.published[0].family_id, id(500)); assert.equal(result.published[1].version, 1);
  assert.equal(result.drafts[0].titulo, 'Draft25'); assert.ok(!JSON.stringify(result).includes('private'));
  for (const call of db.calls) { assert.deepEqual(call.range, [25, 49]); assert.equal(call.counted, true); assert.ok(!/\*|source_snapshot|created_by|updated_by|imagem_capa_url/.test(call.columns)); }
  assert.ok(db.calls.find(call => call.table === 'rm_forms').columns.includes('rm_form_template_versions(version,family_id,legacy)'));
});

test('atomic draft/source reads sanitize metadata, actors and URLs while preserving exact revision and decimal strings', async () => {
  const { db, data } = setup();
  const metadata = { usa_aprovacao: true, imagem_capa_url: 'https://private.invalid/secret', celulas_ids: [id(2), 'bad'], equipes_ids: [], auth_user_id: 'private' };
  const draft = { id: id(1), kind: 'copy', state: 'draft', source_form_id: id(3), family_id: null, source_version: 1, content, source_snapshot: metadata, created_at: version, updated_at: version, published_form_id: null, created_by: 'private' };
  db.snapshots.rm_web_form_template_snapshot_v1 = { draft, publication: { form_id: id(3), version: 2, id_mapping: { questions: { [id(4)]: id(5), private: 'secret' }, items: {} }, token: 'private' }, actor: 'private' };
  db.snapshots.rm_web_form_source_snapshot_v1 = { form: { id: id(3), titulo: 'Form', ativo: true, imagem_capa_url: 'private' }, content, source_snapshot: metadata, version: 2, family_id: id(9), actor: 'private' };
  const result = await data.getFormTemplate(id(1)), published = await data.getPublishedFormTemplate(id(3));
  assert.ok(result && published); assert.equal(result.draft.updated_at, version); assert.equal(result.draft.source_snapshot.has_cover, true);
  assert.deepEqual(result.draft.source_snapshot.celulas_ids, [id(2)]); assert.deepEqual(result.publication?.id_mapping.questions, { [id(4)]: id(5) });
  assert.ok(!/private|secret|imagem_capa_url|created_by|auth_user_id/.test(JSON.stringify({ result, published })));
  assert.equal(db.rpcCalls.length, 2); assert.deepEqual(db.calls, []);
  assert.equal(await data.getFormTemplate('bad'), null); assert.equal(await data.getPublishedFormTemplate('bad'), null); assert.equal(db.rpcCalls.length, 2);
});

test('choices select only the five enum catalogs and return the agreed display shape', async () => {
  const { db, data } = setup(); db.tables.rm_option_sets = [{ option_set_key: 'tipo_quest_o', option_key: 'texto_curto', bubble_display: 'Texto curto', sort_order: 1, private: 'secret' }];
  const result = await data.getFormTemplateChoices();
  assert.deepEqual(result.questionTypes, [{ id: 'texto_curto', option_key: 'texto_curto', bubble_display: 'Texto curto', sort_order: 1 }]);
  assert.deepEqual(result.dimensions, []); assert.deepEqual(result.formTypes, []); assert.deepEqual(result.profiles, []); assert.deepEqual(result.subtypes, []);
  assert.ok(!JSON.stringify(result).includes('secret'));
});
