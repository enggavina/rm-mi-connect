import test from 'node:test';
import assert from 'node:assert/strict';
import { createCatalogActions } from '../src/server/web/catalog-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
const id = '00000000-0000-4000-8000-000000000001';
const version = '2026-10-29T18:03:24.123456+00:00';
const request = { submissionId: id, id, kind: 'clients', expected_updated_at: version, changes: { nome: 'Cliente' } };
function setup(profile = 'administrador', result?: WebActionResult, denied = false) {
  const calls: any[][] = []; const auth: string[] = [];
  const session = { client: {}, user: { id }, profile: { id, nome: 'Pessoa', perfil: profile }, sso: { sessionHash: 'hash', bindingId: id, subject: id, capabilities: ['em.portal.read', 'em.catalogs.manage'] } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createCatalogActions({
    actionUser: async capability => { auth.push(capability); return denied ? { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' } : session; },
    mutate: async (...args) => { calls.push(args); return result ?? { ok: true, data: { operation: args[1], id, projeto_id: null, updated_at: version, record: { id }, idempotent_replay: false } }; },
  });
  return { ...actions, calls, auth, session };
}
test('catalog writes require explicit capability and an administrator before executing any mutation', async () => {
  for (const fixture of [setup('auditor'), setup('padr_o'), setup('administrador', undefined, true)]) {
    assert.equal((await fixture.saveCatalog(request)).ok, false);
    assert.equal((await fixture.deleteCatalog({ ...request, changes: undefined })).ok, false);
    assert.deepEqual(fixture.auth, ['em.catalogs.manage', 'em.catalogs.manage']); assert.deepEqual(fixture.calls, []);
  }
});
test('catalog action passes the exact stable protocol, version and normalized payload to the common BFF mutation path', async () => {
  const fixture = setup();
  const input = { ...request, changes: { nome: ' Cliente ', codigo: ' ' } };
  assert.equal((await fixture.saveCatalog(input)).ok, true); assert.equal((await fixture.saveCatalog(input)).ok, true);
  assert.equal(fixture.calls[0][1], 'save_catalog'); assert.equal(fixture.calls[0][3], 'em.catalogs.manage');
  assert.deepEqual(fixture.calls[0][2], { ...request, changes: { nome: 'Cliente', codigo: null } });
  assert.deepEqual(fixture.calls[0], fixture.calls[1]);
  assert.equal((await fixture.saveCatalog({ ...request, actor_id: id })).ok, false); assert.equal(fixture.calls.length, 2);
});
test('delete supports replay snapshots and preserves definitive and uncertain error codes', async () => {
  const body = { submissionId: id, id, kind: 'types', expected_updated_at: version };
  const replay = setup('administrador', { ok: true, data: { operation: 'delete_catalog', id, projeto_id: null, updated_at: version, record: { id, nome: 'Motor' }, idempotent_replay: true } });
  const result = await replay.deleteCatalog(body); assert.ok(result.ok); assert.equal(result.data.idempotent_replay, true);
  assert.deepEqual(replay.calls[0][2], body);
  for (const code of ['23503', '23505', 'PT409', 'UNAVAILABLE']) {
    const failure = await setup('administrador', { ok: false, code, error: 'Sanitized' }).deleteCatalog(body);
    assert.ok(!failure.ok); assert.equal(failure.code, code);
  }
});
