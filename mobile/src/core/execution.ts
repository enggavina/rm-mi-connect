import type { OutboxRow } from './types';

export const EXECUTION_RPC = 'rm_record_execution_event_v1' as const;
export const PAUSE_REASONS = ['material', 'cliente', 'engenharia', 'ferramenta', 'maquina', 'manutencao', 'transporte', 'servico_externo', 'intervalo', 'outro'] as const;
export type PauseReason = typeof PAUSE_REASONS[number];
export type ExecutionKind = 'start' | 'pause' | 'resume' | 'finish';
export type ExecutionState = 'running' | 'paused' | 'finished' | 'review' | 'void';
export type ExecutionSummary = {
  id: string; allocation_id: string; project_id: string; cell_id: string; numero_projeto: string | null; cell_name: string | null;
  operator_id: string; operator_name: string | null; state: ExecutionState; needs_review: boolean; last_event_id: string | null;
  last_captured_at: string | null; last_received_at: string | null; version: string; confirmed_minutes: number | null;
  effort_source: 'operator' | 'manager' | null; clock_warning: boolean; has_review: boolean;
  can_record: boolean;
};
export type ExecutionEvent = { id: string; session_id: string; previous_event_id: string | null; kind: ExecutionKind; occurred_at: string; received_at: string;
  pause_reason: PauseReason | null; note: string | null; effort_minutes: number | null; disposition: 'accepted' | 'review'; review_reason: string | null; operator_id: string; operator_name: string | null };
export type ExecutionReview = { id: string; session_id: string; action: 'confirm_finished' | 'void'; reported_finished_at: string | null;
  effort_minutes: number | null; note: string | null; reason: string; actor_name: string | null; created_at: string };
export type ExecutionSnapshot = {
  as_of: string; operator_id: string;
  allocation: { id: string; project_id: string; cell_id: string; numero_projeto: string | null; cell_name: string | null; status: string | null;
    retired: boolean; project_closed: boolean; visible: boolean; blocked: boolean; updated_at: string };
  running_session: ExecutionSummary | null; session: ExecutionSummary | null; review_sessions: ExecutionSummary[]; review_sessions_total: number; review_sessions_complete: boolean;
  events: ExecutionEvent[]; events_total: number; events_complete: boolean; reviews: ExecutionReview[]; reviews_total: number; reviews_complete: boolean;
};
export type ExecutionParams = { p_session_id: string; p_allocation_id: string; p_previous_event_id: string | null; p_kind: ExecutionKind;
  p_occurred_at: string; p_pause_reason: PauseReason | null; p_note: string | null; p_effort_minutes: number | null };
export type ExecutionReceipt = { event_id: string; session_id: string; disposition: 'accepted' | 'review'; review_reason: string | null; received_at: string; idempotent_replay: boolean };
export type ExecutionContext = { as_of: string; allocation: ExecutionSnapshot['allocation']; session: ExecutionSummary | null; running_session: ExecutionSummary | null; review_session_ids: string[]; known_event_ids: string[] };
export type ExecutionContexts = Readonly<Record<string, ExecutionContext>>;
export function executionAllocationAllowsRecords(allocation: ExecutionSnapshot['allocation']): boolean {
  return !allocation.retired && allocation.visible && !allocation.blocked && !allocation.project_closed && !['finalizado', 'n_a'].includes(allocation.status ?? '');
}
const invalid = () => new Error('Não foi possível validar os apontamentos. Os registros locais foram preservados.');
const uuid = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const timestamp = (value: unknown): value is string => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value)) && value.slice(0, 4) >= '1900' && value.slice(0, 4) <= '2200'
  && new Date(`${value.slice(0, 10)}T12:00:00Z`).toISOString().slice(0, 10) === value.slice(0, 10);
