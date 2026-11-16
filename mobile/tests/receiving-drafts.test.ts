import test from 'node:test';
import assert from 'node:assert/strict';
import { assertReceivingDraftUnchanged, ReceivingDraftCoordinator, receivingDraftMeta, type ReceivingDraftEntry, type ReceivingDraftRemote,
  type ReceivingDraftRequest, type ReceivingDraftStore, type ReceivingDraftTransport } from '../src/core/receiving-drafts';
import { newReceiving } from '../src/domain/receiving';

const copy = <T>(value: T): T => structuredClone(value);
const draft = (id = 'draft-one') => newReceiving(id, '2026-11-16T12:00:00.000Z');
class Store implements ReceivingDraftStore {
  rows = new Map<string, ReceivingDraftEntry>(); archives: ReceivingDraftEntry[] = [];
  private lane: Promise<unknown> = Promise.resolve();
  async load(actor: string) { await this.lane; return copy(this.rows.get(actor) ?? null); }
  change(actor: string, fn: (entry: ReceivingDraftEntry | null) => ReceivingDraftEntry): Promise<ReceivingDraftEntry> {
    const work = this.lane.then(() => { const next = fn(copy(this.rows.get(actor) ?? null)); this.rows.set(actor, copy(next)); return copy(next); });
    this.lane = work.catch(() => undefined); return work;
  }
  async archive(_actor: string, entry: ReceivingDraftEntry) { this.archives.push(copy(entry)); }
}
class Remote implements ReceivingDraftTransport {
  cloud: ReceivingDraftRemote | null = null; requests: ReceivingDraftRequest[] = []; lostResponse = false;
  async read(id: string | null) { return this.cloud && (!id || this.cloud.id === id) ? copy(this.cloud) : null; }
  async save(id: string, request: ReceivingDraftRequest) {
    this.requests.push(copy(request));
    const prior = this.requests.slice(0, -1).find(value => value.saveId === request.saveId);
    if (!prior) {
      if ((this.cloud?.revision ?? 0) !== request.expectedRevision) throw Object.assign(new Error('Outra versão no banco.'), { code: 'PT409' });
      this.cloud = { id, revision: request.expectedRevision + 1, payload: copy(request.payload), state: 'draft' };
    } else assert.deepEqual(prior, request);
    if (this.lostResponse) { this.lostResponse = false; throw new Error('Network request failed'); }
    return copy(this.cloud!);
  }
}
function setup() {
  const store = new Store(), remote = new Remote(); let id = 0;
  const coordinator = new ReceivingDraftCoordinator(store, () => `save-${++id}`);
  const sync = () => coordinator.sync('actor', remote, copy, async () => false);
  return { store, remote, coordinator, sync };
}

test('starting a partial receiving persists the draft, syncs it separately, and resumes on a fresh device', async () => {
  const { store, remote, coordinator, sync } = setup();
  const initial = await coordinator.open('actor', draft);
  assert.equal(initial.data.cliente, ''); assert.equal(store.rows.size, 1); assert.equal(remote.requests.length, 0);
  await sync();
  assert.equal(remote.requests.length, 1); assert.equal(remote.cloud?.state, 'draft');
  assert.equal((await store.load('actor'))?.meta.state, 'saved');
  const second = new Store(), reopened = new ReceivingDraftCoordinator(second, () => 'unused');
  const restored = await reopened.open('actor', () => draft('different'), remote);
  assert.deepEqual(restored.data, { ...initial.data, submitted: false });
  assert.equal(restored.meta.revision, 1);
});

test('every local edit survives closing/reopening offline with its original protocol and media', async () => {
  const { store, coordinator } = setup();
  await coordinator.open('actor', draft);
  const values = { ...draft(), step: 1, notaFiscal: '0012', descricaoEquipamento: 'Motor salvo',
    fotos: [{ id: 'photo-original', tipo: 'frente', uri: 'file:///durable/photo.jpg', comentario: 'Observação' }] };
  await coordinator.save('actor', values);
  const cold = new ReceivingDraftCoordinator(store, () => 'new-id');
  const resumed = await cold.open('actor', () => draft('new-id'));
  assert.deepEqual(resumed.data, values); assert.equal(resumed.meta.state, 'pending');
  assert.equal((await cold.open('other', () => draft('other-id'))).data.id, 'other-id');
  assert.deepEqual((await store.load('actor'))?.data, values);
});

