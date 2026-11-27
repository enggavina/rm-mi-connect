import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import { ganttRevision } from './gantt-policy';
import { EXECUTION_READ_SCOPES, EXECUTION_MAX_ALLOCATIONS, EXECUTION_MAX_SESSIONS, executionFiltersSchema, executionKindSchema, executionMinutesSchema, executionPauseReasonSchema, executionStateSchema, executionTimestampSchema, type ExecutionFilters } from './execution-policy';
import type { CorporateCapability } from './sso-policy';
import type { WorkshopRead } from './workshop-read-policy';

const text = z.string().nullable(), timestamp = executionTimestampSchema;
export const executionAllocationSchema = z.object({
  id: uuid, project_id: uuid, cell_id: uuid, numero_projeto: text, cliente_nome: text, cell_name: text, status: text,
  retired: z.boolean(), project_closed: z.boolean(), visible: z.boolean(), blocked: z.boolean(),
  planned_start: timestamp.nullable(), planned_end: timestamp.nullable(), updated_at: timestamp,
});
export const executionSessionSchema = z.object({
  id: uuid, allocation_id: uuid, project_id: uuid, cell_id: uuid, numero_projeto: text, cell_name: text,
  operator_id: uuid, operator_name: z.string().nullable(), state: executionStateSchema, needs_review: z.boolean(),
  last_event_id: uuid.nullable(), last_captured_at: timestamp.nullable(), last_received_at: timestamp.nullable(),
  version: ganttRevision, confirmed_minutes: executionMinutesSchema.nullable(), effort_source: z.enum(['operator', 'manager']).nullable(),
  clock_warning: z.boolean(), has_review: z.boolean(),
});
export const executionEventSchema = z.object({
  id: uuid, session_id: uuid, previous_event_id: uuid.nullable(), kind: executionKindSchema,
  occurred_at: timestamp, received_at: timestamp, pause_reason: executionPauseReasonSchema.nullable(), note: z.string().max(1000).nullable(),
  effort_minutes: executionMinutesSchema.nullable(), disposition: z.enum(['accepted', 'review']), review_reason: z.string().min(1).max(120).nullable(),
  operator_id: uuid, operator_name: z.string().nullable(),
});
export const executionReviewSchema = z.object({ id: uuid, session_id: uuid, action: z.enum(['confirm_finished', 'void']),
  reported_finished_at: timestamp.nullable(), effort_minutes: executionMinutesSchema.nullable(), note: z.string().max(1000), reason: z.string().min(3).max(2000), actor_name: text, created_at: timestamp });
export const executionDetailSchema = z.object({ session: executionSessionSchema,
  events: z.array(executionEventSchema).max(200), events_total: z.number().int().nonnegative(), events_complete: z.boolean(),
  reviews: z.array(executionReviewSchema).max(100), reviews_total: z.number().int().nonnegative(), reviews_complete: z.boolean(),
});
export const executionSnapshotSchema = z.object({ as_of: timestamp, filters: executionFiltersSchema, complete: z.boolean(), total: z.number().int().nonnegative(),
  allocations: z.array(executionAllocationSchema).max(EXECUTION_MAX_ALLOCATIONS), sessions: z.array(executionSessionSchema).max(EXECUTION_MAX_SESSIONS), detail: executionDetailSchema.nullable() });
