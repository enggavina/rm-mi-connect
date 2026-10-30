import { projectCommentFiltersSchema, projectDocumentFiltersSchema, type ProjectCommentFilters, type ProjectDocumentFilters } from '@/server/web/project-dossier-search-policy';

export type DossierSearchKind = 'comments' | 'documents';
export type DossierSearchQuery = Record<string, string | string[] | undefined>;
const names = {
  comments: { search: 'comment_q', author_id: 'comment_author', cell_id: 'comment_cell', from_date: 'comment_from', to_date: 'comment_to', page: 'comment_page' },
  documents: { search: 'doc_q', author_id: 'doc_author', source: 'doc_source', status: 'doc_status', from_date: 'doc_from', to_date: 'doc_to', page: 'document_page' },
} as const;
export const dossierSearchNames = <Kind extends DossierSearchKind>(kind: Kind) => names[kind];

export function readDossierSearchQuery(kind: 'comments', query: DossierSearchQuery): { filters: ProjectCommentFilters; errors: string[] };
export function readDossierSearchQuery(kind: 'documents', query: DossierSearchQuery): { filters: ProjectDocumentFilters; errors: string[] };
export function readDossierSearchQuery(kind: DossierSearchKind, query: DossierSearchQuery) {
  const fields = names[kind], errors: string[] = [];
  const read = (name: string) => { const value = query[name]; if (Array.isArray(value)) { errors.push('Há filtros repetidos no endereço. Confira os campos ou limpe os filtros.'); return value[0] ?? ''; } return value ?? ''; };
  const optional = (name: string) => read(name).trim() || null;
  const pageText = read(fields.page), page = pageText ? Number(pageText) : 1;
  if (pageText && !/^[1-9]\d*$/.test(pageText)) errors.push('Informe uma página válida.');
  const input = { search: read(fields.search).trim(), author_id: optional(fields.author_id), from_date: optional(fields.from_date), to_date: optional(fields.to_date), page,
    ...(kind === 'comments' ? { cell_id: optional(names.comments.cell_id) } : { source: read(names.documents.source) || 'all', status: read(names.documents.status) || 'all' }) };
  const schema = kind === 'comments' ? projectCommentFiltersSchema : projectDocumentFiltersSchema, parsed = schema.safeParse(input);
  if (!parsed.success) errors.push('Confira os filtros: busca de até 200 caracteres, autor/célula válidos e período com datas válidas em ordem.');
  // Invalid values remain visible for correction, but the page never queries with them.
  return { filters: parsed.success ? parsed.data : input, errors: [...new Set(errors)] };
}

export function dossierSearchHref(projectId: string, kind: DossierSearchKind, filters: Omit<ProjectCommentFilters, 'page'> | Omit<ProjectDocumentFilters, 'page'>, page = 1) {
  const fields = names[kind], params = new URLSearchParams({ tab: kind === 'comments' ? 'historico' : 'documentos' });
  for (const [key, name] of Object.entries(fields)) {
    if (key === 'page') continue;
    const value = (filters as Record<string, unknown>)[key];
    if (typeof value === 'string' && value && value !== 'all') params.set(name, value);
  }
  if (page > 1) params.set(fields.page, String(page));
  return `/projetos/${projectId}?${params.toString()}`;
}

export function dossierSearchActive(filters: Omit<ProjectCommentFilters, 'page'> | Omit<ProjectDocumentFilters, 'page'>) {
  return Object.entries(filters).some(([key, value]) => key !== 'page' && value !== null && value !== '' && value !== 'all' && value !== undefined);
}
