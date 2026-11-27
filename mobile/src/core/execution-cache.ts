import { executionCacheKey, parseExecutionParams, parseExecutionSnapshot, type ExecutionContexts, type ExecutionSnapshot } from './execution';
import type { OutboxRow } from './types';

export type ExecutionScope = { owner: string; operatorId: string; allocationId: string; workshopId?: string };
// ack is the server-evidence fence: an ACK or an authoritative refusal requires
// a subsequent successful read before another action can use an old cache.
export type ExecutionEpoch = { intent: number; ack: number };
export type ExecutionCache = { schema: 1; scope: ExecutionScope; epoch: ExecutionEpoch; snapshot: ExecutionSnapshot };
export type ExecutionLocalView = { snapshot: ExecutionSnapshot | null; safeToAppend: boolean; epoch: ExecutionEpoch; operations: OutboxRow[]; contexts: ExecutionContexts };
/** Select only execution metadata and event IDs: photo/form text and full
 * execution histories never cross the foreign-allocation context boundary. */
export const EXECUTION_CONTEXT_SQL = `SELECT key,json_object('schema',json_extract(value,'$.schema'),'scope',json_extract(value,'$.scope'),'epoch',json_extract(value,'$.epoch'),
  'snapshot',json_object('as_of',json_extract(value,'$.snapshot.as_of'),'operator_id',json_extract(value,'$.snapshot.operator_id'),
    'allocation',json_extract(value,'$.snapshot.allocation'),'session',json_extract(value,'$.snapshot.session'),
    'running_session',json_extract(value,'$.snapshot.running_session'),'review_sessions',json_extract(value,'$.snapshot.review_sessions'),
    'review_sessions_total',json_extract(value,'$.snapshot.review_sessions_total'),'review_sessions_complete',json(CASE json_type(value,'$.snapshot.review_sessions_complete') WHEN 'true' THEN 'true' WHEN 'false' THEN 'false' ELSE 'null' END),
    'events',json('[]'),'events_total',0,'events_complete',json('true'),'reviews',json('[]'),'reviews_total',0,'reviews_complete',json('true')),
  'known_event_ids',json((SELECT json_group_array(json_extract(e.value,'$.id')) FROM json_each(local_meta.value,'$.snapshot.events') e))) value
  FROM local_meta WHERE key IN (SELECT value FROM json_each(?)) AND json_valid(value)`;
export const EXECUTION_OPERATIONS_SQL = `SELECT o.*,m.next_retry_at,m.actor_id,m.token_key,m.draft_id,m.result_json,m.workshop_id
  FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.rpc_name=? AND m.actor_id=? AND
  (? IS NULL OR m.workshop_id=?) AND
  (o.status<>'completed' OR o.rowid IN(SELECT p.rowid FROM local_rpc_outbox p JOIN local_queue_meta a USING(id)
   WHERE p.rpc_name=? AND a.actor_id=? AND (? IS NULL OR a.workshop_id=?) AND p.status='completed'
   ORDER BY p.created_at DESC,p.rowid DESC LIMIT 200)) ORDER BY o.created_at,o.rowid`;
export function executionContextKeys(scope: ExecutionScope, cache: ExecutionCache | null, operations: readonly OutboxRow[]): string[] {
  const ids = new Set([scope.allocationId]);
  if (cache?.snapshot.running_session) ids.add(cache.snapshot.running_session.allocation_id);
  for (const row of operations) if (row.status !== 'completed' && row.actor_id === scope.operatorId) {
    try { const raw = JSON.parse(row.params_json); if (raw.p_operador_id === scope.operatorId) ids.add(parseExecutionParams(raw).p_allocation_id); } catch { /* Invalid own commands are fenced by the projector. */ }
  }
  return [...ids].map(id => executionCacheKey(scope.owner, scope.operatorId, id, scope.workshopId));
}
export function executionContexts(rows: readonly { key: string; value: string }[], scope: ExecutionScope, current: ExecutionEpoch): ExecutionContexts {
  const result: Record<string, ExecutionContexts[string]> = {};
  for (const row of rows) {
    try {
      const raw = JSON.parse(row.value), allocationId = raw?.scope?.allocationId;
      if (typeof allocationId !== 'string' || row.key !== executionCacheKey(scope.owner, scope.operatorId, allocationId, scope.workshopId)) continue;
      const cache = parseExecutionCache(raw, { ...scope, allocationId });
      if (!cache || cache.epoch.ack !== current.ack || cache.epoch.intent > current.intent) continue;
      const known: unknown[] = raw.known_event_ids ?? cache.snapshot.events.map(event => event.id);
      if (!Array.isArray(known) || known.length > 200 || known.some(value => typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))) continue;
      const snapshot = cache.snapshot;
      result[allocationId] = { as_of: snapshot.as_of, allocation: snapshot.allocation, session: snapshot.session, running_session: snapshot.running_session,
        review_session_ids: snapshot.review_sessions.map(session => session.id), known_event_ids: [...known as string[], ...(snapshot.session?.last_event_id ? [snapshot.session.last_event_id] : [])] };
    } catch { /* An invalid/foreign context grants no offline authority. */ }
  }
  return result;
}
export const executionEpochKey = (owner: string, actor: string) => `execution-epoch:${owner}:${actor}`;
export function executionEpoch(value: unknown): ExecutionEpoch {
  if (value === null) return { intent: 0, ack: 0 };
  const r = value as ExecutionEpoch;
  if (!r || !Number.isSafeInteger(r.intent) || r.intent < 0 || !Number.isSafeInteger(r.ack) || r.ack < 0) throw new Error('A revisão local dos apontamentos não pôde ser validada. Seus registros foram preservados.');
  return { intent: r.intent, ack: r.ack };
}
export const sameExecutionEpoch = (a: ExecutionEpoch, b: ExecutionEpoch) => a.intent === b.intent && a.ack === b.ack;
export const sameExecutionScope = (a: ExecutionScope, b: ExecutionScope) => a.owner === b.owner && a.operatorId === b.operatorId
  && a.allocationId === b.allocationId && a.workshopId === b.workshopId;
