import { parseExecutionSnapshot, type ExecutionSnapshot } from './execution';
import type { OutboxRow } from './types';

export type ExecutionScope = { owner: string; operatorId: string; allocationId: string };
// ack is the server-evidence fence: an ACK or an authoritative refusal requires
// a subsequent successful read before another action can use an old cache.
export type ExecutionEpoch = { intent: number; ack: number };
export type ExecutionCache = { schema: 1; scope: ExecutionScope; epoch: ExecutionEpoch; snapshot: ExecutionSnapshot };
export type ExecutionLocalView = { snapshot: ExecutionSnapshot | null; safeToAppend: boolean; epoch: ExecutionEpoch; operations: OutboxRow[] };
export const executionEpochKey = (owner: string, actor: string) => `execution-epoch:${owner}:${actor}`;
export function executionEpoch(value: unknown): ExecutionEpoch {
  if (value === null) return { intent: 0, ack: 0 };
  const r = value as ExecutionEpoch;
  if (!r || !Number.isSafeInteger(r.intent) || r.intent < 0 || !Number.isSafeInteger(r.ack) || r.ack < 0) throw new Error('A revisão local dos apontamentos não pôde ser validada. Seus registros foram preservados.');
  return { intent: r.intent, ack: r.ack };
}
export const sameExecutionEpoch = (a: ExecutionEpoch, b: ExecutionEpoch) => a.intent === b.intent && a.ack === b.ack;
export const sameExecutionScope = (a: ExecutionScope, b: ExecutionScope) => a.owner === b.owner && a.operatorId === b.operatorId && a.allocationId === b.allocationId;
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
export function executionLocalView(cache: ExecutionCache | null, current: ExecutionEpoch, operations: OutboxRow[]): ExecutionLocalView {
  return { snapshot: cache?.snapshot ?? null, safeToAppend: !!cache && cache.epoch.ack === current.ack, epoch: { ...current }, operations };
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
