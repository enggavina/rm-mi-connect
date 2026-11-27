import type { SupabaseClient } from '@supabase/supabase-js';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import type { WorkshopRead } from './workshop-read-policy';
import { readProjectDetail, readWorkshopOperations } from './workshop-operation-reader';
import { projectCommentFiltersSchema, projectDocumentFiltersSchema, projectCommentPageSchema, projectDocumentPageSchema,
  type ProjectCommentPage, type ProjectDocumentPage } from './project-dossier-search-policy';

export type { ProjectCommentPage, ProjectDocumentPage, ProjectCommentFilters, ProjectDocumentFilters } from './project-dossier-search-policy';
const base: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
const unavailable = () => new Error('Não foi possível consultar este histórico. Tente novamente.');
export class DossierSearchInputError extends Error { constructor() { super('Confira os filtros e o período informado.'); } }
function unique(values: string[]) { return new Set(values).size === values.length; }
function directoryConsistent(page: ProjectDocumentPage, requested: { folder_id?: string | null }) {
  if (!Object.prototype.hasOwnProperty.call(requested, 'folder_id')) return true;
  const navigation = page.navigation;
  if (!navigation || navigation.current_folder_id !== requested.folder_id || !unique(navigation.folders.map(folder => folder.id))) return false;
  const folders = new Map(navigation.folders.map(folder => [folder.id, folder]));
  const visited = new Set<string>();
  for (const folder of navigation.folders) {
    let current: typeof folder | undefined = folder; const seen = new Set<string>();
    while (current && !visited.has(current.id)) {
      if (seen.has(current.id)) return false; seen.add(current.id);
      if (current.parent_id && !folders.has(current.parent_id)) return false;
      current = current.parent_id ? folders.get(current.parent_id) : undefined;
    }
    for (const id of seen) visited.add(id);
  }
  const path: typeof navigation.breadcrumbs = []; let current = requested.folder_id ? folders.get(requested.folder_id) : undefined;
  if (requested.folder_id && !current) return false;
  while (current) { path.push(current); current = current.parent_id ? folders.get(current.parent_id) : undefined; }
  path.reverse();
  return path.length === navigation.breadcrumbs.length && path.every((folder, index) => Object.entries(folder).every(([key, value]) => navigation.breadcrumbs[index][key as keyof typeof folder] === value));
}
function consistent(page: ProjectCommentPage | ProjectDocumentPage, projectId: string, requested: { page: number; [key: string]: unknown }) {
  const { page: requestedPage, ...filters } = requested;
  return page.project_id === projectId && page.total <= page.unfiltered_total
    && page.page === Math.min(requestedPage, Math.max(1, Math.ceil(page.total / 25)))
    && page.items.length === Math.min(25, Math.max(0, page.total - (page.page - 1) * 25))
    && Object.keys(filters).every(key => (page.filters as Record<string, unknown>)[key] === filters[key])
    && page.items.every(item => item.projeto_id === projectId)
    && unique(page.facets.authors.map(author => author.id));
}
export function createProjectDossierSearchData(client: SupabaseClient, capabilities?: readonly CorporateCapability[], workshopRead?: WorkshopRead) {
  function allow(capability: CorporateCapability) {
    if (capabilities !== undefined && ![...base, capability].every(value => capabilities.includes(value))) throw new Error('Acesso não autorizado à consulta do dossiê.');
  }
  async function read(resource: 'project_comments' | 'project_documents', rpc: string, projectId: string, filters: Record<string, unknown>) {
    try {
      const result = await readProjectDetail(client, workshopRead, resource, rpc, { p_project_id: projectId, p_filters: filters });
      if (result.error) throw unavailable();
      return result.data;
    } catch { throw unavailable(); }
  }
  async function getProjectComments(projectId: string, filters: unknown = {}): Promise<ProjectCommentPage | null> {
    allow('em.history.read'); if (!uuid.safeParse(projectId).success) return null;
    projectId = projectId.toLowerCase();
    const input = projectCommentFiltersSchema.safeParse(filters); if (!input.success) throw new DossierSearchInputError();
    const data = await read('project_comments', 'rm_web_project_comments_v1', projectId, input.data); if (data === null) return null;
    const parsed = projectCommentPageSchema.safeParse(data);
    if (!parsed.success || !consistent(parsed.data, projectId, input.data) || !unique(parsed.data.items.map(item => item.id))
      || !unique(parsed.data.facets.cells.map(cell => cell.id))) throw unavailable();
    return parsed.data;
  }
  async function getProjectDocuments(projectId: string, filters: unknown = {}): Promise<ProjectDocumentPage | null> {
    allow('em.documents.read'); if (!uuid.safeParse(projectId).success) return null;
    projectId = projectId.toLowerCase();
    const input = projectDocumentFiltersSchema.safeParse(filters); if (!input.success) throw new DossierSearchInputError();
    const data = await read('project_documents', 'rm_web_project_documents_v1', projectId, input.data); if (data === null) return null;
    const parsed = projectDocumentPageSchema.safeParse(data);
    if (!parsed.success || !consistent(parsed.data, projectId, input.data) || !directoryConsistent(parsed.data, input.data)
      || !unique(parsed.data.items.map(item => `${item.source}:${item.id}`)) || !unique(parsed.data.facets.statuses.map(status => status.value))) throw unavailable();
    return parsed.data;
  }
  return { getProjectComments, getProjectDocuments };
}
export async function getProjectComments(projectId: string, filters: unknown = {}) {
  const { requireWebUser } = await import('./auth'); const access = await requireWebUser([...base, 'em.history.read']);
  return createProjectDossierSearchData(access.client, access.sso?.capabilities, await readWorkshopOperations(access)).getProjectComments(projectId, filters);
}
export async function getProjectDocuments(projectId: string, filters: unknown = {}) {
  const { requireWebUser } = await import('./auth'); const access = await requireWebUser([...base, 'em.documents.read']);
  return createProjectDossierSearchData(access.client, access.sso?.capabilities, await readWorkshopOperations(access)).getProjectDocuments(projectId, filters);
}
