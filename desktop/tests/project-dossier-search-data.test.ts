import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createProjectDossierSearchData, DossierSearchInputError } from '../src/server/web/project-dossier-search-data';
import { projectCommentFiltersSchema, projectDocumentFiltersSchema, type ProjectCommentPage, type ProjectDocumentPage } from '../src/server/web/project-dossier-search-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.history.read', 'em.documents.read'];
const time = '2026-10-30T14:00:01.123456+00:00';
const comment = { id: id(2), projeto_id: id(1), celula_id: id(3), cadastrado_por_id: id(4), evento: 'Texto literal %_*', created_at: time,
  author_name: 'Autora', author_registration: '42', cell_name: 'Célula histórica' };
function comments(): ProjectCommentPage {
  const { page: _page, ...filters } = projectCommentFiltersSchema.parse({});
  return { project_id: id(1), items: [comment], total: 1, unfiltered_total: 1, page: 1, page_size: 25, filters,
    facets: { authors: [{ id: id(4), nome: 'Autora', matricula: '42' }], cells: [{ id: id(3), nome: 'Célula histórica' }] } };
}
function documents(): ProjectDocumentPage {
  const { page: _page, ...filters } = projectDocumentFiltersSchema.parse({});
  return { project_id: id(1), items: ['documents', 'docs'].map(source => ({ id: id(2), source: source as 'documents' | 'docs', projeto_id: id(1),
    nome: 'Documento', descricao: null, tipo_arquivo: null, tipo_documento: null, status: null, data_vencimento: null, created_by: null,
    author_name: null, author_registration: null, created_at: time, has_file: true, visivel_cliente: null })), total: 2, unfiltered_total: 2,
    page: 1, page_size: 25, filters, facets: { authors: [], statuses: [{ value: 'other', label: 'Outras situações' }] } };
}
function fixture(result: unknown, capabilities: CorporateCapability[] = caps, error?: unknown) {
  const calls: unknown[][] = [];
  const client = { rpc: async (...args: unknown[]) => { calls.push(args); if (error instanceof Error) throw error; return { data: result, error: error || null }; },
    from: () => { throw new Error('Unbounded table query must never run'); } } as unknown as SupabaseClient;
  return { ...createProjectDossierSearchData(client, capabilities), calls };
}

test('dossier query schemas preserve literal search and normalize only absent optional filters', () => {
  assert.deepEqual(projectCommentFiltersSchema.parse({ search: '  motor %_*\'  ', page: '2' }), { search: 'motor %_*\'', author_id: null,
    cell_id: null, from_date: null, to_date: null, page: 2 });
  assert.equal(projectDocumentFiltersSchema.parse({ source: 'docs', status: 'No prazo', author_id: id(4), from_date: '2024-02-29', to_date: '2026-10-30' }).page, 1);
  for (const patch of [{ from_date: '2026-02-29' }, { to_date: '0000-01-01' }, { from_date: '2026-11-01', to_date: '2026-10-30' },
    { from_date: '2026-10-30T00:00:00Z' }, { page: 0 }, { page: 'abc' }, { page: '01' }, { page: 100001 }, { author_id: 'operator-name' },
    { cell_id: [id(3)] }, { actor_id: id(4) }, { search: 'a'.repeat(201) }, { search: 'bad\u0000text' }]) assert.equal(projectCommentFiltersSchema.safeParse(patch).success, false);
  for (const patch of [{ source: 'private' }, { status: 'aprovado' }, { arquivo_url: 'https://private.invalid' }]) assert.equal(projectDocumentFiltersSchema.safeParse(patch).success, false);
});

test('project/history and project/documents scopes independently guard every request before RPC', async () => {
  for (const capability of ['em.portal.read', 'em.projects.read', 'em.history.read'] as const) {
    const f = fixture(comments(), caps.filter(value => value !== capability));
    await assert.rejects(f.getProjectComments(id(1)), /Acesso/); assert.deepEqual(f.calls, []);
  }
  for (const capability of ['em.portal.read', 'em.projects.read', 'em.documents.read'] as const) {
    const f = fixture(documents(), caps.filter(value => value !== capability));
    await assert.rejects(f.getProjectDocuments(id(1)), /Acesso/); assert.deepEqual(f.calls, []);
  }
  assert.equal((await fixture(comments(), caps.filter(value => value !== 'em.documents.read')).getProjectComments(id(1)))?.total, 1);
  assert.equal((await fixture(documents(), caps.filter(value => value !== 'em.history.read')).getProjectDocuments(id(1)))?.total, 2);
});