test('lost autosave response retries the exact persisted request before sending newer local edits', async () => {
  const { store, remote, coordinator, sync } = setup();
  await coordinator.open('actor', draft);
  remote.lostResponse = true;
  await assert.rejects(sync(), /Network/);
  const unacknowledged = (await store.load('actor'))!.meta.pending!;
  assert.equal(unacknowledged.expectedRevision, 0); assert.equal(remote.cloud?.revision, 1);
  await coordinator.save('actor', { ...draft(), notaFiscal: 'typed after lost response' });
  // Simulate process death: the request is recovered from persistent metadata.
  const cold = new ReceivingDraftCoordinator(store, () => 'second-save');
  await cold.sync('actor', remote, copy, async () => false);
  assert.equal(remote.requests.length, 3);
  assert.deepEqual(remote.requests[0], remote.requests[1]);
  assert.equal(remote.requests[2].expectedRevision, 1);
  assert.equal(remote.cloud?.payload.notaFiscal, 'typed after lost response');
  const saved = (await store.load('actor'))!;
  assert.equal(saved.meta.revision, 2); assert.equal(saved.meta.state, 'saved'); assert.equal(saved.meta.pending, undefined);
});

test('edits made while a cloud request is in flight remain local and are sent after its acknowledgment', async () => {
  const { store, remote, coordinator, sync } = setup();
  await coordinator.open('actor', draft);
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>(resolve => { entered = resolve; }), paused = new Promise<void>(resolve => { release = resolve; });
  const original = remote.save.bind(remote); let first = true;
  remote.save = async (id, request) => { if (first) { first = false; entered(); await paused; } return original(id, request); };
  const send = sync(); await started;
  await coordinator.save('actor', { ...draft(), eventualidades: 'Edited during upload' });
  assert.equal((await store.load('actor'))?.data.eventualidades, 'Edited during upload');
  release(); await send;
  assert.equal(remote.cloud?.payload.eventualidades, 'Edited during upload');
  assert.equal((await store.load('actor'))?.meta.state, 'saved');
});

test('opening a newer cloud version never overwrites unsent local edits; conflicts require explicit recovery', async () => {
  const { store, remote, coordinator, sync } = setup();
  await coordinator.open('actor', draft); await sync();
  await coordinator.save('actor', { ...draft(), notaFiscal: 'local work' });
  remote.cloud = { ...remote.cloud!, revision: 2, payload: { ...draft(), notaFiscal: 'other device work' } };
  assert.equal((await coordinator.open('actor', draft, remote)).data.notaFiscal, 'local work');
  await assert.rejects(sync(), /Outra versão/);
  const conflict = (await store.load('actor'))!;
  assert.equal(conflict.meta.state, 'conflict'); assert.equal(conflict.data.notaFiscal, 'local work');
  await assert.rejects(coordinator.submission('actor', async () => 'should not run'), /versão diferente/);
  const calls = remote.requests.length; await sync(); assert.equal(remote.requests.length, calls);
  const restored = await coordinator.recover('actor', remote);
  assert.equal(restored.data.notaFiscal, 'other device work'); assert.equal(store.archives[0].data.notaFiscal, 'local work');
  assert.equal(restored.meta.revision, 2); assert.equal(restored.meta.state, 'saved');
});

test('draft media failures are visible and preserve the original draft for retry', async () => {
  const { store, remote, coordinator } = setup(); await coordinator.open('actor', draft);
  await assert.rejects(coordinator.sync('actor', remote, () => { throw new Error('Foto ainda não enviada'); }, async () => false), /Foto/);
  const saved = (await store.load('actor'))!;
  assert.equal(saved.meta.state, 'pending'); assert.match(saved.meta.error!, /Foto/);
  assert.equal(saved.data.id, 'draft-one'); assert.equal(remote.requests.length, 0);
});

test('submission waits for the in-flight save, freezes revision and skips autosave once queued', async () => {
  const { store, remote, coordinator, sync } = setup(); await coordinator.open('actor', draft);
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>(resolve => { entered = resolve; }), paused = new Promise<void>(resolve => { release = resolve; });
  const original = remote.save.bind(remote);
  remote.save = async (id, request) => { entered(); await paused; return original(id, request); };
  const sending = sync(); await started;
  let finalized = false;
  const submit = coordinator.submission('actor', async entry => { assert.equal(entry.meta.revision, 1); finalized = true; return entry.data.id; });
  await Promise.resolve(); assert.equal(finalized, false);
  await assert.rejects(coordinator.submission('actor', async () => 'second'), /Aguarde/);
  release(); await sending; assert.equal(await submit, 'draft-one');
  await coordinator.save('actor', { ...draft(), notaFiscal: 'latest' });
  const calls = remote.requests.length;
  await coordinator.sync('actor', remote, copy, async () => true);
  assert.equal(remote.requests.length, calls); assert.equal((await store.load('actor'))?.data.notaFiscal, 'latest');
});

