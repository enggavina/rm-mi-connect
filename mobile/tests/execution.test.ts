import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, dirname, basename } from 'node:path';
import { existsSync, unlinkSync } from 'node:fs';
import { RM_MOBILE_SQLITE_DDL } from '../src/core/schema';
import { QUEUE_EXECUTION_MIGRATION } from '../src/core/execution-queue-migration';
import { QUEUE_WORKSHOP_MIGRATION } from '../src/core/workshop-queue-migration';
import { EXECUTION_RPC, executionCacheKey, executionMinutes, executionReviewReasonLabel, parseExecutionParams, parseExecutionReceipt, parseExecutionSnapshot, projectExecution, type ExecutionSnapshot, type ExecutionSummary, type ExecutionParams } from '../src/core/execution';
import { EXECUTION_CONTEXT_SQL, acceptExecutionRead, executionContextKeys, executionContexts, executionEpoch, executionEpochKey, executionLocalView, executionReadRefused, newestExecutionView, parseExecutionCache, refreshExecutionRead, type ExecutionCache, type ExecutionEpoch, type ExecutionLocalView } from '../src/core/execution-cache';
import { invalidateExecutionRead, storeExecutionAck, storeExecutionFailure, storeExecutionIntention, type ExecutionSql } from '../src/core/execution-store';
import type { OutboxRow } from '../src/core/types';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const actor = id(3), owner = id(4), allocation = id(1), scope = { owner, operatorId: actor, allocationId: allocation };
const stamp = '2026-11-17T10:01:00.123456+00:00';
const parameters = (patch: Partial<ExecutionParams> = {}): ExecutionParams => ({ p_session_id: id(10), p_allocation_id: allocation, p_previous_event_id: null, p_kind: 'start', p_occurred_at: '2026-11-17T10:00:00.000Z', p_pause_reason: null, p_note: null, p_effort_minutes: null, ...patch });
function session(patch: Partial<ExecutionSummary> = {}): ExecutionSummary { return { id: id(10), allocation_id: allocation, project_id: id(2), cell_id: id(5), numero_projeto: 'OS local', cell_name: 'Ensaios', operator_id: actor, operator_name: 'Operador local', state: 'running', needs_review: false, last_event_id: id(20), last_captured_at: '2026-11-17T10:00:00Z', last_received_at: '2026-11-17T10:00:01Z', version: 'a'.repeat(64), confirmed_minutes: null, effort_source: null, clock_warning: false, has_review: false, can_record: true, ...patch }; }
function snapshot(patch: Partial<ExecutionSnapshot> = {}): ExecutionSnapshot { return { as_of: stamp, operator_id: actor, allocation: { id: allocation, project_id: id(2), cell_id: id(5), numero_projeto: 'OS local', cell_name: 'Ensaios', status: 'em_dia', retired: false, project_closed: false, visible: true, blocked: false, updated_at: stamp }, running_session: null, session: null, review_sessions: [], review_sessions_total: 0, review_sessions_complete: true, events: [], events_total: 0, events_complete: true, reviews: [], reviews_total: 0, reviews_complete: true, ...patch }; }
function operation(n = 20, p = parameters(), status = 'pending'): OutboxRow { return { id: id(n), rpc_name: EXECUTION_RPC, actor_id: actor, token_key: 'secure-token-reference', draft_id: null, status, attempts: 0, created_at: stamp, next_retry_at: 0, params_json: JSON.stringify({ ...p, p_operador_id: actor }) }; }
const ack = (n = 20, disposition: 'accepted' | 'review' = 'accepted') => ({ event_id: id(n), session_id: id(10), disposition, review_reason: disposition === 'review' ? 'Conferir a sequência recebida.' : null, received_at: '2026-11-17T10:00:00.000Z', idempotent_replay: false });
function setup(file = ':memory:', v2 = false) {
  const db = new DatabaseSync(file);
  db.exec(v2 ? RM_MOBILE_SQLITE_DDL.replace("      'rm_add_cell_comment_v1',\n      'rm_record_execution_event_v1'", "      'rm_add_cell_comment_v1'") : RM_MOBILE_SQLITE_DDL);
  db.exec(`CREATE TABLE IF NOT EXISTS local_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS local_queue_meta(id TEXT PRIMARY KEY,next_retry_at INTEGER NOT NULL DEFAULT 0,actor_id TEXT,token_key TEXT,draft_id TEXT,result_json TEXT);
    CREATE INDEX IF NOT EXISTS idx_local_outbox_pending ON local_rpc_outbox(status,created_at);`);
  return db;
}
function sql(db: DatabaseSync): ExecutionSql { return { getFirstAsync: async <T>(query: string, ...values: (string | number | null)[]) => (db.prepare(query).get(...values) ?? null) as T | null, runAsync: async (query, ...values) => db.prepare(query).run(...values) }; }
async function transaction<T>(db: DatabaseSync, work: (adapter: ExecutionSql) => Promise<T>) { db.exec('BEGIN'); try { const result = await work(sql(db)); db.exec('COMMIT'); return result; } catch (error) { db.exec('ROLLBACK'); throw error; } }
const intention = (n = 20, p = parameters()) => ({ id: id(n), owner, actor, tokenKey: 'secure-token-reference', params: { ...p, p_operador_id: actor }, createdAt: stamp });

