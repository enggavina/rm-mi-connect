import type { CorporateCapability } from './sso-policy';
import { uuid } from './policy';
export const WORKSHOP_READ_RESOURCES = ['catalog_list', 'catalog_entry', 'template_list', 'template_draft', 'template_form', 'template_choices'] as const;
export type WorkshopReadResource = typeof WORKSHOP_READ_RESOURCES[number];
export type WorkshopRead = (resource: WorkshopReadResource, args: Record<string, unknown>) => Promise<any>;
export function workshopReadCapabilities(resource: WorkshopReadResource): readonly CorporateCapability[] {
  switch (resource) {
    case 'catalog_list': return ['em.portal.read', 'em.catalogs.read'];
    case 'catalog_entry': return ['em.portal.read', 'em.catalogs.read', 'em.catalogs.manage'];
    case 'template_list': case 'template_draft': case 'template_form': case 'template_choices': return ['em.portal.read', 'em.form_templates.read'];
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