test('another device finalization preserves local data and prevents a second receiving submission', async () => {
  const { store, remote, coordinator } = setup(); await coordinator.open('actor', draft);
  await coordinator.save('actor', { ...draft(), notaFiscal: 'unsent original' });
  remote.cloud = { id: 'draft-one', revision: 4, state: 'finalized', payload: draft(), result: { projeto_id: 'existing-project' } };
  const resumed = await coordinator.open('actor', draft, remote);
  assert.equal(resumed.data.notaFiscal, 'unsent original'); assert.equal(resumed.data.submitted, true);
  assert.equal(resumed.meta.state, 'finalized');
  assert.equal(store.archives[0].data.notaFiscal, 'unsent original');
  await assert.rejects(coordinator.submission('actor', async () => 'duplicate'), /já foi concluído/);
  assert.equal(store.rows.size, 1);
  await coordinator.save('actor', draft('next-protocol'));
  assert.equal((await store.load('actor'))?.meta.revision, 0);
});

test('existing submitted drafts cannot be changed or silently replaced before submission', async () => {
  const { coordinator } = setup(); await coordinator.open('actor', draft);
  await assert.rejects(coordinator.save('actor', draft('another')), /Conclua/);
  await coordinator.save('actor', { ...draft(), submitted: true });
  await assert.rejects(coordinator.save('actor', { ...draft(), notaFiscal: 'changed' }), /já foi confirmado/);
  await assert.rejects(coordinator.recover('actor', new Remote()), /protocolo/);
  const meta = receivingDraftMeta(draft()); assert.equal(meta.revision, 0);
});

test('explicit cloud recovery excludes a simultaneous autosave or confirmation until the local copy is preserved', async () => {
  const { store, remote, coordinator, sync } = setup();
  await coordinator.open('actor', draft); await sync();
  await coordinator.save('actor', { ...draft(), notaFiscal: 'local conflict' });
  remote.cloud = { ...remote.cloud!, revision: 2, payload: { ...draft(), notaFiscal: 'cloud choice' } };
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>(resolve => { entered = resolve; }), paused = new Promise<void>(resolve => { release = resolve; });
  const read = remote.read.bind(remote);
  remote.read = async id => { entered(); await paused; return read(id); };
  const recovering = coordinator.recover('actor', remote); await started;
  const requests = remote.requests.length; await sync(); assert.equal(remote.requests.length, requests);
  await assert.rejects(coordinator.submission('actor', async () => 'duplicate'), /Aguarde/);
  release(); assert.equal((await recovering).data.notaFiscal, 'cloud choice');
  assert.equal(store.archives[0].data.notaFiscal, 'local conflict');
});

test('an edit from another screen during cloud recovery is never overwritten by a late response', async () => {
  const { store, remote, coordinator, sync } = setup();
  await coordinator.open('actor', draft); await sync();
  await coordinator.save('actor', { ...draft(), notaFiscal: 'original local conflict' });
  remote.cloud = { ...remote.cloud!, revision: 2, payload: { ...draft(), notaFiscal: 'older cloud choice' } };
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>(resolve => { entered = resolve; }), paused = new Promise<void>(resolve => { release = resolve; });
  const read = remote.read.bind(remote);
  remote.read = async id => { entered(); await paused; return read(id); };
  const recovering = coordinator.recover('actor', remote); await started;
  // A separate mounted screen/service caller is not protected by this screen's UI busy flag.
  await coordinator.save('actor', { ...draft(), notaFiscal: 'newer local edit' });
  release(); await assert.rejects(recovering, /mudou durante a consulta/);
  assert.equal((await store.load('actor'))?.data.notaFiscal, 'newer local edit');
  assert.equal(store.archives[0].data.notaFiscal, 'original local conflict');
});

test('final queue guard rejects a changed draft or protocol before recording a receiving submission', async () => {
  const { store, coordinator } = setup(); await coordinator.open('actor', draft);
  const captured = (await store.load('actor'))!;
  assert.doesNotThrow(() => assertReceivingDraftUnchanged(copy(captured), captured));
  await coordinator.save('actor', { ...draft(), notaFiscal: 'another screen edited during confirmation' });
  assert.throws(() => assertReceivingDraftUnchanged(store.rows.get('actor')!, captured), { code: 'RECEIVING_CHANGED' });
  assert.throws(() => assertReceivingDraftUnchanged({ ...captured, data: draft('another') }, captured), { code: 'RECEIVING_CHANGED' });
  assert.equal((await store.load('actor'))?.data.notaFiscal, 'another screen edited during confirmation');
});