test('execution queue v3 preserves authors, payloads, retries, results and equal-time FIFO while adding one RPC', () => {
  const db = setup(':memory:', true);
  for (const [n, state] of [[30, 'failed'], [1, 'pending'], [12, 'completed']] as const) {
    db.prepare('INSERT INTO local_rpc_outbox(id,rpc_name,params_json,status,attempts,last_error,created_at) VALUES(?,?,?,?,?,?,?)').run(id(n), 'rm_add_cell_comment_v1', JSON.stringify({ note: `Original ${n}` }), state, n, 'Preservado', stamp);
    db.prepare('INSERT INTO local_queue_meta(id,actor_id,token_key,draft_id,next_retry_at,result_json) VALUES(?,?,?,?,?,?)').run(id(n), actor, `ref-${n}`, id(100 + n), n * 10, '{"original":true}');
  }
  const before = db.prepare('SELECT * FROM local_rpc_outbox ORDER BY created_at,rowid').all(), meta = db.prepare('SELECT * FROM local_queue_meta ORDER BY id').all();
  db.exec(`BEGIN;${QUEUE_EXECUTION_MIGRATION}COMMIT;`);
  assert.deepEqual(db.prepare('SELECT * FROM local_rpc_outbox ORDER BY created_at,rowid').all(), before);
  assert.deepEqual(db.prepare('SELECT * FROM local_queue_meta ORDER BY id').all(), meta);
  db.prepare('INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES(?,?,?,?)').run(id(99), EXECUTION_RPC, '{}', stamp);
  assert.equal(db.prepare('SELECT value FROM local_meta WHERE key=?').get('queue_schema_version')?.value, '3'); db.close();
});

test('queue v4 adds workshop provenance without assigning or rewriting existing offline work', async () => {
  const db = setup();
  try {
    db.exec(QUEUE_EXECUTION_MIGRATION);
    await transaction(db, adapter => storeExecutionIntention(adapter, intention()));
    await transaction(db, adapter => storeExecutionFailure(adapter, { owner, actor, eventId: id(20), error: new Error('Offline'), message: 'Offline', nextRetryAt: 42 }));
    const outbox = db.prepare('SELECT * FROM local_rpc_outbox').get();
    const metadata = db.prepare('SELECT * FROM local_queue_meta').get();
    db.exec(`BEGIN;${QUEUE_WORKSHOP_MIGRATION}COMMIT;`);
    assert.deepEqual(db.prepare('SELECT * FROM local_rpc_outbox').get(), outbox);
    assert.deepEqual({ ...db.prepare('SELECT * FROM local_queue_meta').get() }, { ...metadata, workshop_id: null });
    await transaction(db, async adapter => {
      await storeExecutionIntention(adapter, intention(21));
      await adapter.runAsync('UPDATE local_queue_meta SET workshop_id=? WHERE id=?', id(88), id(21));
    });
    assert.equal(db.prepare('SELECT workshop_id FROM local_queue_meta WHERE id=?').get(id(21))?.workshop_id, id(88));
    assert.equal(db.prepare('SELECT value FROM local_meta WHERE key=?').get('queue_schema_version')?.value, '4');
  } finally { db.close(); }
});
test('failed queue v3 upgrade rolls back all old protocols and the original allowlist', () => {
  const db = setup(':memory:', true); db.prepare('INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES(?,?,?,?)').run(id(2), 'rm_record_cell_photo_v1', '{"file":"file:///original.jpg"}', stamp);
  db.exec('BEGIN'); assert.throws(() => db.exec(`${QUEUE_EXECUTION_MIGRATION}INSERT INTO table_does_not_exist VALUES(1);`)); db.exec('ROLLBACK');
  assert.equal(db.prepare('SELECT params_json FROM local_rpc_outbox').get()?.params_json, '{"file":"file:///original.jpg"}');
  assert.throws(() => db.prepare('INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES(?,?,?,?)').run(id(99), EXECUTION_RPC, '{}', stamp)); db.close();
});
test('execution intentions and ACK epochs commit atomically, retain one protocol and do not reattribute on retry', async () => {
  const db = setup();
  await assert.rejects(transaction(db, adapter => storeExecutionIntention({ ...adapter, runAsync: async (query, ...values) => { if (query.startsWith('INSERT INTO local_queue_meta')) throw new Error('Simulated power loss'); return adapter.runAsync(query, ...values); } }, intention())), /power loss/);
  assert.equal(db.prepare('SELECT count(*) n FROM local_rpc_outbox').get()?.n, 0); assert.equal(db.prepare('SELECT count(*) n FROM local_meta').get()?.n, 0);
  assert.equal(await transaction(db, adapter => storeExecutionIntention(adapter, intention())), true);
  assert.equal(await transaction(db, adapter => storeExecutionIntention(adapter, intention())), false);
  await assert.rejects(transaction(db, adapter => storeExecutionIntention(adapter, { ...intention(), actor: id(77), params: { ...parameters(), p_operador_id: id(77) } })), /protocolo/);
  assert.deepEqual(JSON.parse(String(db.prepare('SELECT value FROM local_meta').get()?.value)), { intent: 1, ack: 0 });
  await assert.rejects(transaction(db, adapter => storeExecutionAck({ ...adapter, runAsync: async (query, ...values) => { if (query.startsWith('INSERT INTO local_meta')) throw new Error('ACK crash'); return adapter.runAsync(query, ...values); } }, owner, actor, id(20), ack())), /ACK crash/);
  assert.equal(db.prepare('SELECT status FROM local_rpc_outbox').get()?.status, 'pending'); assert.equal(db.prepare('SELECT result_json FROM local_queue_meta').get()?.result_json, null);
  await transaction(db, adapter => storeExecutionAck(adapter, owner, actor, id(20), ack()));
  assert.equal(await transaction(db, adapter => storeExecutionAck(adapter, owner, actor, id(20), { ...ack(), idempotent_replay: true })), false);
  assert.deepEqual(JSON.parse(String(db.prepare('SELECT value FROM local_meta').get()?.value)), { intent: 1, ack: 1 });
  await assert.rejects(transaction(db, adapter => storeExecutionAck(adapter, owner, id(77), id(20), ack())), /divergente/); db.close();
});