test('invalid project IDs and filters never query SQL and absence differs from an unavailable query', async () => {
  const f = fixture(null); assert.equal(await f.getProjectComments('invalid'), null); assert.deepEqual(f.calls, []);
  await assert.rejects(f.getProjectComments(id(1), { from_date: 'bad' }), DossierSearchInputError); assert.deepEqual(f.calls, []);
  assert.equal(await f.getProjectDocuments(id(1)), null);
  for (const error of [new Error('secret backend detail'), { code: 'XX000', message: 'secret backend detail' }]) {
    await assert.rejects(fixture(null, caps, error).getProjectComments(id(1)), { message: 'Não foi possível consultar este histórico. Tente novamente.' });
  }
  await assert.rejects(fixture(undefined).getProjectDocuments(id(1)), /Não foi possível/);
});

test('one scoped RPC returns exact filters, bounded rows and project-specific historical facets', async () => {
  const value = comments(), input = { search: 'motor %_*', author_id: id(4), cell_id: id(3), from_date: '2026-10-30', to_date: '2026-10-30', page: 1000 };
  const { page: _page, ...filters } = input; value.filters = filters;
  const f = fixture(value); assert.deepEqual(await f.getProjectComments(id(1), input), value);
  assert.deepEqual(f.calls, [['rm_web_project_comments_v1', { p_project_id: id(1), p_filters: input }]]);
  const empty = { ...comments(), items: [], total: 0, unfiltered_total: 30, filters: { ...comments().filters, search: 'missing' } };
  assert.equal((await fixture(empty).getProjectComments(id(1), { search: 'missing' }))?.unfiltered_total, 30);
});

test('unified document pagination preserves colliding IDs from separate source tables without exposing file URLs', async () => {
  const value = documents(), f = fixture(value); assert.deepEqual(await f.getProjectDocuments(id(1)), value);
  assert.deepEqual(f.calls, [['rm_web_project_documents_v1', { p_project_id: id(1), p_filters: projectDocumentFiltersSchema.parse({}) }]]);
  assert.ok(value.items.every(item => !('arquivo_url' in item) && !('s3_key' in item)));
});

test('UUID case is canonicalized before SQL and response comparisons without changing literal searches', async () => {
  const projectId = 'af000000-0000-4000-8000-000000000001', authorId = 'bc000000-0000-4000-8000-000000000002';
  const value = comments(); value.project_id = projectId; value.items[0] = { ...value.items[0], projeto_id: projectId, cadastrado_por_id: authorId };
  value.filters.author_id = authorId; value.facets.authors = [{ id: authorId, nome: 'Autora', matricula: null }];
  const f = fixture(value); assert.equal((await f.getProjectComments(projectId.toUpperCase(), { author_id: authorId.toUpperCase() }))?.project_id, projectId);
  assert.equal((f.calls[0][1] as any).p_project_id, projectId); assert.equal((f.calls[0][1] as any).p_filters.author_id, authorId);
  assert.equal(projectCommentFiltersSchema.safeParse({ search: 'x' + String.fromCharCode(0) }).success, false);
  assert.equal(projectCommentFiltersSchema.safeParse({ search: 'x' + String.fromCharCode(92) + 'u0000' }).success, true);
});

test('cross-project, inconsistent count/filter/page and duplicate metadata responses fail closed', async () => {
  for (const patch of [{ project_id: id(99) }, { total: 2 }, { unfiltered_total: 0 }, { page: 2 }, { page_size: 50 },
    { filters: { ...comments().filters, search: 'another query' } }, { items: [{ ...comment, projeto_id: id(99) }] },
    { items: [comment, comment], total: 2, unfiltered_total: 2 }, { facets: { authors: [], cells: [{ id: id(3), nome: null }, { id: id(3), nome: null }] } },
    { private_envelope: 'must never leak' }, { items: [{ ...comment, auth_user_id: id(90) }] }]) {
    await assert.rejects(fixture({ ...comments(), ...patch }).getProjectComments(id(1)), /Não foi possível/);
  }
  for (const patch of [{ items: [documents().items[0], documents().items[0]] },
    { items: documents().items.map(item => ({ ...item, arquivo_url: 'https://private.invalid/object' })) },
    { facets: { authors: [{ id: id(4), nome: null, matricula: null }, { id: id(4), nome: null, matricula: null }], statuses: [] } }]) {
    await assert.rejects(fixture({ ...documents(), ...patch }).getProjectDocuments(id(1)), /Não foi possível/);
  }
});
