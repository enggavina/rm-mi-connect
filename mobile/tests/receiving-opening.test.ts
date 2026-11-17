import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, dirname, basename } from 'node:path';
import { existsSync, unlinkSync } from 'node:fs';
import { RM_MOBILE_SQLITE_DDL } from '../src/core/schema';
import { ReceivingOpeningCoordinator, parseReceivingOpeningReceipt, parseReceivingOpeningState, receivingOpeningKey, receivingOpeningParams, storeReceivingOpening, type ReceivingOpeningReceipt, type ReceivingOpeningSql, type ReceivingOpeningState } from '../src/core/receiving-opening';
import { busySyncWithPriority } from '../src/core/sync-policy';
import type { OutboxRow } from '../src/core/types';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const owner = id(1), actor = id(2), submission = id(3), at = '2026-11-18T12:00:00Z';
const params = { p_cliente_id: id(9), p_operador_id: actor, p_receiving_draft_id: submission, p_receiving_draft_revision: 4, p_receiving_draft_save_id: id(10), p_fotos_recebimento: [{ foto_url: 'file:///kept/front.jpg' }], p_arquivo_nota_fiscal_url: 'file:///kept/invoice.pdf', p_receiving_draft_snapshot: { id: submission, version: 2, fotos: [{ uri: 'file:///kept/front.jpg' }] } };
const row = (): OutboxRow => ({ id: submission, rpc_name: 'rm_submit_recebimento_v1', params_json: JSON.stringify(params), status: 'pending', attempts: 7, created_at: at, next_retry_at: 200, actor_id: actor, token_key: 'original-queued-operator-secret-ref', draft_id: null });
const receipt = (patch: Partial<ReceivingOpeningReceipt> = {}): ReceivingOpeningReceipt => ({ projeto_id: id(5), equipamento_id: id(6), receiving_id: submission, opening_created: true, attachments_pending: true, idempotent_replay: false, ...patch });
function database(file = ':memory:') {
  const db = new DatabaseSync(file); db.exec(RM_MOBILE_SQLITE_DDL);
  db.exec('CREATE TABLE IF NOT EXISTS local_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);CREATE TABLE IF NOT EXISTS local_queue_meta(id TEXT PRIMARY KEY,actor_id TEXT,token_key TEXT,draft_id TEXT,next_retry_at INTEGER NOT NULL DEFAULT 0,result_json TEXT)');
  return db;
}
function adapter(db: DatabaseSync): ReceivingOpeningSql { return { getFirstAsync: async <T>(query: string, ...values: (string | number | null)[]) => (db.prepare(query).get(...values) ?? null) as T | null, runAsync: async (query, ...values) => db.prepare(query).run(...values) }; }
function enqueue(db: DatabaseSync) {
  const queued = row();
  db.prepare('INSERT INTO local_rpc_outbox(id,rpc_name,params_json,status,attempts,created_at) VALUES(?,?,?,?,?,?)').run(queued.id, queued.rpc_name, queued.params_json, queued.status, queued.attempts, queued.created_at);
  db.prepare('INSERT INTO local_queue_meta(id,actor_id,token_key,next_retry_at) VALUES(?,?,?,?)').run(queued.id, queued.actor_id, queued.token_key, queued.next_retry_at);
}
async function tx<T>(db: DatabaseSync, fn: (sql: ReceivingOpeningSql) => Promise<T>) { db.exec('BEGIN'); try { const result = await fn(adapter(db)); db.exec('COMMIT'); return result; } catch (error) { db.exec('ROLLBACK'); throw error; } }
const list = (db: DatabaseSync) => db.prepare('SELECT o.*,m.actor_id,m.token_key,m.next_retry_at,m.result_json FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) ORDER BY o.created_at,o.rowid').all() as unknown as OutboxRow[];
function load(db: DatabaseSync, queued: OutboxRow) { const stored = db.prepare('SELECT value FROM local_meta WHERE key=?').get(receivingOpeningKey(owner, queued.actor_id, queued.id)); return parseReceivingOpeningState(stored ? JSON.parse(String(stored.value)) : null, owner, queued.actor_id, queued.id); }

