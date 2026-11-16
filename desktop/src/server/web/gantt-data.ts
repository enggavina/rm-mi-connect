import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { pageNumber, searchTerm, uuid } from './policy';
import { GANTT_MAX_ITEMS, GANTT_MAX_LINKS, ganttFiltersSchema, ganttRevision, type GanttFilters } from './gantt-policy';
import type { CorporateCapability } from './sso-policy';
import { ganttProjectSettingsSchema } from './gantt-settings-policy';

const timestamp = z.string().datetime({ offset: true });
const text = z.string().nullable();
const integer = z.number().int().nullable();
const itemSchema = z.object({
  id: uuid, projeto_id: uuid, celula_id: uuid,
  numero_projeto: text, cliente_nome_export: text, celula_nome: text,
  status: text, bloqueada: text, motivo_bloqueio: text, visibilidade: z.boolean(), prioridade: text,
  indice: integer, posicao: integer, responsavel_nome: text,
  data_inicio: timestamp.nullable(), data_limite: timestamp.nullable(), updated_at: timestamp, can_edit: z.boolean(),
});
const projectSchema = z.object({
  id: uuid, numero: text, nome: text, updated_at: timestamp, plan_version: ganttRevision, closed: z.boolean(),
  planned_start: timestamp.nullable(), planned_end: timestamp.nullable(), contract_date: timestamp.nullable(), renegotiated_date: timestamp.nullable(),
});
const cellSchema = z.object({ id: uuid, nome: text });
const linkSchema = z.object({ projeto_id: uuid, predecessor_id: uuid, successor_id: uuid, lag_days: z.number().int().min(0).max(3650) });
const baselineSchema = z.object({
  id: uuid, label: z.string().min(1).max(120), created_at: timestamp,
  items: z.array(z.object({ allocation_id: uuid, data_inicio: timestamp.nullable(), data_limite: timestamp.nullable() })).max(GANTT_MAX_ITEMS),
});
export const ganttSnapshotSchema = z.object({
  as_of: timestamp, filters: ganttFiltersSchema, total: z.number().int().nonnegative(), complete: z.boolean(),
  items: z.array(itemSchema).max(GANTT_MAX_ITEMS), projects: z.array(projectSchema).max(GANTT_MAX_ITEMS),
  cells: z.array(cellSchema).max(GANTT_MAX_ITEMS), links: z.array(linkSchema).max(GANTT_MAX_LINKS), baseline: baselineSchema.nullable(),
  settings: z.array(ganttProjectSettingsSchema).max(GANTT_MAX_ITEMS).default([]),
});
export type GanttSnapshot = z.infer<typeof ganttSnapshotSchema>;
export type GanttItem = GanttSnapshot['items'][number];
export type GanttProject = GanttSnapshot['projects'][number];
export type GanttCell = GanttSnapshot['cells'][number];
export type GanttLink = GanttSnapshot['links'][number];
export type GanttBaseline = NonNullable<GanttSnapshot['baseline']>;
export type GanttProjectChoices = { items: { id: string; numero: string | null; nome: string | null }[]; page: number; page_size: 25; total: number };
const unavailable = () => new Error('Não foi possível consultar o Gantt. Tente novamente.');
const oversized = () => new Error('O Gantt excede o limite desta consulta. Selecione um projeto ou uma célula.');
const key = (id: string) => id.toLowerCase();

