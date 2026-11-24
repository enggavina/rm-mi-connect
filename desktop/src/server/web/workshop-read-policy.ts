import type { CorporateCapability } from './sso-policy';
import { uuid } from './policy';
export const WORKSHOP_READ_RESOURCES = [
  'catalog_list', 'catalog_entry', 'template_list', 'template_draft', 'template_form', 'template_choices',
  'project_list', 'project_entry', 'planning_list', 'gantt_snapshot', 'gantt_projects', 'gantt_cells',
] as const;
export type WorkshopReadResource = typeof WORKSHOP_READ_RESOURCES[number];
export type WorkshopRead = (resource: WorkshopReadResource, args: Record<string, unknown>) => Promise<any>;
export function workshopReadCapabilities(resource: WorkshopReadResource, filters: Record<string, unknown> = {}): readonly CorporateCapability[] {
  switch (resource) {
    case 'catalog_list': return ['em.portal.read', 'em.catalogs.read'];
    case 'catalog_entry': return ['em.portal.read', 'em.catalogs.read', 'em.catalogs.manage'];
    case 'template_list': case 'template_draft': case 'template_form': case 'template_choices': return ['em.portal.read', 'em.form_templates.read'];
    case 'project_list': return filters.planning === true || filters.cell != null
      ? ['em.portal.read', 'em.projects.read', 'em.planning.read'] : ['em.portal.read', 'em.projects.read'];
    case 'project_entry': return filters.documents === true
      ? ['em.portal.read', 'em.projects.read', 'em.documents.read'] : ['em.portal.read', 'em.projects.read'];
    case 'planning_list': return filters.project_details === true
      ? ['em.portal.read', 'em.planning.read', 'em.projects.read'] : ['em.portal.read', 'em.planning.read'];
    case 'gantt_snapshot': {
      const capabilities: CorporateCapability[] = ['em.portal.read', 'em.planning.read'];
      if (filters.project_id != null || filters.project_details === true || filters.can_manage === true) capabilities.push('em.projects.read');
      if (filters.can_manage === true) capabilities.push('em.planning.manage');
      return capabilities;
    }
    case 'gantt_projects': return ['em.portal.read', 'em.planning.read', 'em.projects.read'];
    case 'gantt_cells': return ['em.portal.read', 'em.planning.read'];
    default: throw new Error('Consulta indisponível.');
  }
}
export function checkedWorkshopPage(value: any, page: number, pageSize: number, templates = false): any {
  const arrays = templates ? ['drafts', 'published'] : ['rows'], counts = templates ? ['draftTotal', 'publishedTotal'] : ['total'];
  if (!value || value.page !== page || value.pageSize !== pageSize
    || arrays.some(key => !Array.isArray(value[key]) || value[key].length > pageSize
      || value[key].some((row: any) => !row || !uuid.safeParse(row.id).success) || new Set(value[key].map((row: any) => row.id)).size !== value[key].length)
    || counts.some((key, i) => !Number.isSafeInteger(value[key]) || value[key] < 0 || value[key] < value[arrays[i]].length)) throw new Error('A consulta retornada não pôde ser validada.');
  return value;
}
export function workshopReadResult(value: any, expected: { requestId: string; resource: WorkshopReadResource; workshopId: string }): unknown {
  if (!value || value.request_id !== expected.requestId || value.resource !== expected.resource || value.workshop_id !== expected.workshopId || !Object.hasOwn(value, 'data')) throw new Error('A consulta retornada não pôde ser validada.');
  return value.data;
}
