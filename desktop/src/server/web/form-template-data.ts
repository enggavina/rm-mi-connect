import type { SupabaseClient } from '@supabase/supabase-js';
import type { WebRow } from './data';
import { pageNumber, searchTerm, uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import { formTemplateSnapshotDto, publishedFormSnapshotDto } from './form-template-dto';

export type FormTemplateFilters = { q?: string; state?: string; page?: number | string };
const DRAFT_LIST = 'id,kind,state,family_id,source_form_id,source_version,created_at,updated_at,published_form_id,titulo:content->>titulo';
const FORM_LIST = 'id,titulo,title,descricao,tipo,ativo,updated_at,version_info:rm_form_template_versions(version,family_id,legacy)';
const OPTION_SETS = { questionTypes: 'tipo_quest_o', dimensions: 'dimensoes', subtypes: 'subtipos', formTypes: 'tipo_formulario', profiles: 'tipo_de_usu_rio' } as const;
export interface FormTemplateChoice { id: string; option_key: string; bubble_display: string; sort_order: number | null }
function checked(result: any) {
  if (result.error) throw new Error('Não foi possível consultar os modelos de formulário. Tente novamente.');
  return result;
}

export function createFormTemplateData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  function authorize() {
    if (capabilities !== undefined && (!capabilities.includes('em.portal.read') || !capabilities.includes('em.form_templates.read'))) throw new Error('Acesso não autorizado aos modelos de formulário.');
  }
  async function listFormTemplates(filters: FormTemplateFilters = {}) {
    authorize();
    const page = pageNumber(filters.page), pageSize = 25, start = (page - 1) * pageSize;
    let drafts: any = client.from('rm_form_template_drafts').select(DRAFT_LIST, { count: 'exact' });
    let published: any = client.from('rm_forms').select(FORM_LIST, { count: 'exact' });
    const term = searchTerm(filters.q);
    if (term) { drafts = drafts.ilike('content->>titulo', `%${term}%`); published = published.or(`titulo.ilike.%${term}%,title.ilike.%${term}%`); }
    if (filters.state === 'draft' || filters.state === 'published') drafts = drafts.eq('state', filters.state);
    const [draftResult, formResult] = await Promise.all([
      drafts.order('updated_at', { ascending: false }).order('id').range(start, start + pageSize - 1),
      published.order('titulo').order('id').range(start, start + pageSize - 1),
    ]);
    const rows: WebRow[] = (checked(formResult).data || []).map((raw: WebRow) => {
      const { version_info, ...form } = raw;
      const info = Array.isArray(version_info) ? version_info[0] : version_info;
      return { ...form, version: info?.version ?? 1, family_id: info?.family_id ?? null, legacy: info?.legacy ?? true } as WebRow;
    });
    return { drafts: (checked(draftResult).data || []) as WebRow[], published: rows,
      draftTotal: draftResult.count ?? 0, publishedTotal: formResult.count ?? 0, page, pageSize };
  }
  async function getFormTemplate(id: string) {
    authorize();
    if (!uuid.safeParse(id).success) return null;
    return formTemplateSnapshotDto(checked(await client.rpc('rm_web_form_template_snapshot_v1', { p_id: id })).data);
  }
  async function getPublishedFormTemplate(formId: string) {
    authorize();
    if (!uuid.safeParse(formId).success) return null;
    return publishedFormSnapshotDto(checked(await client.rpc('rm_web_form_source_snapshot_v1', { p_id: formId })).data);
  }
  async function getFormTemplateChoices() {
    authorize();
    const result = checked(await client.from('rm_option_sets').select('option_set_key,option_key,bubble_display,sort_order')
      .in('option_set_key', Object.values(OPTION_SETS)).order('sort_order'));
    const all = (result.data || []) as Record<string, any>[];
    const options = (set: string): FormTemplateChoice[] => all.filter(row => row.option_set_key === set)
      .map(row => ({ id: row.option_key, option_key: row.option_key, bubble_display: row.bubble_display, sort_order: row.sort_order }));
    return { questionTypes: options(OPTION_SETS.questionTypes), dimensions: options(OPTION_SETS.dimensions),
      subtypes: options(OPTION_SETS.subtypes), formTypes: options(OPTION_SETS.formTypes), profiles: options(OPTION_SETS.profiles) };
  }
  return { listFormTemplates, getFormTemplate, getPublishedFormTemplate, getFormTemplateChoices };
}
async function data() {
  const { requireWebUser } = await import('./auth');
  const session = await requireWebUser('em.form_templates.read');
  return createFormTemplateData(session.client, session.sso?.capabilities);
}
export async function listFormTemplates(filters: FormTemplateFilters = {}) { return (await data()).listFormTemplates(filters); }
export async function getFormTemplate(id: string) { return (await data()).getFormTemplate(id); }
export async function getPublishedFormTemplate(formId: string) { return (await data()).getPublishedFormTemplate(formId); }
export async function getFormTemplateChoices() { return (await data()).getFormTemplateChoices(); }
