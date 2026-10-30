import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { pageNumber, searchTerm, uuid } from './policy';
import { queuePriorities, receivingReasons, type ReceivingReason } from './pcp-policy';
import type { CorporateCapability } from './sso-policy';

export type { ReceivingReason, QueuePriority } from './pcp-policy';
const text = z.string().nullable(), nullableId = uuid.nullable();
const timestamp = z.string().datetime({ offset: true });
const count = z.number().int().nonnegative();
// Hours stay exact decimal strings returned by PostgreSQL, with null meaning
// no estimate was supplied. The BFF never invents available hours or a ratio.
const hours = z.string().regex(/^-?\d+(?:\.\d+)?$/).nullable();
const cellSchema = z.object({ id: uuid, nome: z.string() });
const queueItemSchema = z.object({
  id: uuid, projeto_id: uuid, celula_id: uuid, numero_projeto: text, cliente_nome_export: text,
  tipo_equipamento_nome_export: text, status: text, bloqueada: text, motivo_bloqueio: text,
  visibilidade: z.boolean(), prioridade: z.enum(queuePriorities).nullable(),
  indice: z.number().int().nullable(), posicao: z.number().int().nullable(),
  horas_previstas: hours, horas_realizadas: hours, data_inicio: timestamp.nullable(), data_limite: timestamp.nullable(),
  responsavel_id: nullableId, responsavel_nome: text, updated_at: timestamp,
});
const queueSchema = z.object({
  cell: cellSchema.extend({ updated_at: timestamp }), items: z.array(queueItemSchema).max(2000),
  total: count, queue_version: z.string().regex(/^[0-9a-f]{64}$/), complete: z.boolean(),
});
const loadCellSchema = cellSchema.extend({
  open_allocations: count, visible_allocations: count, hidden_allocations: count,
  blocked_allocations: count, overdue_allocations: count, estimated_allocations: count, unestimated_allocations: count,
  planned_hours: hours, realized_hours: hours,
});
const loadSchema = z.object({ as_of: timestamp, cells: z.array(loadCellSchema) });
const receivingItemSchema = z.object({
  id: uuid, numero: text, nome: text, cliente_id: nullableId, cliente_nome_exportacao: text, cliente_nome: text,
  descricao_equipamento: text, chegada_do_equipamento: timestamp.nullable(), nota_fiscal: text,
  tipo_equipamento_id: nullableId, tipo_equipamento_nome: text, status_pcp: text, updated_at: timestamp,
  allocation_count: count, historical_allocation_count: count, reasons: z.array(z.enum(receivingReasons)).min(1),
});
const summarySchema = z.object({
  without_number: count, without_type: count, without_allocation: count, awaiting_arrival: count, legacy_type_locked: count,
});
const receivingPageSchema = z.object({
  items: z.array(receivingItemSchema), total: count, page: z.number().int().positive(),
  page_size: z.number().int().min(1).max(100), summary: summarySchema,
});

export type PcpCellQueue = z.infer<typeof queueSchema>;
export type PcpQueueItem = z.infer<typeof queueItemSchema>;
export type PcpLoad = z.infer<typeof loadSchema>;
export type ReceivingItem = z.infer<typeof receivingItemSchema>;
export type ReceivingPage = z.infer<typeof receivingPageSchema>;
export type ReceivingFilters = { reason?: ReceivingReason; q?: string; page?: number | string };
const queryError = () => new Error('Não foi possível consultar o planejamento. Tente novamente.');