const object = (value: unknown): Record<string, unknown> => { if (!value || typeof value !== 'object' || Array.isArray(value)) throw invalid(); return value as Record<string, unknown>; };
const id = (value: unknown) => { if (!uuid(value)) throw invalid(); return value; };
const at = (value: unknown) => { if (!timestamp(value)) throw invalid(); return value; };
const label = (value: unknown, max = 2000): string => { if (typeof value !== 'string' || value.length > max) throw invalid(); return value; };
const bool = (value: unknown) => { if (typeof value !== 'boolean') throw invalid(); return value; };
const integer = (value: unknown, max = Number.MAX_SAFE_INTEGER) => { if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > max) throw invalid(); return value; };
const nullable = <T>(value: unknown, parse: (value: unknown) => T): T | null => value === null ? null : parse(value);
function choice<T extends string>(value: unknown, values: readonly T[]): T { if (typeof value !== 'string' || !values.includes(value as T)) throw invalid(); return value as T; }
function summary(value: unknown): ExecutionSummary {
  const r = object(value); const version = label(r.version, 64); if (!/^[0-9a-f]{64}$/.test(version)) throw invalid();
  return { id: id(r.id), allocation_id: id(r.allocation_id), project_id: id(r.project_id), cell_id: id(r.cell_id), numero_projeto: nullable(r.numero_projeto, label), cell_name: nullable(r.cell_name, label),
    operator_id: id(r.operator_id), operator_name: nullable(r.operator_name, label), state: choice(r.state, ['running', 'paused', 'finished', 'review', 'void']), needs_review: bool(r.needs_review),
    last_event_id: nullable(r.last_event_id, id), last_captured_at: nullable(r.last_captured_at, at), last_received_at: nullable(r.last_received_at, at), version,
    confirmed_minutes: nullable(r.confirmed_minutes, v => integer(v, 1000000)), effort_source: nullable(r.effort_source, v => choice(v, ['operator', 'manager'])), clock_warning: bool(r.clock_warning), has_review: bool(r.has_review), can_record: bool(r.can_record) };
}
function event(value: unknown): ExecutionEvent {
  const r = object(value); return { id: id(r.id), session_id: id(r.session_id), previous_event_id: nullable(r.previous_event_id, id), kind: choice(r.kind, ['start', 'pause', 'resume', 'finish']),
    occurred_at: at(r.occurred_at), received_at: at(r.received_at), pause_reason: nullable(r.pause_reason, v => choice(v, PAUSE_REASONS)), note: nullable(r.note, v => label(v, 1000)), effort_minutes: nullable(r.effort_minutes, v => integer(v, 1000000)),
    disposition: choice(r.disposition, ['accepted', 'review']), review_reason: nullable(r.review_reason, label), operator_id: id(r.operator_id), operator_name: nullable(r.operator_name, label) };
}
function review(value: unknown): ExecutionReview {
  const r = object(value); return { id: id(r.id), session_id: id(r.session_id), action: choice(r.action, ['confirm_finished', 'void']), reported_finished_at: nullable(r.reported_finished_at, at),
    effort_minutes: nullable(r.effort_minutes, v => integer(v, 1000000)), note: nullable(r.note, v => label(v, 1000)), reason: label(r.reason), actor_name: nullable(r.actor_name, label), created_at: at(r.created_at) };
}
function rows<T>(value: unknown, limit: number, parse: (value: unknown) => T): T[] { if (!Array.isArray(value) || value.length > limit) throw invalid(); return value.map(parse); }
export function parseExecutionSnapshot(value: unknown, operatorId: string, allocationId: string): ExecutionSnapshot {
  const r = object(value), a = object(r.allocation);
  const result: ExecutionSnapshot = { as_of: at(r.as_of), operator_id: id(r.operator_id), allocation: { id: id(a.id), project_id: id(a.project_id), cell_id: id(a.cell_id), numero_projeto: nullable(a.numero_projeto, label), cell_name: nullable(a.cell_name, label),
    status: nullable(a.status, label), retired: bool(a.retired), project_closed: bool(a.project_closed), visible: bool(a.visible), blocked: bool(a.blocked), updated_at: at(a.updated_at) },
    running_session: nullable(r.running_session, summary), session: nullable(r.session, summary), review_sessions: rows(r.review_sessions, 50, summary), review_sessions_total: integer(r.review_sessions_total), review_sessions_complete: bool(r.review_sessions_complete),
    events: rows(r.events, 200, event), events_total: integer(r.events_total), events_complete: bool(r.events_complete), reviews: rows(r.reviews, 100, review), reviews_total: integer(r.reviews_total), reviews_complete: bool(r.reviews_complete) };
  if (result.operator_id !== operatorId || result.allocation.id !== allocationId || result.session && (result.session.operator_id !== operatorId || result.session.allocation_id !== allocationId)
    || result.running_session && result.running_session.operator_id !== operatorId || result.review_sessions.some(s => s.operator_id !== operatorId || s.allocation_id !== allocationId)
    || result.events.some(e => e.operator_id !== operatorId)) throw invalid();
  for (const [items, total, complete] of [[result.events, result.events_total, result.events_complete], [result.reviews, result.reviews_total, result.reviews_complete], [result.review_sessions, result.review_sessions_total, result.review_sessions_complete]] as const) {
    if (new Set(items.map(item => item.id)).size !== items.length || total < items.length || complete && total !== items.length) throw invalid();
  }
  return result;
}
export function parseExecutionReceipt(value: unknown): ExecutionReceipt {
  const r = object(value); return { event_id: id(r.event_id), session_id: id(r.session_id), disposition: choice(r.disposition, ['accepted', 'review']), review_reason: nullable(r.review_reason, label), received_at: at(r.received_at), idempotent_replay: bool(r.idempotent_replay) };
}
export function parseExecutionParams(value: unknown): ExecutionParams {
  const r = object(value); const parsed: ExecutionParams = { p_session_id: id(r.p_session_id), p_allocation_id: id(r.p_allocation_id), p_previous_event_id: nullable(r.p_previous_event_id, id), p_kind: choice(r.p_kind, ['start', 'pause', 'resume', 'finish']),
    p_occurred_at: at(r.p_occurred_at), p_pause_reason: nullable(r.p_pause_reason, v => choice(v, PAUSE_REASONS)), p_note: nullable(r.p_note, v => label(v, 1000)), p_effort_minutes: nullable(r.p_effort_minutes, v => integer(v, 1000000)) };
  if (parsed.p_kind === 'start' && parsed.p_previous_event_id !== null || parsed.p_kind !== 'start' && parsed.p_previous_event_id === null || parsed.p_kind === 'pause' && !parsed.p_pause_reason
    || parsed.p_kind !== 'pause' && parsed.p_pause_reason !== null || parsed.p_kind !== 'finish' && parsed.p_effort_minutes !== null
    || parsed.p_kind === 'pause' && parsed.p_pause_reason === 'outro' && (parsed.p_note?.trim().length ?? 0) < 3) throw invalid();
  return parsed;
}
export function executionCacheKey(owner: string, operatorId: string, allocationId: string, workshopId?: string) {
  return workshopId ? `execution:${owner}:${operatorId}:${workshopId}:${allocationId}` : `execution:${owner}:${operatorId}:${allocationId}`;
}
export function executionMinutes(input: string): number | null { const value = input.trim(); if (!/^\d{1,7}$/.test(value)) return null; const minutes = Number(value); return minutes <= 1000000 ? minutes : null; }
export function executionReviewReasonLabel(reason: string | null): string {
  switch (reason) {
    case 'missing_start': return 'O início deste apontamento não foi confirmado.';
    case 'unresolved_evidence': return 'Há registros anteriores deste apontamento aguardando conferência.';
    case 'after_management_review': return 'Este registro chegou após uma conferência da gestão.';
    case 'duplicate_start': return 'Já existe um início registrado para este apontamento.';
    case 'previous_event_mismatch': return 'A sequência recebida difere do último registro confirmado.';
    case 'invalid_transition': return 'A ação recebida não corresponde à situação confirmada do apontamento.';
    case 'allocation_changed': return 'As condições da etapa mudaram desde o registro no dispositivo.';
    case 'another_open_session': return 'Já existe outro apontamento aberto para esta etapa.';
    case 'operator_already_running': return 'Existe outro trabalho em andamento para este operador.';
    default: return 'O apontamento precisa ser conferido pela gestão.';
  }
}
export type ExecutionProjection = { session: ExecutionSummary | null; runningSession: ExecutionSummary | null; pending: number; reviewOperations: { id: string; reason: string }[]; localEvents: { id: string; params: ExecutionParams; status: string; error?: string }[]; uncertain: boolean };
/** The durable outbox is the only local intention journal. Completed review
 * receipts never become canonical execution, and other actors never project. */