export function createGanttData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  const allowed = (capability: CorporateCapability) => capabilities === undefined || capabilities.includes(capability);
  function authorize(project = false) {
    if (!allowed('em.portal.read') || !allowed('em.planning.read') || project && !allowed('em.projects.read')) {
      throw new Error('Acesso não autorizado a esta área.');
    }
  }
  async function getGanttSnapshot(input: GanttFilters): Promise<GanttSnapshot> {
    authorize();
    const checked = ganttFiltersSchema.safeParse(input);
    if (!checked.success) throw unavailable();
    const filters = checked.data;
    if (filters.project_id) authorize(true);
    let result;
    try { result = await client.rpc('rm_web_gantt_snapshot_v1', { p_filters: filters }); } catch { throw unavailable(); }
    if (result.error) throw result.error.code === 'PT413' ? oversized() : unavailable();
    const parsed = ganttSnapshotSchema.safeParse(result.data);
    if (!parsed.success) throw unavailable();
    const data = parsed.data;
    if (data.filters.project_id !== filters.project_id || data.filters.cell_id !== filters.cell_id || data.filters.include_closed !== filters.include_closed
      || (data.complete ? data.total > GANTT_MAX_ITEMS || data.items.length !== data.total
        : data.total <= GANTT_MAX_ITEMS || !!(data.items.length || data.projects.length || data.cells.length || data.links.length || data.settings.length || data.baseline))) throw unavailable();
    const items = new Map(data.items.map(item => [key(item.id), item])), projects = new Map(data.projects.map(project => [key(project.id), project]));
    const cells = new Set(data.cells.map(cell => key(cell.id)));
    if (new Set(data.settings.map(settings => key(settings.projeto_id))).size !== data.settings.length
      || data.settings.some(settings => !projects.has(key(settings.projeto_id)))) throw unavailable();
    if (items.size !== data.items.length || projects.size !== data.projects.length || cells.size !== data.cells.length
      || filters.project_id && data.projects.some(project => key(project.id) !== key(filters.project_id!))
      || filters.cell_id && data.cells.some(cell => key(cell.id) !== key(filters.cell_id!))
      || data.projects.some(project => key(project.id) !== key(filters.project_id ?? '') && !data.items.some(item => key(item.projeto_id) === key(project.id)))
      || data.cells.some(cell => key(cell.id) !== key(filters.cell_id ?? '') && !data.items.some(item => key(item.celula_id) === key(cell.id)))
      || data.items.some(item => !projects.has(key(item.projeto_id)) || !cells.has(key(item.celula_id))
        || filters.project_id && key(item.projeto_id) !== key(filters.project_id)
        || filters.cell_id && key(item.celula_id) !== key(filters.cell_id)
        || !filters.include_closed && (projects.get(key(item.projeto_id))!.closed || ['finalizado', 'n_a'].includes(item.status ?? ''))
        || item.can_edit && (projects.get(key(item.projeto_id))!.closed || ['finalizado', 'n_a'].includes(item.status ?? '')))) throw unavailable();
    const edges = new Set<string>();
    for (const link of data.links) {
      const from = items.get(key(link.predecessor_id)), to = items.get(key(link.successor_id)), edge = `${key(link.predecessor_id)}:${key(link.successor_id)}`;
      if (!from || !to || from.id === to.id || key(from.projeto_id) !== key(link.projeto_id) || key(to.projeto_id) !== key(link.projeto_id) || edges.has(edge)) throw unavailable();
      edges.add(edge);
    }
    if (data.baseline && (!filters.project_id || new Set(data.baseline.items.map(item => key(item.allocation_id))).size !== data.baseline.items.length)) throw unavailable();
    // Corporate capabilities remain independent even when the local RLS profile can read more.
    const canManage = allowed('em.planning.manage') && allowed('em.projects.read');
    if (!canManage) data.items = data.items.map(item => ({ ...item, can_edit: false }));
    if (!allowed('em.projects.read')) data.projects = data.projects.map(project => ({ ...project,
      numero: data.items.find(item => key(item.projeto_id) === key(project.id))?.numero_projeto ?? null,
      nome: null, planned_start: null, planned_end: null, contract_date: null, renegotiated_date: null,
    }));
    if (!allowed('em.projects.read')) data.settings = data.settings.map(settings => ({ ...settings, milestones: [] }));
    return data;
  }
  async function listGanttProjects(query?: string, requestedPage?: number | string): Promise<GanttProjectChoices> {
    authorize(true);
    const page = pageNumber(requestedPage), term = searchTerm(query), pageSize = 25;
    let request = client.from('rm_projetos').select('id,numero,nome', { count: 'exact' });
    if (term) request = request.or(`numero.ilike.%${term}%,nome.ilike.%${term}%`);
    let result;
    try { result = await request.order('numero').order('id').range((page - 1) * pageSize, page * pageSize - 1); } catch { throw unavailable(); }
    if (result.error || !Number.isInteger(result.count) || (result.count ?? -1) < 0) throw unavailable();
    const parsed = z.array(z.object({ id: uuid, numero: text, nome: text })).max(pageSize).safeParse(result.data);
    if (!parsed.success || new Set(parsed.data.map(project => key(project.id))).size !== parsed.data.length || parsed.data.length > result.count!) throw unavailable();
    return { items: parsed.data, total: result.count!, page, page_size: pageSize };
  }
  return { getGanttSnapshot, listGanttProjects };
}

async function data() {
  const { requireWebUser } = await import('./auth');
  const session = await requireWebUser('em.planning.read');
  return createGanttData(session.client, session.sso?.capabilities);
}
export async function getGanttSnapshot(filters: GanttFilters) { return (await data()).getGanttSnapshot(filters); }
export async function listGanttProjects(query?: string, page?: number | string) { return (await data()).listGanttProjects(query, page); }