export function createPcpData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  function authorize(capability: CorporateCapability) {
    if (capabilities !== undefined && (!capabilities.includes('em.portal.read') || !capabilities.includes(capability))) {
      throw new Error('Acesso não autorizado a esta área.');
    }
  }
  async function getCellQueue(cellId: string): Promise<PcpCellQueue | null> {
    authorize('em.planning.read');
    if (!uuid.safeParse(cellId).success) return null;
    const result = await client.rpc('rm_web_cell_queue_snapshot_v1', { p_cell_id: cellId });
    if (result.error) throw queryError();
    if (result.data === null) return null;
    const parsed = queueSchema.safeParse(result.data);
    if (!parsed.success) throw queryError();
    const data = parsed.data;
    if (data.cell.id !== cellId || data.items.some(item => item.celula_id !== cellId || ['finalizado', 'n_a'].includes(item.status ?? ''))
      || new Set(data.items.map(item => item.id)).size !== data.items.length
      || (data.complete ? data.items.length !== data.total : data.items.length !== 0 || data.total <= 2000)) throw queryError();
    return data;
  }
  async function getPlanningLoad(): Promise<PcpLoad> {
    authorize('em.planning.read');
    const result = await client.rpc('rm_web_planning_load_v1');
    if (result.error) throw queryError();
    const parsed = loadSchema.safeParse(result.data);
    if (!parsed.success || new Set(parsed.data.cells.map(cell => cell.id)).size !== parsed.data.cells.length
      || parsed.data.cells.some(cell => cell.visible_allocations + cell.hidden_allocations !== cell.open_allocations
        || cell.estimated_allocations + cell.unestimated_allocations !== cell.open_allocations
        || cell.blocked_allocations > cell.open_allocations || cell.overdue_allocations > cell.open_allocations
        || (cell.estimated_allocations === 0 ? cell.planned_hours !== null : cell.planned_hours === null))) throw queryError();
    return parsed.data;
  }
  async function listReceiving(filters: ReceivingFilters = {}): Promise<ReceivingPage> {
    authorize('em.projects.read');
    const reason = filters.reason ?? 'all', page = pageNumber(filters.page), page_size = 25;
    if (reason !== 'all' && !receivingReasons.includes(reason)) throw queryError();
    const result = await client.rpc('rm_web_receivings_v1', { p_reason: reason, p_search: searchTerm(filters.q), p_page: page, p_page_size: page_size });
    if (result.error) throw queryError();
    const parsed = receivingPageSchema.safeParse(result.data);
    if (!parsed.success) throw queryError();
    const data = parsed.data;
    if (data.page !== page || data.page_size !== page_size || data.items.length > page_size
      || new Set(data.items.map(item => item.id)).size !== data.items.length
      || data.items.some(item => !validReceivingItem(item) || (reason !== 'all' && !item.reasons.includes(reason)))) throw queryError();
    return data;
  }
  async function getPcpChoices() {
    authorize('em.planning.read');
    const cells: z.infer<typeof cellSchema>[] = [];
    for (let offset = 0; offset < 20_000; offset += 500) {
      const result = await client.from('rm_celulas').select('id,nome').order('nome').order('id').range(offset, offset + 499);
      if (result.error) throw queryError();
      const parsed = z.array(cellSchema).safeParse(result.data ?? []);
      if (!parsed.success) throw queryError();
      cells.push(...parsed.data);
      if (parsed.data.length < 500) return { cells };
    }
    throw new Error('A consulta de células excedeu o limite desta tela.');
  }
  return { getCellQueue, getPlanningLoad, listReceiving, getPcpChoices };
}

function validReceivingItem(item: ReceivingItem): boolean {
  if (['cancelado', 'finalizando_para_faturar'].includes(item.status_pcp ?? '')) return false;
  if (item.historical_allocation_count < item.allocation_count) return false;
  const withoutNumber = !item.numero?.trim(), withoutType = item.tipo_equipamento_id === null, withoutAllocation = item.allocation_count === 0;
  if (!withoutNumber && !withoutType && !withoutAllocation) return false;
  const expected: typeof receivingReasons[number][] = [];
  if (withoutNumber) expected.push('without_number');
  if (withoutType) expected.push('without_type');
  if (withoutAllocation) expected.push('without_allocation');
  if (item.chegada_do_equipamento === null) expected.push('awaiting_arrival');
  if (withoutType && item.historical_allocation_count > 0) expected.push('legacy_type_locked');
  return item.reasons.length === expected.length && new Set(item.reasons).size === expected.length && expected.every(reason => item.reasons.includes(reason));
}

async function data(capability: CorporateCapability) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(capability);
  return createPcpData(access.client, access.sso?.capabilities);
}
export async function getCellQueue(cellId: string) { return (await data('em.planning.read')).getCellQueue(cellId); }
export async function getPlanningLoad() { return (await data('em.planning.read')).getPlanningLoad(); }
export async function listReceiving(filters: ReceivingFilters = {}) { return (await data('em.projects.read')).listReceiving(filters); }
export async function getPcpChoices() { return (await data('em.planning.read')).getPcpChoices(); }