test('a read issued before ACK cannot overwrite the certificate after late completion, including restart and manager reconciliation', async () => {
  const file = join(tmpdir(), `em-execution-${randomUUID()}.sqlite`); let db = setup(file);
  const cacheKey = executionCacheKey(owner, actor, allocation), epochKey = executionEpochKey(owner, actor);
  try {
    await transaction(db, adapter => storeExecutionIntention(adapter, intention()));
    const old: ExecutionCache = { schema: 1, scope, epoch: { intent: 1, ack: 0 }, snapshot: snapshot() };
    db.prepare('INSERT INTO local_meta(key,value) VALUES(?,?)').run(cacheKey, JSON.stringify(old));
    function read(): ExecutionLocalView {
      const current = executionEpoch(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(epochKey)?.value)));
      const cache = parseExecutionCache(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(cacheKey)?.value)), scope);
      const operations = db.prepare('SELECT o.*,m.* FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) ORDER BY o.created_at,o.rowid').all() as unknown as OutboxRow[];
      return executionLocalView(cache, current, operations);
    }
    async function commit(ticket: ExecutionEpoch, next: ExecutionSnapshot) {
      const current = read(), prior = parseExecutionCache(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(cacheKey)?.value)), scope);
      const accepted = acceptExecutionRead(prior, current.epoch, ticket, next, scope);
      db.prepare('UPDATE local_meta SET value=? WHERE key=?').run(JSON.stringify(accepted), cacheKey); return read();
    }
    let release!: (value: ExecutionSnapshot) => void;
    const delayed = refreshExecutionRead(async () => read(), () => new Promise(resolve => { release = resolve; }), commit);
    await Promise.resolve();
    // Server received10:00, read snapshot10:01, transaction committed10:02.
    // Wall-clock comparison would incorrectly treat the ACK as included.
    await transaction(db, adapter => storeExecutionAck(adapter, owner, actor, id(20), ack()));
    release(snapshot()); const stale = await delayed;
    assert.equal(stale.safeToAppend, false); assert.equal(projectExecution(stale.snapshot!, stale.operations).session, null);
    db.close(); db = new DatabaseSync(file); const restarted = read(); assert.equal(restarted.safeToAppend, false);
    const running = session();
    const fresh = await refreshExecutionRead(async () => read(), async () => snapshot({ as_of: '2026-11-17T10:03:00Z', session: running, running_session: running }), commit);
    assert.equal(fresh.safeToAppend, true); assert.equal(projectExecution(fresh.snapshot!, fresh.operations).session?.state, 'running');
    const resolved = await refreshExecutionRead(async () => read(), async () => snapshot({ as_of: '2026-11-17T10:05:00Z', session: session({ state: 'finished', has_review: true, confirmed_minutes: 60, effort_source: 'manager' }) }), commit);
    assert.equal(projectExecution(resolved.snapshot!, resolved.operations).session?.state, 'finished');
    assert.equal(projectExecution(resolved.snapshot!, resolved.operations).runningSession, null);
  } finally {
    db.close(); assert.equal(dirname(file), tmpdir()); assert.match(basename(file), /^em-execution-[0-9a-f-]+\.sqlite$/);
    for (const suffix of ['', '-wal', '-shm']) if (existsSync(file + suffix)) unlinkSync(file + suffix);
  }
});
test('cache scope and read tickets cannot cross an operator, account, intention or ACK revision', () => {
  const cache: ExecutionCache = { schema: 1, scope, epoch: { intent: 1, ack: 0 }, snapshot: snapshot() };
  assert.throws(() => parseExecutionCache(cache, { ...scope, owner: id(77) }), /outro contexto/);
  assert.throws(() => parseExecutionCache(cache, { ...scope, operatorId: id(77) }), /outro contexto/);
  assert.equal(acceptExecutionRead(cache, { intent: 2, ack: 0 }, { intent: 1, ack: 0 }, snapshot(), scope), cache);
  const recent = executionLocalView(cache, { intent: 3, ack: 2 }, []), older = executionLocalView(cache, { intent: 2, ack: 1 }, []);
  assert.equal(newestExecutionView(recent, older), recent); assert.equal(recent.safeToAppend, false);
});
test('pending offline start pause resume finish project in FIFO without deriving effort or changing legacy data', () => {
  const operations = [operation(20), operation(21, parameters({ p_kind: 'pause', p_previous_event_id: id(20), p_pause_reason: 'maquina' })), operation(22, parameters({ p_kind: 'resume', p_previous_event_id: id(21) })), operation(23, parameters({ p_kind: 'finish', p_previous_event_id: id(22), p_effort_minutes: 0 }))];
  const source = snapshot(), frozen = JSON.stringify(source), result = projectExecution(source, operations);
  assert.equal(result.session?.state, 'finished'); assert.equal(result.session?.confirmed_minutes, 0); assert.equal(result.runningSession, null); assert.equal(result.pending, 4); assert.equal(JSON.stringify(source), frozen);
  assert.equal(projectExecution(source, operations.map(row => ({ ...row, actor_id: id(88) }))).session, null);
  const confused = { ...operation(), params_json: JSON.stringify({ ...parameters(), p_operador_id: id(88) }) };
  assert.equal(projectExecution(source, [confused]).uncertain, true); assert.equal(projectExecution(source, [confused]).session, null);
});
test('completed historical starts never reopen terminal sessions, while pending foreign starts never invent project or cell links', () => {
  const resolved = snapshot({ session: session({ state: 'void', has_review: true, last_event_id: null }) });
  const completed = { ...operation(), status: 'completed', result_json: JSON.stringify(ack()) };
  assert.equal(projectExecution(resolved, [completed]).session?.state, 'void'); assert.equal(projectExecution(resolved, [operation()]).session?.state, 'void');
  const paused = snapshot({ session: session({ state: 'paused' }) });
  const foreign = operation(30, parameters({ p_session_id: id(31), p_allocation_id: id(32) }));
  const result = projectExecution(paused, [foreign]); assert.equal(result.session?.state, 'paused'); assert.equal(result.runningSession?.allocation_id, id(32)); assert.equal(result.runningSession?.project_id, ''); assert.equal(result.runningSession?.cell_id, '');
});
test('review ACKs remain distinct from accepted execution and manager resolution clears current review alerts', () => {
  const completed = { ...operation(), status: 'completed', result_json: JSON.stringify(ack(20, 'review')) };
  const awaiting = snapshot({ review_sessions: [session({ state: 'review', needs_review: true })], review_sessions_total: 1 });
  const result = projectExecution(awaiting, [completed]); assert.equal(result.session, null); assert.equal(result.reviewOperations.length, 1); assert.equal(result.runningSession, null);
  assert.equal(projectExecution(snapshot(), [completed], false).reviewOperations.length, 1);
  assert.equal(projectExecution(snapshot(), [completed], true).reviewOperations.length, 0);
});
test('snapshot parsing strips unknown fields, rejects another actor and allows bounded empty tails without losing current state', () => {
  const current = session();
  const raw = { ...snapshot({ session: current, running_session: current, events_total: 300, events_complete: false, reviews_total: 120, reviews_complete: false, review_sessions_total: 60, review_sessions_complete: false }), private_token: 'must-not-cache' };
  const parsed = parseExecutionSnapshot(raw, actor, allocation);
  assert.equal(parsed.events.length, 0); assert.equal(parsed.session?.last_event_id, id(20)); assert.ok(!JSON.stringify(parsed).includes('must-not-cache'));
  assert.equal(projectExecution(parsed, [operation()]).session?.state, 'running');
  assert.throws(() => parseExecutionSnapshot({ ...raw, operator_id: id(77) }, actor, allocation));
  assert.throws(() => parseExecutionSnapshot({ ...raw, allocation: { ...raw.allocation, id: id(77) } }, actor, allocation));
  assert.throws(() => parseExecutionSnapshot({ ...raw, events_complete: true }, actor, allocation));
});
test('event requests and receipts preserve exact protocol IDs and reject malformed state, dates or partial-minute effort', () => {
  assert.equal(executionMinutes('0'), 0); assert.equal(executionMinutes('1000000'), 1000000); assert.equal(executionMinutes('1.5'), null); assert.equal(executionMinutes('1000001'), null);
  assert.equal(parseExecutionParams(parameters({ p_note: 'file:///é uma observação, não um upload' })).p_note, 'file:///é uma observação, não um upload');
  for (const patch of [{ p_kind: 'finish', p_previous_event_id: null }, { p_kind: 'pause', p_previous_event_id: id(20), p_pause_reason: null }, { p_kind: 'pause', p_previous_event_id: id(20), p_pause_reason: 'outro', p_note: ' ' }, { p_occurred_at: '2026-02-30T10:00:00Z' }, { p_occurred_at: '1899-01-01T10:00:00Z' }, { p_effort_minutes: 15 }, { p_note: 'x'.repeat(1001) }]) assert.throws(() => parseExecutionParams({ ...parameters(), ...patch }));
  assert.deepEqual(parseExecutionReceipt({ ...ack(), private: 'strip' }), ack());
  assert.throws(() => parseExecutionReceipt({ ...ack(), disposition: 'success' }));
});
test('operator-facing review explanations translate every current reason and never expose unknown internal codes', () => {
  for (const reason of ['missing_start', 'unresolved_evidence', 'after_management_review', 'duplicate_start', 'previous_event_mismatch', 'invalid_transition', 'allocation_changed', 'another_open_session', 'operator_already_running']) {
    const text = executionReviewReasonLabel(reason); assert.ok(text.length > 20); assert.ok(!text.includes(reason)); assert.ok(!text.includes('_'));
  }
  assert.equal(executionReviewReasonLabel('future_internal_reason'), executionReviewReasonLabel(null));
  assert.equal(executionReviewReasonLabel('constructor'), executionReviewReasonLabel(null));
  const receipt = { ...ack(20, 'review'), review_reason: 'operator_already_running' };
  const result = projectExecution(snapshot(), [{ ...operation(), status: 'completed', result_json: JSON.stringify(receipt) }], false);
  assert.equal(result.reviewOperations[0].reason, 'Existe outro trabalho em andamento para este operador.');
});
test('authoritative read refusal persistently fences cached writes while network failures preserve offline use', async () => {
  for (const code of ['28000', '42501', 'P0002', 'PT410']) assert.equal(executionReadRefused({ code }), true);
  for (const error of [{ message: 'Network request failed' }, { code: '57014' }, { status: 503 }, new Error('timeout')]) assert.equal(executionReadRefused(error), false);
  const file = join(tmpdir(), `em-execution-${randomUUID()}.sqlite`); let db = setup(file);
  try {
    const cache: ExecutionCache = { schema: 1, scope, epoch: { intent: 0, ack: 0 }, snapshot: snapshot() };
    db.prepare('INSERT INTO local_meta(key,value) VALUES(?,?)').run(executionCacheKey(owner, actor, allocation), JSON.stringify(cache));
    await transaction(db, adapter => invalidateExecutionRead(adapter, owner, actor));
    const current = executionEpoch(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(executionEpochKey(owner, actor))?.value)));
    assert.equal(executionLocalView(cache, current, []).safeToAppend, false);
    assert.equal(acceptExecutionRead(cache, current, { intent: 0, ack: 0 }, snapshot({ as_of: '2026-11-17T11:00:00Z' }), scope), cache);
    db.close(); db = new DatabaseSync(file);
    const persisted = executionEpoch(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(executionEpochKey(owner, actor))?.value)));
    assert.equal(executionLocalView(cache, persisted, []).safeToAppend, false);
    const renewed = acceptExecutionRead(cache, persisted, persisted, snapshot({ as_of: '2026-11-17T11:01:00Z' }), scope);
    assert.equal(executionLocalView(renewed, persisted, []).safeToAppend, true);
    assert.equal(db.prepare('SELECT count(*) n FROM local_rpc_outbox').get()?.n, 0);
  } finally {
    db.close(); assert.equal(dirname(file), tmpdir()); assert.match(basename(file), /^em-execution-[0-9a-f-]+\.sqlite$/);
    for (const suffix of ['', '-wal', '-shm']) if (existsSync(file + suffix)) unlinkSync(file + suffix);
  }
});
test('pending commands known to require review retain the accepted running session and mark projection uncertain', () => {
  for (const patch of [{ needs_review: true }, { has_review: true }, { can_record: false }]) for (const kind of ['pause', 'finish'] as const) {
    const running = session(patch), source = snapshot({ session: running, running_session: running });
    const pending = operation(21, parameters({ p_kind: kind, p_previous_event_id: id(20), p_pause_reason: kind === 'pause' ? 'material' : null }));
    const result = projectExecution(source, [pending]);
    assert.equal(result.session?.state, 'running'); assert.equal(result.runningSession?.id, running.id); assert.equal(result.uncertain, true);
  }
  const running = session();
  for (const patch of [{ project_closed: true }, { visible: false }, { blocked: true }, { retired: true }, { status: 'finalizado' }]) {
    const source = snapshot({ session: running, running_session: running }); source.allocation = { ...source.allocation, ...patch };
    const result = projectExecution(source, [operation(21, parameters({ p_kind: 'finish', p_previous_event_id: id(20) }))]);
    assert.equal(result.runningSession?.state, 'running'); assert.equal(result.uncertain, true);
  }
});
test('foreign pending transitions with unknown context are uncertain instead of silently enabling another start', () => {
  for (const kind of ['resume', 'pause', 'finish'] as const) {
    const unknown = operation(31, parameters({ p_session_id: id(80), p_allocation_id: id(81), p_kind: kind, p_previous_event_id: id(30), p_pause_reason: kind === 'pause' ? 'maquina' : null }));
    const result = projectExecution(snapshot(), [unknown]); assert.equal(result.runningSession, null); assert.equal(result.uncertain, true);
  }
  const foreign = session({ id: id(80), allocation_id: id(81), project_id: id(82), cell_id: id(83), can_record: false });
  const result = projectExecution(snapshot({ running_session: foreign }), [operation(31, parameters({ p_session_id: foreign.id, p_allocation_id: foreign.allocation_id, p_kind: 'pause', p_previous_event_id: foreign.last_event_id, p_pause_reason: 'maquina' }))]);
  assert.equal(result.runningSession?.id, foreign.id); assert.equal(result.uncertain, true);
});
test('a valid known foreign pause can precede an offline start in this allocation without inventing its context', () => {
  const foreign = session({ id: id(80), allocation_id: id(81), project_id: id(82), cell_id: id(83), can_record: true });
  const pause = operation(31, parameters({ p_session_id: foreign.id, p_allocation_id: foreign.allocation_id, p_kind: 'pause', p_previous_event_id: foreign.last_event_id, p_pause_reason: 'intervalo' }));
  const start = operation(32, parameters({ p_session_id: id(90) }));
  const result = projectExecution(snapshot({ running_session: foreign }), [pause, start]);
  assert.equal(result.uncertain, false); assert.equal(result.session?.id, id(90)); assert.equal(result.runningSession?.project_id, id(2)); assert.equal(result.runningSession?.cell_id, id(5));
});
test('authoritative failed writes fence the original queued author atomically while network failures retain offline capability', async () => {
  const file = join(tmpdir(), `em-execution-${randomUUID()}.sqlite`); let db = setup(file);
  try {
    await transaction(db, adapter => storeExecutionIntention(adapter, intention()));
    const before = db.prepare('SELECT params_json FROM local_rpc_outbox').get()?.params_json;
    await assert.rejects(transaction(db, adapter => storeExecutionFailure({ ...adapter, runAsync: async (query, ...values) => { if (query.startsWith('INSERT INTO local_meta')) throw new Error('Failure transaction interrupted'); return adapter.runAsync(query, ...values); } }, { owner, actor, eventId: id(20), error: { code: '42501' }, message: 'Acesso recusado', nextRetryAt: 100 })), /interrupted/);
    assert.equal(db.prepare('SELECT status FROM local_rpc_outbox').get()?.status, 'pending');
    for (const code of ['28000', '42501', 'P0002', 'PT410']) await transaction(db, adapter => storeExecutionFailure(adapter, { owner, actor, eventId: id(20), error: { code }, message: 'Recusa preservada', nextRetryAt: 100 }));
    const saved = executionEpoch(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(executionEpochKey(owner, actor))?.value)));
    assert.deepEqual(saved, { intent: 1, ack: 4 }); assert.equal(db.prepare('SELECT status FROM local_rpc_outbox').get()?.status, 'failed');
    assert.equal(db.prepare('SELECT params_json FROM local_rpc_outbox').get()?.params_json, before);
    assert.equal(db.prepare('SELECT value FROM local_meta WHERE key=?').get(executionEpochKey(owner, id(99))), undefined);
    await transaction(db, adapter => storeExecutionFailure(adapter, { owner, actor, eventId: id(20), error: new Error('Network request failed'), message: 'Sem conexão', nextRetryAt: 200 }));
    assert.deepEqual(executionEpoch(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(executionEpochKey(owner, actor))?.value))), saved);
    db.close(); db = new DatabaseSync(file);
    const restarted = executionEpoch(JSON.parse(String(db.prepare('SELECT value FROM local_meta WHERE key=?').get(executionEpochKey(owner, actor))?.value)));
    const cached: ExecutionCache = { schema: 1, scope, epoch: { intent: 1, ack: 0 }, snapshot: snapshot() };
    assert.equal(executionLocalView(cached, restarted, []).safeToAppend, false);
    assert.equal(acceptExecutionRead(cached, restarted, { intent: 1, ack: 0 }, snapshot({ as_of: '2026-11-17T11:30:00Z' }), scope), cached);
  } finally {
    db.close(); assert.equal(dirname(file), tmpdir()); assert.match(basename(file), /^em-execution-[0-9a-f-]+\.sqlite$/);
    for (const suffix of ['', '-wal', '-shm']) if (existsSync(file + suffix)) unlinkSync(file + suffix);
  }
});