export function projectExecution(snapshot: ExecutionSnapshot, operations: readonly OutboxRow[], postAckRead = true, contexts: ExecutionContexts = {}): ExecutionProjection {
  let selected = snapshot.session ? { ...snapshot.session } : null, running = snapshot.running_session ? { ...snapshot.running_session } : null;
  const known = new Set([...snapshot.events.map(e => e.id), snapshot.session?.last_event_id, snapshot.running_session?.last_event_id].filter((id): id is string => !!id)), reviewOperations: ExecutionProjection['reviewOperations'] = [], localEvents: ExecutionProjection['localEvents'] = [];
  let pending = 0, uncertain = false;
  const currentAllocationAllowsRecords = executionAllocationAllowsRecords(snapshot.allocation);
  // Only the cache boundary supplies these account/operator/ACK-checked contexts.
  // Keep paused foreign sessions as well as the running one while replaying FIFO.
  const sessions = new Map<string, ExecutionSummary>(), observedAt = new Map<string, string>();
  let runningObservedAt = snapshot.as_of;
  for (const context of Object.values(contexts)) {
    // This page's complete canonical snapshot always replaces its compact map
    // entry, including an explicit null session after management reconciliation.
    if (context.allocation.id === snapshot.allocation.id) continue;
    for (const eventId of context.known_event_ids) known.add(eventId);
    if (context.session) { sessions.set(context.session.id, { ...context.session }); observedAt.set(context.session.id, context.as_of); }
    // A read of A can confirm a start whose network ACK was lost while B's
    // cache is still older. Known-event skipping must retain that occupation.
    const newer = Date.parse(context.as_of) - Date.parse(runningObservedAt);
    if (newer > 0 || newer === 0 && context.running_session && !running) {
      running = context.running_session ? { ...context.running_session } : null; runningObservedAt = context.as_of;
    }
  }
  for (const [row, at] of [[selected, snapshot.as_of], [running, runningObservedAt]] as const) if (row && (!observedAt.has(row.id) || Date.parse(at) >= Date.parse(observedAt.get(row.id)!))) {
    sessions.set(row.id, row); observedAt.set(row.id, at);
  }
  const unresolvedSessions = new Set(snapshot.review_sessions.map(row => row.id));
  if (snapshot.session?.needs_review) unresolvedSessions.add(snapshot.session.id);
  for (const operation of operations) {
    if (operation.rpc_name !== EXECUTION_RPC || operation.actor_id !== snapshot.operator_id) continue;
    let params: ExecutionParams; let receipt: ExecutionReceipt | null = null;
    try { const raw = JSON.parse(operation.params_json); if (raw.p_operador_id !== operation.actor_id) { uncertain = true; continue; } params = parseExecutionParams(raw); if (operation.result_json) receipt = parseExecutionReceipt(JSON.parse(operation.result_json)); }
    catch { uncertain = true; continue; }
    const relevant = params.p_allocation_id === snapshot.allocation.id;
    if (relevant && operation.status !== 'completed') pending++;
    if (relevant) localEvents.push({ id: operation.id, params, status: operation.status, error: operation.last_error });
    if (receipt && (receipt.event_id !== operation.id || receipt.session_id !== params.p_session_id)) { uncertain = true; continue; }
    if (receipt?.disposition === 'review') { if (relevant && (!postAckRead || unresolvedSessions.has(params.p_session_id) || !snapshot.review_sessions_complete)) reviewOperations.push({ id: operation.id, reason: executionReviewReasonLabel(receipt.review_reason) }); continue; }
    // Completed commands are never replayed over a canonical read. The cache
    // ACK epoch separately requires a post-ACK read before actions are enabled.
    if (operation.status === 'completed' || known.has(operation.id)) continue;
    const context = relevant ? { as_of: snapshot.as_of, allocation: snapshot.allocation, session: snapshot.session, running_session: snapshot.running_session, review_session_ids: snapshot.review_sessions.map(row => row.id), known_event_ids: [] } : contexts[params.p_allocation_id];
    let current = sessions.get(params.p_session_id) ?? null;
    if (params.p_kind === 'start') {
      if (current) { uncertain = true; continue; } // An unknown duplicate start never reopens a server session.
      const open = [...sessions.values()].some(row => row.allocation_id === params.p_allocation_id && ['running', 'paused'].includes(row.state));
      if (running || context && (!executionAllocationAllowsRecords(context.allocation) || open)) { uncertain = true; continue; }
      if (!context) uncertain = true;
      current = { id: params.p_session_id, allocation_id: params.p_allocation_id, project_id: context?.allocation.project_id ?? '', cell_id: context?.allocation.cell_id ?? '', numero_projeto: context?.allocation.numero_projeto ?? null, cell_name: context?.allocation.cell_name ?? null,
        operator_id: snapshot.operator_id, operator_name: null, state: 'running', needs_review: false, last_event_id: operation.id, last_captured_at: params.p_occurred_at, last_received_at: receipt?.received_at ?? null, version: '', confirmed_minutes: null, effort_source: null, clock_warning: false, has_review: false, can_record: !!context && executionAllocationAllowsRecords(context.allocation) };
      observedAt.set(current.id, context?.as_of ?? snapshot.as_of);
    } else {
      // A command the server is known to retain for review cannot release its
      // accepted running work locally. Foreign context uses its own summary.
      const contextIsNewer = !!current && !!context && Date.parse(context.as_of) > Date.parse(observedAt.get(current.id) ?? snapshot.as_of);
      const canRecord = contextIsNewer ? executionAllocationAllowsRecords(context!.allocation) : current?.can_record;
      if (current && (!canRecord || current.needs_review || current.has_review || context?.review_session_ids.includes(current.id) || relevant && !currentAllocationAllowsRecords
        || context && Date.parse(context.as_of) >= Date.parse(observedAt.get(current.id) ?? snapshot.as_of) && !executionAllocationAllowsRecords(context.allocation))) {
        if (current.state === 'running' && !running) running = current;
        uncertain = true; continue;
      }
      if (!current || current.last_event_id !== params.p_previous_event_id || params.p_kind === 'pause' && current.state !== 'running' || params.p_kind === 'resume' && current.state !== 'paused'
        || params.p_kind === 'finish' && !['running', 'paused'].includes(current.state) || params.p_kind === 'resume' && running && running.id !== current.id) { uncertain = true; continue; }
      current = { ...current, state: params.p_kind === 'pause' ? 'paused' : params.p_kind === 'resume' ? 'running' : 'finished', last_event_id: operation.id, last_captured_at: params.p_occurred_at, last_received_at: receipt?.received_at ?? null,
        confirmed_minutes: params.p_kind === 'finish' ? params.p_effort_minutes : current.confirmed_minutes, effort_source: params.p_kind === 'finish' && params.p_effort_minutes !== null ? 'operator' : current.effort_source };
    }
    sessions.set(current.id, current);
    if (relevant) selected = current;
    if (current.state === 'running') running = current; else if (running?.id === current.id) running = null;
  }
  return { session: selected, runningSession: running, pending, reviewOperations, localEvents: localEvents.filter(row => !known.has(row.id)), uncertain };
}
