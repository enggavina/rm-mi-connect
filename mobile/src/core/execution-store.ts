import { canonicalJson } from './sync-policy';
import { EXECUTION_RPC, parseExecutionParams, parseExecutionReceipt, type ExecutionReceipt } from './execution';
import { advanceExecutionEpoch, executionEpoch, executionEpochKey, executionReadRefused } from './execution-cache';

export interface ExecutionSql {
  getFirstAsync<T>(sql: string, ...params: (string | number | null)[]): Promise<T | null>;
  runAsync(sql: string, ...params: (string | number | null)[]): Promise<unknown>;
}
async function advance(db: ExecutionSql, owner: string, actor: string, kind: 'intent' | 'ack') {
  const key = executionEpochKey(owner, actor), row = await db.getFirstAsync<{ value: string }>('SELECT value FROM local_meta WHERE key=?', key);
  const next = advanceExecutionEpoch(executionEpoch(row ? JSON.parse(row.value) : null), kind);
  await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', key, JSON.stringify(next));
}
export function invalidateExecutionRead(db: ExecutionSql, owner: string, actor: string) { return advance(db, owner, actor, 'ack'); }
/** Caller owns one exclusive SQLite transaction. Epoch and journal must commit
 * together so a crash can never leave a false cache certificate. */
export async function storeExecutionIntention(db: ExecutionSql, value: { id: string; owner: string; actor: string; tokenKey: string; params: Record<string, unknown>; createdAt: string }) {
  if (value.params.p_operador_id !== value.actor) throw new Error('Identidade do apontamento divergente.');
  parseExecutionParams(value.params);
  const existing = await db.getFirstAsync<{ rpc_name: string; params_json: string; actor_id: string }>('SELECT o.rpc_name,o.params_json,m.actor_id FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.id=?', value.id);
  if (existing) {
    if (existing.rpc_name !== EXECUTION_RPC || existing.actor_id !== value.actor || canonicalJson(JSON.parse(existing.params_json)) !== canonicalJson(value.params)) throw new Error('O protocolo já foi usado com outro apontamento.');
    return false;
  }
  await db.runAsync('INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES (?,?,?,?)', value.id, EXECUTION_RPC, JSON.stringify(value.params), value.createdAt);
  await db.runAsync('INSERT INTO local_queue_meta(id,actor_id,token_key,draft_id) VALUES (?,?,?,NULL)', value.id, value.actor, value.tokenKey);
  await advance(db, value.owner, value.actor, 'intent');
  return true;
}
export async function storeExecutionAck(db: ExecutionSql, owner: string, actor: string, eventId: string, input: ExecutionReceipt) {
  const receipt = parseExecutionReceipt(input);
  const row = await db.getFirstAsync<{ rpc_name: string; params_json: string; status: string; actor_id: string }>('SELECT o.rpc_name,o.params_json,o.status,m.actor_id FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.id=?', eventId);
  if (!row || row.rpc_name !== EXECUTION_RPC || row.actor_id !== actor || receipt.event_id !== eventId || receipt.session_id !== JSON.parse(row.params_json).p_session_id) throw new Error('Confirmação de apontamento divergente. O protocolo original foi preservado.');
  if (row.status === 'completed') return false;
  await db.runAsync("UPDATE local_rpc_outbox SET status='completed',last_error=NULL WHERE id=?", eventId);
  await db.runAsync('UPDATE local_queue_meta SET result_json=? WHERE id=?', JSON.stringify(receipt), eventId);
  await advance(db, owner, actor, 'ack');
  return true;
}
/** A refused write is authoritative evidence too. Keep the original command
 * intact, and invalidate its original author's caches in the failed-write tx. */
export async function storeExecutionFailure(db: ExecutionSql, value: { owner: string; actor: string; eventId: string; error: unknown; message: string; nextRetryAt: number }) {
  const row = await db.getFirstAsync<{ rpc_name: string; actor_id: string }>('SELECT o.rpc_name,m.actor_id FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.id=?', value.eventId);
  if (!row || row.rpc_name !== EXECUTION_RPC || row.actor_id !== value.actor) throw new Error('O envio pertence a outro contexto. O protocolo foi preservado.');
  await db.runAsync("UPDATE local_rpc_outbox SET status='failed',attempts=attempts+1,last_error=? WHERE id=?", value.message, value.eventId);
  await db.runAsync('UPDATE local_queue_meta SET next_retry_at=? WHERE id=?', value.nextRetryAt, value.eventId);
  const fenced = executionReadRefused(value.error);
  if (fenced) await advance(db, value.owner, value.actor, 'ack');
  return fenced;
}