test('previously consulted own SQLite contexts preserve a wholly offline start A, pause A, start B sequence', () => {
  const db = setup(), other = id(81), otherScope = { ...scope, allocationId: other };
  const a = snapshot({ allocation: { ...snapshot().allocation, id: other, project_id: id(82), cell_id: id(83), numero_projeto: 'OS A', cell_name: 'Mecânica' } });
  const cachedA: ExecutionCache = { schema: 1, scope: otherScope, epoch: { intent: 0, ack: 0 }, snapshot: a };
  const cachedB: ExecutionCache = { schema: 1, scope, epoch: { intent: 0, ack: 0 }, snapshot: snapshot() };
  for (const cache of [cachedA, cachedB]) db.prepare('INSERT INTO local_meta(key,value) VALUES(?,?)').run(executionCacheKey(cache.scope.owner, actor, cache.scope.allocationId), JSON.stringify(cache));
  const startA = operation(31, parameters({ p_session_id: id(80), p_allocation_id: other }));
  const pauseA = operation(32, parameters({ p_session_id: id(80), p_allocation_id: other, p_kind: 'pause', p_previous_event_id: startA.id, p_pause_reason: 'intervalo' }));
  const startB = operation(33, parameters({ p_session_id: id(90) }));
  const operations = [startA, pauseA, startB], epoch = { intent: 3, ack: 0 };
  const rows = db.prepare(EXECUTION_CONTEXT_SQL).all(JSON.stringify(executionContextKeys(scope, cachedB, operations))) as { key: string; value: string }[];
  for (const row of rows) assert.ok(Array.isArray(JSON.parse(row.value).known_event_ids), 'SQLite subquery JSON must remain an array across engine versions');
  const contexts = executionContexts(rows, scope, epoch), view = executionLocalView(cachedB, epoch, operations, contexts);
  assert.equal(view.safeToAppend, true); assert.equal(contexts[other].allocation.project_id, id(82));
  const result = projectExecution(view.snapshot!, view.operations, view.safeToAppend, view.contexts);
  assert.equal(result.uncertain, false); assert.equal(result.session?.id, id(90)); assert.equal(result.runningSession?.allocation_id, allocation);
  const atA = projectExecution(a, operations.slice(0, 2));
  assert.equal(atA.session?.state, 'paused');
  const withoutContext = projectExecution(snapshot(), operations); assert.equal(withoutContext.uncertain, true); assert.equal(withoutContext.runningSession?.id, id(80));
  db.close();
});