test('priority opening reaches the portal with the original envelope while unrelated uploads are still pending or fail', async () => {
  const db = database(); enqueue(db); const before = list(db), calls: string[] = [];
  const coordinator = new ReceivingOpeningCoordinator({ assertOwner: value => assert.equal(value, owner), list: async () => list(db), read: async (_, queued) => load(db, queued), write: (queued, state) => tx(db, sql => storeReceivingOpening(sql, queued, state)), send: async (value, queued, sent) => {
    calls.push('open'); assert.equal(value, owner); assert.equal(queued.actor_id, actor); assert.equal(queued.token_key, row().token_key); assert.deepEqual(sent, params); return receipt();
  } });
  const media = new Promise<void>(() => {}); // A pre-existing global sync may be uploading for minutes.
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try { await Promise.race([coordinator.run(owner), new Promise<never>((_, reject) => { timeout = setTimeout(() => reject(new Error('Opening waited for media')), 1000); })]); }
  finally { clearTimeout(timeout); }
  assert.deepEqual(calls, ['open']); assert.equal(load(db, row())?.receipt?.projeto_id, id(5)); assert.deepEqual(list(db), before);
  await assert.rejects(Promise.reject(new Error('Unrelated upload failed')), /upload failed/);
  assert.equal(load(db, row())?.receipt?.attachments_pending, true); assert.equal(list(db)[0].status, 'pending');
  assert.ok(media); db.close();
});

test('a lost opening response survives restart and replays the same protocol, payload and queued author without finalizing attachments', async () => {
  const file = join(tmpdir(), `em-receiving-opening-${randomUUID()}.sqlite`); let db = database(file), currentOwner = owner, calls = 0, projects = 0;
  try {
    enqueue(db); const original = list(db);
    const make = () => new ReceivingOpeningCoordinator({ assertOwner: value => { assert.equal(currentOwner, value); }, list: async () => list(db), read: async (_, queued) => load(db, queued), write: (queued, state) => tx(db, sql => storeReceivingOpening(sql, queued, state)), send: async (_, queued, sent) => {
      calls++; assert.equal(queued.id, submission); assert.equal(queued.actor_id, actor); assert.deepEqual(sent, params);
      if (calls === 1) { projects++; throw new Error('Network request failed after server commit'); }
      return receipt({ idempotent_replay: true });
    }, now: () => Date.parse(at) });
    await make().run(owner); assert.equal(load(db, row())?.receipt, null); assert.equal(load(db, row())?.attempts, 1);
    db.close(); db = new DatabaseSync(file);
    await make().run(owner, true); assert.equal(projects, 1); assert.equal(calls, 2); assert.equal(load(db, row())?.receipt?.idempotent_replay, true); assert.deepEqual(list(db), original);
    await make().run(owner, true); assert.equal(calls, 2); // A durable opening receipt is not sent twice.
  } finally {
    db.close(); assert.equal(dirname(file), tmpdir()); assert.match(basename(file), /^em-receiving-opening-[0-9a-f-]+\.sqlite$/);
    for (const suffix of ['', '-wal', '-shm']) if (existsSync(file + suffix)) unlinkSync(file + suffix);
  }
});

test('late opening responses cannot publish local evidence after account change or reattribute the queued operator', async () => {
  const db = database(); enqueue(db); let currentOwner = owner, release!: (value: unknown) => void;
  const coordinator = new ReceivingOpeningCoordinator({ assertOwner: value => { if (value !== currentOwner) throw new Error('Owner changed'); }, list: async () => list(db), read: async (_, queued) => load(db, queued), write: (queued, state) => tx(db, sql => storeReceivingOpening(sql, queued, state)), send: async () => new Promise(resolve => { release = resolve; }) });
  const running = coordinator.run(owner); while (!release) await Promise.resolve(); currentOwner = id(99); release(receipt());
  await assert.rejects(running, /Owner changed/); assert.equal(load(db, row()), null); assert.equal(list(db)[0].actor_id, actor); assert.equal(list(db)[0].status, 'pending');
  const confused = { ...row(), actor_id: id(99) }; assert.throws(() => receivingOpeningParams(confused)); db.close();
});

