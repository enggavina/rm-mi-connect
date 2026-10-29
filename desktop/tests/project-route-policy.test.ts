import test from 'node:test';
import assert from 'node:assert/strict';
import { saveProjectRouteSchema } from '../src/server/web/project-route-policy';
import { createProjectRouteActions } from '../src/server/web/project-route-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00', hash = 'a'.repeat(64);
const request = { submissionId: id(1), projeto_id: id(2), expected_project_updated_at: version, expected_route_version: hash,
  items: [{ id: id(3), expected_updated_at: version }] };

test('project route is a strict full permutation with opaque project/item revisions and no operational mutations', () => {
  assert.deepEqual(saveProjectRouteSchema.parse(request), request);
  for (const invalid of [
    { ...request, actor_id: id(4) }, { ...request, celula_id: id(4) }, { ...request, expected_project_updated_at: null },
    { ...request, expected_project_updated_at: '2026-10-29' }, { ...request, expected_route_version: hash.toUpperCase() },
    { ...request, expected_route_version: undefined }, { ...request, items: [] }, { ...request, items: [...request.items, ...request.items] },
    ...['indice', 'posicao', 'prioridade', 'forms_ids', 'status', 'visibilidade', 'modified_by_id'].map(key => ({ ...request, items: [{ ...request.items[0], [key]: 1 }] })),
    { ...request, items: [{ ...request.items[0], expected_updated_at: 'infinity' }] },
  ]) assert.equal(saveProjectRouteSchema.safeParse(invalid).success, false);
  const items = Array.from({ length: 2000 }, (_, n) => ({ ...request.items[0], id: id(n + 10) }));
  assert.equal(saveProjectRouteSchema.safeParse({ ...request, items }).success, true);
  assert.equal(saveProjectRouteSchema.safeParse({ ...request, items: [...items, { ...request.items[0], id: id(9999) }] }).success, false);
});

function setup(profile = 'administrador', caps = ['em.portal.read', 'em.planning.manage', 'em.planning.read', 'em.projects.read'], result?: WebActionResult) {
  const calls: any[][] = [], auth: string[] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Pessoa', perfil: profile },
    sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities: caps } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createProjectRouteActions({
    actionUser: async capability => { auth.push(capability); return access; },
    mutate: async (...args) => { calls.push(args); return result ?? { ok: true, data: { operation: args[1], id: id(2), projeto_id: id(2), updated_at: version,
      record: { projeto_id: id(2), route_version: hash, changed_ids: [id(3)] }, idempotent_replay: false } }; },
  });
  return { ...actions, auth, calls };
}
test('route save requires planning management, both reads and an operational profile before SQL', async () => {
  for (const f of [setup('auditor'), setup('mobile'), setup('administrador', ['em.planning.manage', 'em.projects.read']), setup('administrador', ['em.planning.manage', 'em.planning.read'])]) {
    assert.equal((await f.saveProjectRoute(request)).ok, false); assert.deepEqual(f.auth, ['em.planning.manage']); assert.deepEqual(f.calls, []);
  }
  for (const profile of ['administrador', 'padr_o']) {
    const f = setup(profile); assert.equal((await f.saveProjectRoute(request)).ok, true);
    assert.equal(f.calls[0][1], 'save_project_route'); assert.equal(f.calls[0][3], 'em.planning.manage');
    assert.deepEqual(f.calls[0][2], request); await f.saveProjectRoute(request); assert.deepEqual(f.calls[0], f.calls[1]);
  }
});
test('route action preserves safe output and refuses crossed/corrupt results without exposing audit snapshots', async () => {
  const data = { operation: 'save_project_route', id: id(2), projeto_id: id(2), updated_at: version,
    record: { projeto_id: id(2), route_version: hash, changed_ids: [id(3)], secret: 'private' }, idempotent_replay: true, snapshot: 'private' };
  const result = await setup('administrador', undefined, { ok: true, data }).saveProjectRoute(request);
  assert.ok(result.ok); assert.ok(!JSON.stringify(result).includes('private')); assert.equal(result.data.idempotent_replay, true);
  for (const corrupt of [{ id: id(99) }, { projeto_id: null }, { operation: 'save_cell_queue' }, { updated_at: 'broken' },
    { record: { ...data.record, changed_ids: [id(99)] } }, { record: { ...data.record, changed_ids: [id(3), id(3)] } },
    { record: { ...data.record, route_version: 'broken' } }, { record: { ...data.record, projeto_id: id(9) } }]) {
    const failure = await setup('administrador', undefined, { ok: true, data: { ...data, ...corrupt } }).saveProjectRoute(request);
    assert.ok(!failure.ok); assert.equal(failure.code, 'UNAVAILABLE');
  }
  for (const code of ['PT409', '42501', '23505', 'UNAVAILABLE']) {
    const failure = await setup('administrador', undefined, { ok: false, code, error: 'Safe error' }).saveProjectRoute(request);
    assert.ok(!failure.ok); assert.equal(failure.code, code);
  }
});