test('foreign context metadata is account, actor, allocation and ACK fenced without copying event notes', () => {
  const db = setup(), other = id(81), otherScope = { ...scope, allocationId: other };
  const contextSnapshot = snapshot({ allocation: { ...snapshot().allocation, id: other }, session: session({ allocation_id: other }) });
  const cache: ExecutionCache = { schema: 1, scope: otherScope, epoch: { intent: 1, ack: 2 }, snapshot: contextSnapshot };
  const key = executionCacheKey(owner, actor, other), epoch = { intent: 3, ack: 2 };
  db.prepare('INSERT INTO local_meta(key,value) VALUES(?,?)').run(key, JSON.stringify(cache));
  const rows = () => db.prepare(EXECUTION_CONTEXT_SQL).all(JSON.stringify([key])) as { key: string; value: string }[];
  assert.ok(executionContexts(rows(), scope, epoch)[other]);
  for (const invalid of [{ ...cache, scope: { ...otherScope, owner: id(98) } }, { ...cache, scope: { ...otherScope, operatorId: id(98) } }, { ...cache, scope: { ...otherScope, allocationId: id(98) } }, { ...cache, epoch: { intent: 1, ack: 1 } }, { ...cache, epoch: { intent: 4, ack: 2 } }]) {
    db.prepare('UPDATE local_meta SET value=? WHERE key=?').run(JSON.stringify(invalid), key);
    assert.deepEqual(executionContexts(rows(), scope, epoch), {});
  }
  const privateEvent = { id: id(20), session_id: id(10), previous_event_id: null, kind: 'start', occurred_at: stamp, received_at: stamp, pause_reason: null, note: 'PRIVATE_EVENT_NOTE', effort_minutes: null, disposition: 'accepted', review_reason: null, operator_id: actor, operator_name: null };
  db.prepare('UPDATE local_meta SET value=? WHERE key=?').run(JSON.stringify({ ...cache, snapshot: { ...contextSnapshot, events: [privateEvent], events_total: 1 } }), key);
  assert.ok(!rows()[0].value.includes('PRIVATE_EVENT_NOTE')); assert.deepEqual(executionContexts(rows(), scope, epoch)[other].known_event_ids, [id(20), id(20)]);
  db.close();
});