test('opening evidence writes are atomic and reject changed payloads or another owner cache', async () => {
  const db = database(); enqueue(db); const state: ReceivingOpeningState = { schema: 1, owner, actor, receivingId: submission, receipt: receipt(), attempts: 0, nextRetryAt: 0, error: null, updatedAt: at };
  await assert.rejects(tx(db, sql => storeReceivingOpening({ ...sql, runAsync: async () => { throw new Error('Power loss'); } }, row(), state)), /Power loss/);
  assert.equal(load(db, row()), null); assert.equal(list(db)[0].status, 'pending');
  await assert.rejects(tx(db, sql => storeReceivingOpening(sql, { ...row(), params_json: JSON.stringify({ ...params, p_receiving_draft_revision: 100 }) }, state)), /abertura/);
  assert.throws(() => parseReceivingOpeningState({ ...state, owner: id(99) }, owner, actor, submission));
  await tx(db, sql => storeReceivingOpening(sql, row(), state)); assert.deepEqual(load(db, row())?.receipt, receipt());
  assert.equal(list(db)[0].result_json, null); assert.equal(list(db)[0].status, 'pending'); db.close();
});

test('authoritative deletion and missing API errors back off without changing IDs or dropping offline attachments', async () => {
  for (const code of ['PT410', 'PGRST202', '28000', '42501']) {
    const db = database(); enqueue(db); let calls = 0;
    const coordinator = new ReceivingOpeningCoordinator({ assertOwner: value => assert.equal(value, owner), list: async () => list(db), read: async (_, queued) => load(db, queued), write: (queued, state) => tx(db, sql => storeReceivingOpening(sql, queued, state)), send: async (_, queued) => { calls++; assert.equal(queued.id, submission); throw { code, message: 'Abertura não autorizada ou indisponível' }; }, now: () => Date.parse(at) });
    await coordinator.run(owner); await coordinator.run(owner); assert.equal(calls, 1); assert.equal(load(db, row())?.nextRetryAt, Date.parse(at) + 300_000); assert.equal(list(db)[0].params_json, row().params_json); assert.equal(list(db)[0].status, 'pending'); db.close();
  }
});

test('opening DTO distinguishes creation, legacy QR and an already finalized submission while rejecting false confirmations', () => {
  assert.equal(parseReceivingOpeningReceipt(receipt(), submission).attachments_pending, true);
  assert.equal(parseReceivingOpeningReceipt(receipt({ opening_created: false, attachments_pending: true }), submission).opening_created, false);
  assert.equal(parseReceivingOpeningReceipt(receipt({ opening_created: false, attachments_pending: false }), submission).attachments_pending, false);
  for (const value of [receipt({ opening_created: true, attachments_pending: false }), receipt({ receiving_id: id(99) }), { ...receipt(), projeto_id: 'wrong' }, { ...receipt(), private: 'strip' }]) {
    if ('private' in value) assert.ok(!('private' in parseReceivingOpeningReceipt(value, submission))); else assert.throws(() => parseReceivingOpeningReceipt(value, submission));
  }
});

test('manual sync retries a backed-off opening during an active upload without starting another upload batch', async () => {
  const db = database(); enqueue(db); let calls = 0, release!: () => void;
  const activeUpload = new Promise<void>(resolve => { release = resolve; });
  const coordinator = new ReceivingOpeningCoordinator({ assertOwner: value => assert.equal(value, owner), list: async () => list(db), read: async (_, queued) => load(db, queued), write: (queued, state) => tx(db, sql => storeReceivingOpening(sql, queued, state)), send: async () => { calls++; if (calls === 1) throw { code: 'PGRST202', message: 'API unavailable' }; return receipt(); }, now: () => Date.parse(at) });
  await coordinator.run(owner); assert.equal(calls, 1); assert.equal(load(db, row())?.receipt, null);
  let forced: Promise<void> | undefined;
  const prioritize = () => { forced = coordinator.run(owner, true); return forced; };
  assert.equal(busySyncWithPriority(activeUpload, false, prioritize), activeUpload); assert.equal(forced, undefined);
  assert.equal(busySyncWithPriority(undefined, true, prioritize), undefined); assert.equal(forced, undefined);
  assert.equal(busySyncWithPriority(activeUpload, true, prioritize), activeUpload);
  await forced; assert.equal(calls, 2); assert.equal(load(db, row())?.receipt?.attachments_pending, true);
  assert.equal(list(db)[0].status, 'pending'); release(); await activeUpload; db.close();
});
