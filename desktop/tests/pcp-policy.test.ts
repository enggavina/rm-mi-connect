import test from 'node:test';
import assert from 'node:assert/strict';
import { saveCellQueueSchema } from '../src/server/web/pcp-policy';
import { createPcpActions } from '../src/server/web/pcp-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00', hash = 'a'.repeat(64);
const request = { submissionId: id(1), celula_id: id(2), expected_queue_version: hash, apply_order: false,
  items: [{ id: id(3), expected_updated_at: version, prioridade: 'alta' }] };

test('PCP queue payload preserves exact revisions and requires an explicit order decision without actor injection', () => {
  assert.deepEqual(saveCellQueueSchema.parse(request), request);
  assert.deepEqual(saveCellQueueSchema.parse({ ...request, apply_order: true, items: [{ ...request.items[0], prioridade: null }] }),
    { ...request, apply_order: true, items: [{ ...request.items[0], prioridade: null }] });
  for (const invalid of [
    { ...request, actor_id: id(8) }, { ...request, operation: 'plan_cell' },
    { ...request, expected_queue_version: hash.toUpperCase() }, { ...request, expected_queue_version: 'unknown' },
    { ...request, expected_queue_version: null }, { ...request, apply_order: undefined }, { ...request, apply_order: 'false' },
    { ...request, items: [] }, { ...request, items: [request.items[0], request.items[0]] },
    { ...request, items: [{ ...request.items[0], prioridade: 'urgent' }] },
    { ...request, items: [{ ...request.items[0], expected_updated_at: null }] },
    { ...request, items: [{ ...request.items[0], expected_updated_at: '2026-10-29' }] },
    { ...request, items: [{ ...request.items[0], posicao: 1 }] },
    { ...request, items: [{ ...request.items[0], status: 'finalizado' }] },
    { ...request, items: [{ ...request.items[0], modified_by_id: id(8) }] },
  ]) assert.equal(saveCellQueueSchema.safeParse(invalid).success, false);
  const items = Array.from({ length: 2000 }, (_, n) => ({ ...request.items[0], id: id(n + 10) }));
  assert.equal(saveCellQueueSchema.safeParse({ ...request, items }).success, true);
  assert.equal(saveCellQueueSchema.safeParse({ ...request, items: [...items, { ...request.items[0], id: id(9999) }] }).success, false);
});

function setup(profile = 'administrador', denied = false, result?: WebActionResult) {
  const calls: any[][] = [], auth: string[] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Pessoa', perfil: profile },
    sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities: ['em.portal.read', 'em.planning.manage'] } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createPcpActions({
    actionUser: async capability => { auth.push(capability); return denied ? { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' } : access; },
    mutate: async (...args) => { calls.push(args); return result ?? { ok: true, data: { operation: args[1], id: id(2), projeto_id: null, updated_at: version, record: { raw: 'private' }, idempotent_replay: false } }; },
  });
  return { ...actions, auth, calls };
}

test('queue writes need the current planning management grant and an allowed RM profile before reaching SQL', async () => {
  for (const fixture of [setup('auditor'), setup('mobile'), setup('administrador', true)]) {
    assert.equal((await fixture.saveCellQueue(request)).ok, false);
    assert.deepEqual(fixture.auth, ['em.planning.manage']); assert.deepEqual(fixture.calls, []);
  }
  for (const profile of ['administrador', 'padr_o']) {
    const fixture = setup(profile); assert.equal((await fixture.saveCellQueue(request)).ok, true);
    assert.equal(fixture.calls[0][1], 'save_cell_queue'); assert.equal(fixture.calls[0][3], 'em.planning.manage');
  }
});

test('queue BFF retries keep the full sequence, priorities and opaque versions unchanged', async () => {
  const fixture = setup(); await fixture.saveCellQueue(request); await fixture.saveCellQueue(request);
  assert.deepEqual(fixture.calls[0], fixture.calls[1]); assert.deepEqual(fixture.calls[0][2], request);
  assert.equal((await fixture.saveCellQueue({ ...request, expected_queue_version: null })).ok, false);
  assert.equal(fixture.calls.length, 2);
});

test('queue result never sends private batch snapshots or fabricated single-project ownership to the browser', async () => {
  const raw: any = { ok: true, data: { operation: 'save_cell_queue', id: id(2), projeto_id: null, updated_at: version,
    record: { secret: 'private-record' }, snapshot: { secret: 'private-snapshot' }, changed_ids: ['private'], idempotent_replay: true } };
  const result = await setup('administrador', false, raw).saveCellQueue(request);
  assert.ok(result.ok); assert.deepEqual(result.data.record, {}); assert.equal(result.data.projeto_id, null); assert.equal(result.data.idempotent_replay, true);
  assert.ok(!/private|secret|snapshot|changed_ids/.test(JSON.stringify(result)));
  for (const corrupt of [{ id: id(99) }, { operation: 'plan_cell' }, { projeto_id: id(99) }, { updated_at: 'broken' }, { idempotent_replay: undefined }]) {
    const failure = await setup('administrador', false, { ...raw, data: { ...raw.data, ...corrupt } }).saveCellQueue(request);
    assert.ok(!failure.ok); assert.equal(failure.code, 'UNAVAILABLE');
  }
  for (const code of ['PT409', '42501', '23505', 'UNAVAILABLE']) {
    const failure = await setup('administrador', false, { ok: false, code, error: 'Sanitized' }).saveCellQueue(request);
    assert.ok(!failure.ok); assert.equal(failure.code, code);
  }
});