test('cached foreign restrictions and newer bad summaries retain occupancy, while confirmed foreign paused sessions can resume offline', () => {
  const other = id(81), foreign = session({ id: id(80), allocation_id: other, project_id: id(82), cell_id: id(83) });
  const a = snapshot({ allocation: { ...snapshot().allocation, id: other }, session: foreign });
  const foreignScope = { ...scope, allocationId: other }, epoch = { intent: 2, ack: 0 };
  const contextsFor = (source: ExecutionSnapshot) => executionContexts([{ key: executionCacheKey(owner, actor, other), value: JSON.stringify({ schema: 1, scope: foreignScope, epoch: { intent: 0, ack: 0 }, snapshot: source }) }], scope, epoch);
  const pause = operation(31, parameters({ p_session_id: foreign.id, p_allocation_id: other, p_kind: 'pause', p_previous_event_id: foreign.last_event_id, p_pause_reason: 'material' }));
  for (const source of [{ ...a, allocation: { ...a.allocation, project_closed: true } }, { ...a, session: { ...foreign, needs_review: true } }, { ...a, session: { ...foreign, has_review: true } }]) {
    const result = projectExecution(snapshot(), [pause, operation(32)], true, contextsFor(source));
    assert.equal(result.uncertain, true); assert.equal(result.runningSession?.id, foreign.id); assert.equal(result.session, null);
  }
  const newerBad = snapshot({ as_of: '2026-11-17T11:00:00Z', running_session: { ...foreign, can_record: false } });
  const result = projectExecution(newerBad, [pause], true, contextsFor(a)); assert.equal(result.uncertain, true); assert.equal(result.runningSession?.id, foreign.id);
  const paused = { ...a, session: { ...foreign, state: 'paused' as const } };
  const resume = operation(33, parameters({ p_session_id: foreign.id, p_allocation_id: other, p_kind: 'resume', p_previous_event_id: foreign.last_event_id }));
  const resumed = projectExecution(snapshot(), [resume], true, contextsFor(paused)); assert.equal(resumed.uncertain, false); assert.equal(resumed.runningSession?.project_id, id(82));
  // A compact current-allocation entry from before manager reconciliation must
  // never reintroduce its old session over the newly accepted null snapshot.
  const staleCurrent = executionContexts([{ key: executionCacheKey(owner, actor, allocation), value: JSON.stringify({ schema: 1, scope, epoch: { intent: 0, ack: 0 }, snapshot: snapshot({ session: session() }) }) }], scope, epoch);
  const currentResult = projectExecution(snapshot({ as_of: '2026-11-17T12:00:00Z' }), [operation(40, parameters({ p_session_id: id(99) }))], true, staleCurrent);
  assert.equal(currentResult.uncertain, false); assert.equal(currentResult.session?.id, id(99));
});

