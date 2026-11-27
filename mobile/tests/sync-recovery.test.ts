import test from 'node:test';
import assert from 'node:assert/strict';
import { canOpenSyncQueue, knownConnection, nextSyncRecovery, showSyncRecovery, syncQueueSummary } from '../src/core/sync-recovery';
import { RPC_NAMES, type Operator, type OutboxRow } from '../src/core/types';

function scenario() {
  let state = { online: false, connectionKnown: false, syncRecovery: false, pendingMedia: 0, pendingMutations: 0 };
  return {
    connection(online: boolean) {
      state = { ...state, online, connectionKnown: true, syncRecovery: nextSyncRecovery(state.syncRecovery, { type: 'connection', online, pending: state.pendingMedia + state.pendingMutations }) };
    },
    queue(pendingMedia: number, pendingMutations: number, restoring = false) {
      state = { ...state, pendingMedia, pendingMutations, syncRecovery: nextSyncRecovery(state.syncRecovery, { type: 'queue', online: state.online, pendingMedia, pendingMutations, restoring }) };
    },
    interrupted() { state.syncRecovery = nextSyncRecovery(state.syncRecovery, { type: 'interrupted-send' }); },
    visible() { return showSyncRecovery(state); },
  };
}

test('unknown initial connectivity and routine online uploads never show a recovery notice', () => {
  assert.equal(knownConnection({ isConnected: null, isInternetReachable: null }), null);
  assert.equal(knownConnection({ isConnected: true, isInternetReachable: null }), true);
  assert.equal(knownConnection({ isConnected: true, isInternetReachable: false }), false);
  assert.equal(knownConnection({ isConnected: false, isInternetReachable: null }), false);
  const app = scenario();
  assert.equal(app.visible(), false);
  app.connection(true); app.queue(0, 0, true);
  assert.equal(app.visible(), false);
  app.queue(1, 1); assert.equal(app.visible(), false);
  app.queue(0, 0); assert.equal(app.visible(), false);
});

test('offline work remains visible after reconnect until both media and mutations are confirmed', () => {
  const app = scenario(); app.connection(true); app.connection(false);
  assert.equal(app.visible(), true);
  app.queue(2, 1); app.connection(true);
  assert.equal(app.visible(), true);
  app.queue(0, 1); assert.equal(app.visible(), true);
  app.queue(0, 1); assert.equal(app.visible(), true, 'backoff or failure must retain recovery');
  app.queue(0, 0); assert.equal(app.visible(), false, 'no need to wait for catalog downloads');
  app.queue(1, 1); assert.equal(app.visible(), false, 'future ordinary online work stays quiet');
});

test('a connection interruption without queued work does not show a reconnect warning', () => {
  const app = scenario(); app.connection(false); app.queue(0, 0);
  assert.equal(app.visible(), true, 'offline mode is still explained');
  app.connection(true); assert.equal(app.visible(), false);
  app.queue(1, 1); assert.equal(app.visible(), false, 'new online work does not inherit an empty interruption');
  app.queue(0, 0); assert.equal(app.visible(), false);
});

test('reopening online restores recovery from durable queues without relying on connectivity history', () => {
  for (const [media, mutations] of [[1, 0], [0, 1], [3, 2]]) {
    const app = scenario(); app.queue(media, mutations, true);
    assert.equal(app.visible(), false, 'unknown initial connectivity must not be announced as offline');
    app.connection(true);
    assert.equal(app.visible(), true);
    app.queue(0, 0); assert.equal(app.visible(), false);
  }
});

test('a transport failure can expose pending sends even when the network monitor still says online', () => {
  const app = scenario(); app.connection(true); app.queue(1, 1);
  app.interrupted(); assert.equal(app.visible(), true);
  app.connection(true); assert.equal(app.visible(), true, 'repeated online events do not confirm delivery');
  app.queue(0, 1); assert.equal(app.visible(), true);
  app.queue(0, 0); assert.equal(app.visible(), false);
  app.interrupted(); assert.equal(app.visible(), false, 'a catalog-only failure has no unsent data');
});

test('pending protocol details open only for the current device and operator after recovery begins online', () => {
  const operator: Operator = { operador_id: 'operator', matricula: 'operator', nome: 'Operador local', perfil: 'mobile',
    perfil_assinante: [], celulas_vinculadas: [], authenticated_at: '2026-11-27T17:00:00Z' };
  const reconnect = { operator, sessionUserId: 'device', online: true, connectionKnown: true, syncRecovery: true,
    pendingMedia: 0, pendingMutations: 1 };
  assert.equal(canOpenSyncQueue(reconnect), true);
  assert.equal(canOpenSyncQueue({ ...reconnect, pendingMutations: 0, pendingMedia: 1 }), true);
  for (const change of [{ online: false }, { connectionKnown: false }, { syncRecovery: false }, { sessionUserId: null },
    { operator: null }, { pendingMutations: 0 }]) assert.equal(canOpenSyncQueue({ ...reconnect, ...change }), false);
});

test('recovery details preserve each original protocol and omit private queue data', () => {
  const row: OutboxRow = { id: '10cfcc01-3e5d-4d16-a07d-e0893d7cf550', rpc_name: 'rm_submit_recebimento_v1',
    status: 'failed', created_at: '2026-11-27T17:00:00Z', params_json: '{"internal":"payload"}', attempts: 2,
    next_retry_at: 0, actor_id: 'operator', token_key: 'local-token-key', draft_id: null, workshop_id: 'workshop', last_error: 'Raw error' };
  assert.deepEqual(syncQueueSummary(row), { protocol: row.id, operation: 'Recebimento', status: 'Aguardando nova tentativa',
    createdAt: row.created_at, failed: true });
  assert.equal(syncQueueSummary({ ...row, status: 'syncing' }).status, 'Enviando');
  assert.equal(syncQueueSummary({ ...row, status: 'pending' }).status, 'Aguardando envio');
  const labels = RPC_NAMES.map(rpc_name => syncQueueSummary({ ...row, rpc_name }).operation);
  assert.equal(new Set(labels).size, RPC_NAMES.length);
});
