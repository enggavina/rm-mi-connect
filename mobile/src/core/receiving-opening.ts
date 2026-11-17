import { retryDelay } from './sync-policy';
import type { OutboxRow } from './types';

export const RECEIVING_OPEN_RPC = 'rm_mobile_open_receiving_v1' as const;
export type ReceivingOpeningReceipt = { projeto_id: string; equipamento_id: string; receiving_id: string; opening_created: boolean; attachments_pending: boolean; idempotent_replay: boolean };
export type ReceivingOpeningState = { schema: 1; owner: string; actor: string; receivingId: string; receipt: ReceivingOpeningReceipt | null; attempts: number; nextRetryAt: number; error: string | null; updatedAt: string };
export const receivingOpeningKey = (owner: string, actor: string, id: string) => `receiving-opening:${owner}:${actor}:${id}`;
const uuid = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const invalid = () => new Error('A abertura não pôde ser confirmada. O recebimento original permanece salvo para nova tentativa.');
export function receivingOpeningParams(row: OutboxRow): Record<string, unknown> {
  const raw: unknown = JSON.parse(row.params_json);
  if (row.rpc_name !== 'rm_submit_recebimento_v1' || !uuid(row.id) || !uuid(row.actor_id) || !raw || typeof raw !== 'object' || Array.isArray(raw)) throw invalid();
  const params = raw as Record<string, unknown>;
  if (params.p_operador_id !== row.actor_id || params.p_receiving_draft_id !== undefined && params.p_receiving_draft_id !== row.id) throw invalid();
  return params; // Exact frozen envelope, including unresolved local media.
}
export function parseReceivingOpeningReceipt(value: unknown, receivingId: string): ReceivingOpeningReceipt {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw invalid();
  const r = value as ReceivingOpeningReceipt;
  if (!uuid(r.projeto_id) || !uuid(r.equipamento_id) || r.receiving_id !== receivingId || !uuid(r.receiving_id)
    || typeof r.opening_created !== 'boolean' || typeof r.attachments_pending !== 'boolean' || typeof r.idempotent_replay !== 'boolean'
    || r.opening_created && !r.attachments_pending) throw invalid();
  return { projeto_id: r.projeto_id, equipamento_id: r.equipamento_id, receiving_id: r.receiving_id, opening_created: r.opening_created, attachments_pending: r.attachments_pending, idempotent_replay: r.idempotent_replay };
}
export function parseReceivingOpeningState(value: unknown, owner: string, actor: string, id: string): ReceivingOpeningState | null {
  if (value === null) return null;
  const r = value as ReceivingOpeningState;
  if (!r || r.schema !== 1 || r.owner !== owner || r.actor !== actor || r.receivingId !== id || !Number.isSafeInteger(r.attempts) || r.attempts < 0
    || !Number.isSafeInteger(r.nextRetryAt) || r.nextRetryAt < 0 || r.error !== null && typeof r.error !== 'string' || typeof r.updatedAt !== 'string' || !Number.isFinite(Date.parse(r.updatedAt))) throw invalid();
  return { schema: 1, owner, actor, receivingId: id, receipt: r.receipt === null ? null : parseReceivingOpeningReceipt(r.receipt, id), attempts: r.attempts, nextRetryAt: r.nextRetryAt, error: r.error, updatedAt: r.updatedAt };
}
export interface ReceivingOpeningSql {
  getFirstAsync<T>(query: string, ...values: (string | number | null)[]): Promise<T | null>;
  runAsync(query: string, ...values: (string | number | null)[]): Promise<unknown>;
}
/** Caller owns an exclusive write transaction and guards the current account.
 * An opening ACK is separate evidence, never completion of photos/documents. */
export async function storeReceivingOpening(db: ReceivingOpeningSql, row: OutboxRow, state: ReceivingOpeningState): Promise<void> {
  const parsed = parseReceivingOpeningState(state, state.owner, row.actor_id, row.id)!;
  receivingOpeningParams(row);
  const existing = await db.getFirstAsync<{ rpc_name: string; params_json: string; actor_id: string }>('SELECT o.rpc_name,o.params_json,m.actor_id FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.id=?', row.id);
  if (!existing || existing.rpc_name !== row.rpc_name || existing.params_json !== row.params_json || existing.actor_id !== row.actor_id) throw invalid();
  await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', receivingOpeningKey(state.owner, row.actor_id, row.id), JSON.stringify(parsed));
}
type OpeningWorker = { promise: Promise<void>; again: boolean; force: boolean };
export class ReceivingOpeningCoordinator {
  private workers = new Map<string, OpeningWorker>();
  constructor(private io: {
    assertOwner(owner: string): void;
    list(): Promise<OutboxRow[]>;
    read(owner: string, row: OutboxRow): Promise<ReceivingOpeningState | null>;
    write(row: OutboxRow, state: ReceivingOpeningState): Promise<void>;
    send(owner: string, row: OutboxRow, params: Record<string, unknown>): Promise<unknown>;
    now?: () => number;
  }) {}
  run(owner: string, force = false): Promise<void> {
    const prior = this.workers.get(owner);
    if (prior) { prior.again = true; prior.force ||= force; return prior.promise; }
    const worker: OpeningWorker = { promise: Promise.resolve(), again: true, force };
    worker.promise = this.drain(owner, worker).finally(() => { this.workers.delete(owner); });
    this.workers.set(owner, worker); return worker.promise;
  }
  private async drain(owner: string, worker: OpeningWorker) {
    const now = this.io.now ?? Date.now;
    while (worker.again) {
      worker.again = false; const force = worker.force; worker.force = false;
      this.io.assertOwner(owner);
      for (const row of await this.io.list()) {
        if (row.rpc_name !== 'rm_submit_recebimento_v1' || row.status === 'completed') continue;
        this.io.assertOwner(owner);
        const prior = await this.io.read(owner, row);
        this.io.assertOwner(owner);
        if (prior?.receipt || !force && (prior?.nextRetryAt ?? 0) > now()) continue;
        let next: ReceivingOpeningState;
        try {
          const params = receivingOpeningParams(row), response = await this.io.send(owner, row, params);
          this.io.assertOwner(owner);
          next = { schema: 1, owner, actor: row.actor_id, receivingId: row.id, receipt: parseReceivingOpeningReceipt(response, row.id), attempts: prior?.attempts ?? 0, nextRetryAt: 0, error: null, updatedAt: new Date(now()).toISOString() };
        } catch (error) {
          this.io.assertOwner(owner);
          const attempts = (prior?.attempts ?? 0) + 1;
          const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
          const delay = ['28000', '42501', 'P0002', 'PT409', 'PT410', 'PGRST202'].includes(code) ? 300_000 : retryDelay(attempts);
          next = { schema: 1, owner, actor: row.actor_id, receivingId: row.id, receipt: null, attempts, nextRetryAt: now() + delay, error: error instanceof Error ? error.message : String((error as { message?: unknown })?.message ?? 'A abertura permanece pendente.'), updatedAt: new Date(now()).toISOString() };
        }
        this.io.assertOwner(owner); await this.io.write(row, next); this.io.assertOwner(owner);
      }
    }
  }
}
