import test from 'node:test';
import assert from 'node:assert/strict';
import { dossierSearchActive, dossierSearchHref, readDossierSearchQuery } from '../src/components/web/project-dossier-search-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const comments = { search: 'inspeção 100%_ (motor)', author_id: id(2), cell_id: id(3), from_date: '2026-10-29', to_date: '2026-10-30', page: 3 };
const documents = { search: 'Laudo & placa', author_id: id(2), source: 'docs' as const, status: 'No prazo' as const, from_date: '2026-10-01', to_date: '2026-10-30', page: 2 };

test('comment and document queries have independent pages and retain literal search text and calendar dates', () => {
  const query = { comment_q: `  ${comments.search}  `, comment_author: id(2), comment_cell: id(3), comment_from: comments.from_date, comment_to: comments.to_date, comment_page: '3',
    doc_q: documents.search, doc_author: id(2), doc_source: 'docs', doc_status: 'No prazo', doc_from: documents.from_date, doc_to: documents.to_date, document_page: '2', page: '9' };
  assert.deepEqual(readDossierSearchQuery('comments', query), { filters: comments, errors: [] });
  assert.deepEqual(readDossierSearchQuery('documents', query), { filters: documents, errors: [] });
  assert.equal(readDossierSearchQuery('comments', { page: '99' }).filters.page, 1, 'The gallery page never selects a comment page.');
  assert.equal(readDossierSearchQuery('documents', { comment_page: '99' }).filters.page, 1);
});

test('invalid and repeated filters remain explicit errors instead of silently querying another selection', () => {
  for (const query of [{ comment_author: 'not-an-identity' }, { comment_cell: 'invalid' }, { comment_from: '2026-02-29' }, { comment_to: '0000-01-01' },
    { comment_from: '2026-11-01', comment_to: '2026-10-30' }, { comment_page: '1e2' }, { comment_page: '-1' }, { comment_page: '100001' },
    { comment_page: ['1', '2'] }, { comment_q: ['primeira', 'segunda'] }, { comment_q: 'x'.repeat(201) }]) {
    assert.ok(readDossierSearchQuery('comments', query).errors.length > 0, JSON.stringify(query));
  }
  for (const query of [{ doc_status: 'ativo' }, { doc_source: 'external' }, { doc_author: ['a', 'b'] }, { doc_from: '30/10/2026' }, { document_page: '1.5' }]) {
    assert.ok(readDossierSearchQuery('documents', query).errors.length > 0, JSON.stringify(query));
  }
  const invalid = readDossierSearchQuery('comments', { comment_q: 'texto preservado', comment_from: '2026-02-29' });
  assert.equal(invalid.filters.search, 'texto preservado'); assert.equal(invalid.filters.from_date, '2026-02-29');
});

test('native pagination keeps the project, active tab and every active filter without mixing gallery or other dossier pages', () => {
  const href = dossierSearchHref(id(1), 'comments', comments, 4), url = new URL(href, 'https://em.example.invalid');
  assert.equal(url.pathname, `/projetos/${id(1)}`); assert.equal(url.searchParams.get('tab'), 'historico');
  assert.equal(url.searchParams.get('comment_q'), comments.search); assert.equal(url.searchParams.get('comment_author'), comments.author_id);
  assert.equal(url.searchParams.get('comment_cell'), comments.cell_id); assert.equal(url.searchParams.get('comment_from'), comments.from_date);
  assert.equal(url.searchParams.get('comment_to'), comments.to_date); assert.equal(url.searchParams.get('comment_page'), '4');
  for (const key of ['page', 'document_page', 'doc_q', 'doc_author']) assert.equal(url.searchParams.has(key), false);
  const doc = new URL(dossierSearchHref(id(1), 'documents', documents, 5), url.origin);
  assert.equal(doc.searchParams.get('tab'), 'documentos'); assert.equal(doc.searchParams.get('document_page'), '5');
  assert.equal(doc.searchParams.get('doc_q'), documents.search); assert.equal(doc.searchParams.get('doc_source'), 'docs');
  assert.equal(doc.searchParams.get('doc_status'), 'No prazo'); assert.equal(doc.searchParams.get('doc_author'), documents.author_id);
  assert.equal(doc.searchParams.get('doc_from'), documents.from_date); assert.equal(doc.searchParams.get('doc_to'), documents.to_date);
});

test('clearing filters keeps the authorized project tab and a page alone does not imply filtered absence', () => {
  const cleanComments = { search: '', author_id: null, cell_id: null, from_date: null, to_date: null, page: 4 };
  const cleanDocuments = { search: '', author_id: null, source: 'all' as const, status: 'all' as const, from_date: null, to_date: null, page: 2 };
  assert.equal(dossierSearchHref(id(1), 'comments', cleanComments), `/projetos/${id(1)}?tab=historico`);
  assert.equal(dossierSearchHref(id(1), 'documents', cleanDocuments), `/projetos/${id(1)}?tab=documentos`);
  assert.equal(dossierSearchActive(cleanComments), false); assert.equal(dossierSearchActive(cleanDocuments), false);
  assert.equal(dossierSearchActive({ ...cleanComments, cell_id: id(3) }), true);
  assert.equal(dossierSearchActive({ ...cleanDocuments, status: 'other' }), true);
});
