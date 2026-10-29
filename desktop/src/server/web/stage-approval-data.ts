import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { pageNumber, searchTerm, uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import { stageActions } from './stage-approval-policy';

const text = z.string().nullable();
const nullableId = uuid.nullable();
const timestamp = z.string().datetime({ offset: true });
const actorSchema = z.object({ id: uuid, nome: text });
const stageSchema = z.object({
  id: uuid, projeto_id: uuid, celula_projeto_id: nullableId, celula_origem_id: uuid, celula_destino_id: nullableId,
  status: text, status_cel_proj: text, bloquear_avanco_sem_aprov: z.boolean(), aprovador_id: nullableId,
  aprovadores_ids: z.array(uuid), aprovadores_retorno_ids: z.array(uuid), aprovado_por_id: nullableId,
  data_aprovacao: timestamp.nullable(), created_at: timestamp, updated_at: timestamp,
});
const allocationSchema = z.object({
  id: uuid, projeto_id: uuid, celula_id: uuid, status: text, visibilidade: z.boolean(), bloqueada: text,
  motivo_bloqueio: text, updated_at: timestamp,
});
const projectSchema = z.object({
  id: uuid, numero: text, nome: text, cliente_id: nullableId, cliente_nome_exportacao: text,
  cliente_nome: text, descricao_equipamento: text,
});
const listItemSchema = z.object({
  stage: stageSchema,
  allocation: allocationSchema.nullable(), project: projectSchema.nullable(),
  origin: actorSchema.nullable(), destination: actorSchema.nullable(),
  available_actions: z.array(z.enum(stageActions)), action_reason: text,
});
const historySchema = z.object({
  id: uuid, aprovacao_etapa_id: uuid, acao: z.enum(stageActions), status_anterior: text, status_novo: text,
  observacao: text, actor_id: nullableId, actor_nome: text, created_at: timestamp, source: z.literal('web'),
});
const legacyHistorySchema = z.object({
  id: uuid, projeto_id: nullableId, celula_id: nullableId, aprovador_id: nullableId, aprovador_nome: text,
  status_aprovacao: text, data_aprovacao: timestamp.nullable(), created_at: timestamp,
});
const snapshotSchema = listItemSchema.extend({
  approvers: z.array(actorSchema), return_approvers: z.array(actorSchema), decided_by: actorSchema.nullable(),
  history: z.array(historySchema), legacy_history: z.array(legacyHistorySchema),
});
const listSchema = z.object({ items: z.array(listItemSchema), total: z.number().int().nonnegative(), page: z.number().int().positive(), page_size: z.number().int().min(1).max(100) });

export type StageApprovalListItem = z.infer<typeof listItemSchema>;
export type StageApprovalSnapshot = z.infer<typeof snapshotSchema>;
export type StageApprovalPage = z.infer<typeof listSchema>;
export type StageApprovalState = 'pending' | 'approved' | 'returned' | 'all';
export type StageApprovalFilters = { q?: string; project?: string; cell?: string; state?: StageApprovalState; mine?: boolean; page?: number | string };
const queryError = () => new Error('Não foi possível consultar as aprovações de etapas. Tente novamente.');

/** Reads use the user's RLS client; no media, Auth, synchronization or private receipt metadata enters these DTOs. */
export function createStageApprovalData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  const canDecide = capabilities === undefined || capabilities.includes('em.approvals.decide');
  function authorize() {
    if (capabilities !== undefined && (!capabilities.includes('em.portal.read') || !capabilities.includes('em.approvals.read'))) throw new Error('Acesso não autorizado às aprovações de etapas.');
  }
  function enforceScope<T extends StageApprovalListItem>(item: T): T {
    if (item.allocation && (item.allocation.projeto_id !== item.stage.projeto_id || item.allocation.celula_id !== item.stage.celula_origem_id)) throw queryError();
    if (item.project && item.project.id !== item.stage.projeto_id) throw queryError();
    if (item.origin && item.origin.id !== item.stage.celula_origem_id) throw queryError();
    if (item.destination && item.destination.id !== item.stage.celula_destino_id) throw queryError();
    // SQL provides operational eligibility. Central grants remain independently
    // enforced at the BFF and are checked again before every mutation.
    return canDecide ? item : { ...item, available_actions: [], action_reason: 'Seu acesso permite consultar as etapas, mas não registrar decisões.' };
  }
  function matchingFilter(item: StageApprovalListItem, filters: StageApprovalFilters): boolean {
    if (filters.project && item.stage.projeto_id !== filters.project) return false;
    if (filters.cell && item.stage.celula_origem_id !== filters.cell) return false;
    if (filters.mine && !item.available_actions.length) return false;
    const status = item.stage.status ?? 'nulo';
    switch (filters.state ?? 'pending') {
      case 'pending': return status === 'nulo';
      case 'approved': return status === 'aprovado';
      case 'returned': return status === 'reprovado';
      default: return true;
    }
  }
  async function listStageApprovals(filters: StageApprovalFilters = {}): Promise<StageApprovalPage> {
    authorize();
    const page = pageNumber(filters.page), page_size = 25;
    if ((filters.project && !uuid.safeParse(filters.project).success) || (filters.cell && !uuid.safeParse(filters.cell).success)) return { items: [], total: 0, page, page_size };
    if (filters.state && !['pending', 'approved', 'returned', 'all'].includes(filters.state)) throw queryError();
    // A read-only account cannot have actions waiting for its decision.
    if (filters.mine && !canDecide) return { items: [], total: 0, page, page_size };
    const result = await client.rpc('rm_web_stage_approvals_v1', {
      p_project_id: filters.project || null, p_cell_id: filters.cell || null,
      p_state: filters.state || 'pending', p_mine: filters.mine === true,
      p_search: searchTerm(filters.q), p_page: page, p_page_size: page_size,
    });
    if (result.error) throw queryError();
    const parsed = listSchema.safeParse(result.data);
    if (!parsed.success || parsed.data.page !== page || parsed.data.page_size !== page_size || parsed.data.items.length > page_size
      || new Set(parsed.data.items.map(item => item.stage.id)).size !== parsed.data.items.length
      || parsed.data.items.some(item => !matchingFilter(item, filters))) throw queryError();
    return { ...parsed.data, items: parsed.data.items.map(enforceScope) };
  }
  async function getStageApproval(id: string): Promise<StageApprovalSnapshot | null> {
    authorize();
    if (!uuid.safeParse(id).success) return null;
    // A single STABLE snapshot pairs the two exact timestamps with eligibility
    // and history from the same database statement, including legacy null links.
    const result = await client.rpc('rm_web_stage_approval_snapshot_v1', { p_id: id });
    if (result.error) throw queryError();
    if (result.data === null) return null;
    const parsed = snapshotSchema.safeParse(result.data);
    if (!parsed.success || parsed.data.stage.id !== id
      || parsed.data.history.some(event => event.aprovacao_etapa_id !== id)
      || parsed.data.legacy_history.some(event => event.projeto_id !== parsed.data.stage.projeto_id || event.celula_id !== parsed.data.stage.celula_origem_id)) throw queryError();
    return enforceScope(parsed.data);
  }
  async function getStageApprovalChoices() {
    authorize();
    const cells: z.infer<typeof actorSchema>[] = [];
    for (let offset = 0; offset < 20_000; offset += 500) {
      const result = await client.from('rm_celulas').select('id,nome').order('nome').order('id').range(offset, offset + 499);
      if (result.error) throw queryError();
      const parsed = z.array(actorSchema).safeParse(result.data ?? []);
      if (!parsed.success) throw queryError();
      cells.push(...parsed.data);
      if (parsed.data.length < 500) return { cells };
    }
    throw new Error('A consulta de células excedeu o limite desta tela.');
  }
  return { listStageApprovals, getStageApproval, getStageApprovalChoices };
}

async function data() {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser('em.approvals.read');
  return createStageApprovalData(access.client, access.sso?.capabilities);
}
export async function listStageApprovals(filters: StageApprovalFilters = {}) { return (await data()).listStageApprovals(filters); }
export async function getStageApproval(id: string) { return (await data()).getStageApproval(id); }
export async function getStageApprovalChoices() { return (await data()).getStageApprovalChoices(); }