export function executionReadRefused(error: unknown): boolean {
  return !!error && typeof error === 'object' && 'code' in error && ['28000', '42501', 'P0002', 'PT410'].includes(String(error.code));
}
export function advanceExecutionEpoch(epoch: ExecutionEpoch, kind: 'intent' | 'ack'): ExecutionEpoch {
  return executionEpoch({ ...epoch, [kind]: epoch[kind] + 1 });
}
export function parseExecutionCache(value: unknown, scope: ExecutionScope): ExecutionCache | null {
  if (value === null) return null;
  const raw = value as ExecutionCache;
  if (!raw || raw.schema !== 1 || !raw.scope || !sameExecutionScope(raw.scope, scope)) throw new Error('O cache pertence a outro contexto de execução. Identifique o autor para consultar.');
  return { schema: 1, scope: { ...scope }, epoch: executionEpoch(raw.epoch), snapshot: parseExecutionSnapshot(raw.snapshot, scope.operatorId, scope.allocationId) };
}
/** Called inside the same SQLite write lane that owns enqueue and ACK. A
 * response started before either change cannot certify the current state. */
export function acceptExecutionRead(prior: ExecutionCache | null, current: ExecutionEpoch, ticket: ExecutionEpoch, snapshot: ExecutionSnapshot, scope: ExecutionScope): ExecutionCache | null {
  if (!sameExecutionEpoch(current, ticket)) return prior;
  if (prior && sameExecutionEpoch(prior.epoch, current) && Date.parse(prior.snapshot.as_of) >= Date.parse(snapshot.as_of)) return prior;
  return { schema: 1, scope: { ...scope }, epoch: { ...current }, snapshot };
}
export function executionLocalView(cache: ExecutionCache | null, current: ExecutionEpoch, operations: OutboxRow[], contexts: ExecutionContexts = {}): ExecutionLocalView {
  const safeToAppend = !!cache && cache.epoch.ack === current.ack;
  const snapshot = cache?.scope.workshopId && !safeToAppend ? null : cache?.snapshot ?? null;
  return { snapshot, safeToAppend, epoch: { ...current }, operations, contexts };
}
/** The ticket is captured before issuing the read. Commit must compare it
 * atomically, rather than trusting server/device wall-clock timestamps. */
export async function refreshExecutionRead(read: () => Promise<ExecutionLocalView>, transport: () => Promise<ExecutionSnapshot>, commit: (ticket: ExecutionEpoch, snapshot: ExecutionSnapshot) => Promise<ExecutionLocalView>) {
  const initial = await read();
  const snapshot = await transport();
  return commit(initial.epoch, snapshot);
}
export function newestExecutionView(current: ExecutionLocalView | null, incoming: ExecutionLocalView): ExecutionLocalView {
  if (current && (incoming.epoch.intent < current.epoch.intent || incoming.epoch.ack < current.epoch.ack)) return current;
  if (current && sameExecutionEpoch(current.epoch, incoming.epoch) && current.snapshot && incoming.snapshot && Date.parse(incoming.snapshot.as_of) < Date.parse(current.snapshot.as_of)) return current;
  return incoming;
}