test('a newer own read confirms global running occupation even when a lost-ACK start remains in the outbox of an older allocation', () => {
  const other = id(81), foreign = session({ id: id(80), allocation_id: other, project_id: id(82), cell_id: id(83), last_event_id: id(31) });
  const a = snapshot({ as_of: '2026-11-17T11:00:00Z', allocation: { ...snapshot().allocation, id: other }, session: foreign, running_session: foreign });
  const row = { key: executionCacheKey(owner, actor, other), value: JSON.stringify({ schema: 1, scope: { ...scope, allocationId: other }, epoch: { intent: 1, ack: 0 }, snapshot: a }) };
  const contexts = executionContexts([row], scope, { intent: 1, ack: 0 });
  const lostAck = operation(31, parameters({ p_session_id: foreign.id, p_allocation_id: other }), 'failed');
  const result = projectExecution(snapshot(), [lostAck], true, contexts);
  assert.equal(result.uncertain, false); assert.equal(result.runningSession?.id, foreign.id); assert.equal(result.runningSession?.project_id, id(82));
  const laterStart = projectExecution(snapshot(), [lostAck, operation(32, parameters({ p_session_id: id(99) }))], true, contexts);
  assert.equal(laterStart.uncertain, true); assert.equal(laterStart.session, null); assert.equal(laterStart.runningSession?.id, foreign.id);
});

