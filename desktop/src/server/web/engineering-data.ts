import type { SupabaseClient } from '@supabase/supabase-js';
import type { WebRow } from './data';
import { pageNumber, searchTerm, uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import { withFormVersionLabels } from './form-version-labels';

const MATRIX = 'id,celula_id,tipo_equipamento_id,ativo,visibilidade,numero_fotos,updated_at';
const CELL = 'id,nome,codigo,indice,ordem';
const TYPE = 'id,nome,sigla';
const TITLE = 'id,titulo,numero,celula_nome,updated_at';
const PHOTO = 'id,cadastro_foto_id,titulo,numero,descricao,identificador_foto_key,categoria_foto';
const STAGE = 'id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov,aprovador_id,aprovadores_ids,aprovadores_retorno_ids';
export type EngineeringSnapshot = { matrix: WebRow; form_ids: string[]; photos: WebRow[]; stages: WebRow[] };
export type PhotoTitleFilters = { q?: string; page?: number | string; cell?: string };
export type PhotoTitleRow = WebRow & { celula_id?: string | null; scope_resolved: boolean; scope_ambiguous: boolean };

function checked(result: any) {
  if (result.error) throw new Error('Não foi possível consultar a configuração de engenharia. Tente novamente.');
  return result;
}
function selectedIds(values: unknown[]): string[] { return [...new Set(values.filter((value): value is string => uuid.safeParse(value).success))]; }
function pick(row: Record<string, unknown>, columns: string): WebRow {
  return Object.fromEntries(columns.split(',').map(key => [key, row[key]])) as WebRow;
}
/** Same name equivalence as SQL; ambiguous/unknown legacy names are not global. */
export function photoTitleScope(row: WebRow, cells: WebRow[]): PhotoTitleRow {
  const key = (value: unknown) => typeof value === 'string' ? value.trim().replace(/\s+/g, ' ').toLowerCase() : null;
  if (row.celula_nome === null || key(row.celula_nome) === '') return { ...row, celula_id: null, scope_resolved: true, scope_ambiguous: false };
  const matches = cells.filter(cell => key(cell.nome) === key(row.celula_nome));
  return { ...row, ...(matches.length === 1 ? { celula_id: matches[0].id } : {}), scope_resolved: matches.length === 1, scope_ambiguous: matches.length > 1 };
}

/** Injectable anon+RLS client. Templates only; no URLs, emails or Auth metadata. */
export function createEngineeringData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  function authorize() {
    if (capabilities !== undefined && (!capabilities.includes('em.portal.read') || !capabilities.includes('em.engineering.read'))) throw new Error('Acesso não autorizado à engenharia.');
  }
  async function all(table: string, columns: string, filter?: (query: any) => any, order = 'id'): Promise<WebRow[]> {
    const rows: WebRow[] = [];
    for (let offset = 0; offset < 20_000; offset += 500) {
      let query: any = client.from(table).select(columns).order(order).order('id');
      if (filter) query = filter(query);
      const result = checked(await query.range(offset, offset + 499));
      rows.push(...(result.data || []));
      if (!result.data || result.data.length < 500) return rows;
    }
    throw new Error('A configuração excedeu o limite desta consulta. Restrinja o tipo de equipamento.');
  }
  async function byIds(table: string, columns: string, ids: string[]): Promise<WebRow[]> {
    const rows: WebRow[] = [];
    for (let offset = 0; offset < ids.length; offset += 100) rows.push(...await all(table, columns, q => q.in('id', ids.slice(offset, offset + 100))));
    return rows;
  }
  async function baseChoices() {
    const [types, cells] = await Promise.all([all('rm_tipos_equipamento', TYPE, undefined, 'nome'), all('rm_celulas', CELL, undefined, 'ordem')]);
    return { types, cells };
  }
  async function getEngineeringMatrix(typeId?: string) {
    authorize();
    const { types, cells } = await baseChoices();
    const selectedTypeId = typeId ? types.find(type => type.id === typeId)?.id ?? null : types[0]?.id ?? null;
    if (!selectedTypeId) return { rows: [] as WebRow[], types, cells, selectedTypeId };
    const rows = await all('rm_celula_tipos_equipamento', MATRIX, q => q.eq('tipo_equipamento_id', selectedTypeId));
    const children = async (table: string, columns: string, filter?: (q: any) => any) => {
      const output: WebRow[] = [];
      for (let offset = 0; offset < rows.length; offset += 100) output.push(...await all(table, columns, q => {
        q = q.in('celula_tipo_equipamento_id', rows.slice(offset, offset + 100).map(row => row.id));
        return filter ? filter(q) : q;
      }));
      return output;
    };
    const [forms, photos, stages] = await Promise.all([
      children('rm_celula_form_tipos_equipamento', 'id,celula_tipo_equipamento_id', q => q.eq('ativo', true)),
      children('rm_fotos', 'id,celula_tipo_equipamento_id', q => q.is('projeto_id', null).is('celula_projeto_id', null).eq('lixeira', false)),
      children('rm_aprovacoes_etapas', 'id,celula_tipo_equipamento_id', q => q.is('projeto_id', null).is('celula_projeto_id', null).eq('ativo', true)),
    ]);
    const count = (values: WebRow[], id: string) => values.filter(row => row.celula_tipo_equipamento_id === id).length;
    const resultRows: WebRow[] = rows.map(row => ({ ...row, form_count: count(forms, row.id), photo_count: count(photos, row.id), stage_count: count(stages, row.id) }));
    return { rows: resultRows, types, cells, selectedTypeId };
  }
  async function getEngineeringEntry(id: string): Promise<EngineeringSnapshot | null> {
    authorize();
    if (!uuid.safeParse(id).success) return null;
    // One STABLE statement is essential: a parent timestamp from an earlier
    // query must never be paired with children from a later committed revision.
    const raw = checked(await client.rpc('rm_web_engineering_snapshot_v1', { p_id: id })).data;
    if (!raw?.matrix) return null;
    if (raw.matrix.id !== id || !Array.isArray(raw.form_ids) || !Array.isArray(raw.photos) || !Array.isArray(raw.stages)) throw new Error('A configuração retornada não pôde ser validada.');
    return { matrix: pick(raw.matrix, MATRIX), form_ids: raw.form_ids,
      photos: raw.photos.map((row: WebRow) => pick(row, PHOTO)), stages: raw.stages.map((row: WebRow) => pick(row, STAGE)) };
  }
  async function getEngineeringChoices(entry?: EngineeringSnapshot | null) {
    authorize();
    const formIds = selectedIds(entry?.form_ids ?? []);
    const userIds = selectedIds((entry?.stages ?? []).flatMap(stage => [stage.aprovador_id, ...(stage.aprovadores_ids ?? []), ...(stage.aprovadores_retorno_ids ?? [])]));
    const [base, activeForms, currentForms, activeUsers, currentUsers, cellUserLinks, photoTitles, statusResult] = await Promise.all([
      baseChoices(), all('rm_forms', 'id,titulo,ativo', q => q.eq('ativo', true), 'titulo'), byIds('rm_forms', 'id,titulo,ativo', formIds),
      all('rm_users', 'id,nome,status', q => q.eq('status', 'ativo'), 'nome'), byIds('rm_users', 'id,nome,status', userIds),
      all('rm_tablet_celula_users', 'id,celula_id,identidade_id'), all('rm_cadastro_fotos', TITLE, undefined, 'titulo'),
      client.from('rm_option_sets').select('option_key,bubble_display,sort_order').eq('option_set_key', 'status_cel_proj').order('sort_order'),
    ]);
    const merge = (available: WebRow[], current: WebRow[], expected: string[], label: string) => {
      const rows = new Map([...available, ...current].map(row => [row.id, row]));
      for (const id of expected) if (!rows.has(id)) rows.set(id, { id, [label]: 'Referência não disponível', missing: true });
      return [...rows.values()];
    };
    const linkedUsers = new Set(cellUserLinks.map(link => link.identidade_id));
    return { ...base,
      forms: await withFormVersionLabels(client, merge(activeForms, currentForms, formIds, 'titulo')),
      users: merge(activeUsers.filter(user => linkedUsers.has(user.id)), currentUsers, userIds, 'nome'),
      cellUserLinks, photoTitles: photoTitles.map(row => photoTitleScope(row, base.cells)),
      statuses: (checked(statusResult).data || []).map((row: any) => ({ ...row, id: row.option_key })),
    };
  }
  async function listPhotoTitles(filters: PhotoTitleFilters = {}) {
    authorize();
    const cells = await all('rm_celulas', CELL, undefined, 'nome');
    let query: any = client.from('rm_cadastro_fotos').select(TITLE, { count: 'exact' });
    const term = searchTerm(filters.q);
    if (term) query = query.or(`titulo.ilike.%${term}%,celula_nome.ilike.%${term}%`);
    if (filters.cell) {
      const cell = cells.find(row => row.id === filters.cell);
      if (!cell) return { rows: [] as PhotoTitleRow[], total: 0, page: pageNumber(filters.page), pageSize: 50, cells };
      query = query.eq('celula_nome', cell.nome);
    }
    const page = pageNumber(filters.page), pageSize = 50;
    const result = checked(await query.order('titulo').order('id').range((page - 1) * pageSize, page * pageSize - 1));
    return { rows: (result.data || []).map((row: WebRow) => photoTitleScope(row, cells)) as PhotoTitleRow[], total: result.count ?? 0, page, pageSize, cells };
  }
  async function getPhotoTitle(id: string): Promise<PhotoTitleRow | null> {
    authorize();
    if (!uuid.safeParse(id).success) return null;
    const [result, cells] = await Promise.all([client.from('rm_cadastro_fotos').select(TITLE).eq('id', id).maybeSingle(), all('rm_celulas', CELL)]);
    const row = checked(result).data;
    return row ? photoTitleScope(row, cells) : null;
  }
  return { getEngineeringMatrix, getEngineeringEntry, getEngineeringChoices, listPhotoTitles, getPhotoTitle };
}

async function data() {
  const { requireWebUser } = await import('./auth');
  const session = await requireWebUser('em.engineering.read');
  return createEngineeringData(session.client, session.sso?.capabilities);
}
export async function getEngineeringMatrix(typeId?: string) { return (await data()).getEngineeringMatrix(typeId); }
export async function getEngineeringEntry(id: string) { return (await data()).getEngineeringEntry(id); }
export async function getEngineeringChoices(entry?: EngineeringSnapshot | null) { return (await data()).getEngineeringChoices(entry); }
export async function listPhotoTitles(filters: PhotoTitleFilters = {}) { return (await data()).listPhotoTitles(filters); }
export async function getPhotoTitle(id: string) { return (await data()).getPhotoTitle(id); }
export const listEngineering = getEngineeringMatrix;
export const getEngineeringSnapshot = getEngineeringEntry;
