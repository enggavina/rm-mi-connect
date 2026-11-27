import type { CorporateCapability } from './sso-policy';
import { uuid } from './policy';
export const WORKSHOP_READ_RESOURCES = [
  'catalog_list', 'catalog_entry', 'template_list', 'template_draft', 'template_form', 'template_choices',
  'project_list', 'project_entry', 'planning_list', 'gantt_snapshot', 'gantt_projects', 'gantt_cells', 'operation_validation', 'receiving_list',
  'project_qr', 'document_link', 'form_record_project', 'form_record_list', 'workshop_twin', 'planning_export', 'media_reference', 'overview',
  'approval_list', 'approval_entry', 'approval_choices', 'approval_allocation', 'capacity_snapshot', 'cell_availability',
  'cell_queue', 'planning_load', 'execution_snapshot',
  'engineering_matrix', 'engineering_entry', 'engineering_choices', 'photo_title_list', 'photo_title_entry', 'workshop_team',
] as const;
export type WorkshopReadResource = typeof WORKSHOP_READ_RESOURCES[number];
export type WorkshopRead = (resource: WorkshopReadResource, args: Record<string, unknown>) => Promise<any>;
export function workshopReadCapabilities(resource: WorkshopReadResource, filters: Record<string, unknown> = {}): readonly CorporateCapability[] {
  switch (resource) {
    case 'catalog_list': case 'workshop_team': return ['em.portal.read', 'em.catalogs.read'];
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
    case 'gantt_projects': case 'cell_availability': case 'execution_snapshot': return ['em.portal.read', 'em.planning.read', 'em.projects.read'];
    case 'capacity_snapshot': return filters.can_manage === true
      ? ['em.portal.read', 'em.planning.read', 'em.projects.read', 'em.planning.manage'] : ['em.portal.read', 'em.planning.read', 'em.projects.read'];
    case 'gantt_cells': case 'cell_queue': case 'planning_load': return ['em.portal.read', 'em.planning.read'];
    case 'engineering_matrix': case 'engineering_entry': case 'engineering_choices': case 'photo_title_list': case 'photo_title_entry':
      return ['em.portal.read', 'em.engineering.read'];
    case 'receiving_list': case 'project_qr': return ['em.portal.read', 'em.projects.read'];
    case 'document_link': return ['em.portal.read', 'em.documents.read'];
    case 'media_reference': return ['em.portal.read', 'em.photos.read', filters.source === 'project_photo' ? 'em.projects.read' : 'em.forms.read'];
    case 'approval_entry': case 'approval_choices': return ['em.portal.read', 'em.approvals.read'];
    case 'approval_list': return filters.mine === true ? ['em.portal.read', 'em.approvals.read', 'em.approvals.decide'] : ['em.portal.read', 'em.approvals.read'];
    case 'approval_allocation': return ['em.portal.read', 'em.approvals.read', 'em.projects.read', 'em.planning.read'];
    case 'overview': {
      const capabilities: CorporateCapability[] = ['em.portal.read'];
      if (filters.projects === true) capabilities.push('em.projects.read');
      if (filters.forms === true) capabilities.push('em.forms.read');
      if (filters.planning === true) capabilities.push('em.planning.read');
      if (filters.documents === true) capabilities.push('em.documents.read');
      return capabilities;
    }
    case 'form_record_project': return ['em.portal.read', 'em.forms.read'];
    case 'form_record_list': return filters.project_details === true
      ? ['em.portal.read', 'em.forms.read', 'em.projects.read'] : ['em.portal.read', 'em.forms.read'];
    case 'operation_validation': case 'workshop_twin': case 'planning_export':
      return ['em.portal.read', 'em.projects.read', 'em.planning.read'];
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