test('the timestamp of a newer global running observation defeats an older permissive own-session cache across three allocations', () => {
  const yAllocation = id(81), aAllocation = id(91), y = session({ id: id(80), allocation_id: yAllocation, project_id: id(82), cell_id: id(83), last_event_id: id(30) });
  const yRead = snapshot({ as_of: '2026-11-17T11:00:00Z', allocation: { ...snapshot().allocation, id: yAllocation }, session: y, running_session: y });
  const aSession = session({ id: id(90), allocation_id: aAllocation, state: 'paused', last_event_id: id(32) });
  const event = { id: id(31), session_id: aSession.id, previous_event_id: null, kind: 'start' as const, occurred_at: stamp, received_at: stamp, pause_reason: null, note: null, effort_minutes: null, disposition: 'accepted' as const, review_reason: null, operator_id: actor, operator_name: null };
  const aRead = snapshot({ as_of: '2026-11-17T12:00:00Z', allocation: { ...snapshot().allocation, id: aAllocation }, session: aSession, running_session: { ...y, can_record: false }, events: [event], events_total: 1 });
  const rows = [aRead, yRead].map(source => ({ key: executionCacheKey(owner, actor, source.allocation.id), value: JSON.stringify({ schema: 1, scope: { ...scope, allocationId: source.allocation.id }, epoch: { intent: 1, ack: 0 }, snapshot: source }) }));
  const contexts = executionContexts(rows, scope, { intent: 3, ack: 0 });
  const lostAckA = operation(31, parameters({ p_session_id: aSession.id, p_allocation_id: aAllocation }), 'failed');
  const pauseY = operation(33, parameters({ p_session_id: y.id, p_allocation_id: yAllocation, p_kind: 'pause', p_previous_event_id: y.last_event_id, p_pause_reason: 'intervalo' }));
  for (const map of [contexts, Object.fromEntries(Object.entries(contexts).reverse())]) {
    const result = projectExecution(snapshot(), [lostAckA, pauseY, operation(34)], true, map);
    assert.equal(result.uncertain, true); assert.equal(result.runningSession?.id, y.id); assert.equal(result.runningSession?.can_record, false); assert.equal(result.session, null);
  }
});
