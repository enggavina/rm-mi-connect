import test from 'node:test';
import assert from 'node:assert/strict';
import { knownConnection, nextSyncRecovery, showSyncRecovery } from '../src/core/sync-recovery';

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