export type ExecutionSnapshot = z.infer<typeof executionSnapshotSchema>;
export type ExecutionAllocation = z.infer<typeof executionAllocationSchema>;
export type ExecutionSession = z.infer<typeof executionSessionSchema>;
export type ExecutionEvent = z.infer<typeof executionEventSchema>;
export type ExecutionReview = z.infer<typeof executionReviewSchema>;
export type ExecutionDetail = z.infer<typeof executionDetailSchema>;
const key = (id: string) => id.toLowerCase();
const unavailable = () => new Error('Não foi possível consultar os apontamentos de execução. Tente novamente.');
const unique = (rows: { id: string }[]) => new Set(rows.map(row => key(row.id))).size === rows.length;
export class ExecutionSelectionUnavailable extends Error {
  constructor() { super('Este contexto de apontamentos está indisponível.'); }
}
export function createExecutionData(client: SupabaseClient, capabilities?: readonly CorporateCapability[], workshopRead?: WorkshopRead) {
  return { async getExecutionSnapshot(input: ExecutionFilters): Promise<ExecutionSnapshot> {
    if (capabilities && !EXECUTION_READ_SCOPES.every(scope => capabilities.includes(scope))) throw new Error('Acesso não autorizado a esta área.');
    const filters = executionFiltersSchema.safeParse(input); if (!filters.success) throw unavailable();
    let payload: unknown;
    if (workshopRead) {
      payload = await workshopRead('execution_snapshot', filters.data);
      if (payload === null && (filters.data.project_id || filters.data.cell_id || filters.data.session_id)) throw new ExecutionSelectionUnavailable();
    } else {
      let result;
      try { result = await client.rpc('rm_web_execution_snapshot_v1', { p_filters: filters.data }); } catch { throw unavailable(); }
      if (result.error) throw result.error.code === 'PT413' ? new Error('Os apontamentos excedem o limite de leitura. Selecione um projeto ou uma célula.') : unavailable();
      payload = result.data;
    }
    try { if (Buffer.byteLength(JSON.stringify(payload), 'utf8') > 10 * 1024 * 1024) throw unavailable(); } catch { throw unavailable(); }
    const parsed = executionSnapshotSchema.safeParse(payload); if (!parsed.success) throw unavailable();
    const data = parsed.data;
    if ((['project_id', 'cell_id', 'session_id', 'include_closed'] as const).some(field => data.filters[field] !== filters.data[field])) throw unavailable();
    if (!data.complete) { if (data.allocations.length || data.sessions.length || data.detail) throw unavailable(); return data; }
    if (data.total !== data.allocations.length || !unique(data.allocations) || !unique(data.sessions)) throw unavailable();
    const allocations = new Map(data.allocations.map(row => [key(row.id), row]));
    for (const row of data.allocations) if (filters.data.project_id && key(row.project_id) !== key(filters.data.project_id) || filters.data.cell_id && key(row.cell_id) !== key(filters.data.cell_id)) throw unavailable();
    for (const session of data.sessions) {
      const allocation = allocations.get(key(session.allocation_id));
      if (!allocation || key(allocation.project_id) !== key(session.project_id) || key(allocation.cell_id) !== key(session.cell_id) || session.state === 'review' && !session.needs_review) throw unavailable();
    }
    if (data.detail) {
      const detail = data.detail, summary = data.sessions.find(row => key(row.id) === key(detail.session.id));
      if (!filters.data.session_id || key(detail.session.id) !== key(filters.data.session_id) || !summary || JSON.stringify(summary) !== JSON.stringify(detail.session)
        || !unique(detail.events) || !unique(detail.reviews)
        || detail.events.length !== Math.min(200, detail.events_total) || detail.events_complete !== (detail.events_total <= 200)
        || detail.reviews.length !== Math.min(100, detail.reviews_total) || detail.reviews_complete !== (detail.reviews_total <= 100)) throw unavailable();
      for (const event of detail.events) if (key(event.session_id) !== key(summary.id) || key(event.operator_id) !== key(summary.operator_id)
        || event.disposition === 'accepted' && event.review_reason !== null || event.disposition === 'review' && event.review_reason === null
        || event.kind !== 'finish' && event.effort_minutes !== null || event.kind === 'pause' && event.pause_reason === null || event.kind !== 'pause' && event.pause_reason !== null) throw unavailable();
      for (const review of detail.reviews) if (key(review.session_id) !== key(summary.id) || review.action === 'confirm_finished' && !review.reported_finished_at
        || review.action === 'void' && (review.reported_finished_at !== null || review.effort_minutes !== null)) throw unavailable();
    } else if (filters.data.session_id) throw unavailable();
    return data;
  } };
}
export async function getExecutionSnapshot(filters: ExecutionFilters) {
  const { requireWebUser } = await import('./auth');
  const { ssoWorkshopRead } = await import('./sso-bridge');
  const session = await requireWebUser(EXECUTION_READ_SCOPES);
  const workshopRead = session.sso && ssoWorkshopRead(session.sso, session.client);
  return createExecutionData(session.client, session.sso?.capabilities, workshopRead).getExecutionSnapshot(filters);
}
