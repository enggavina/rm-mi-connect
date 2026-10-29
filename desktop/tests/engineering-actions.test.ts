import test from 'node:test';
import assert from 'node:assert/strict';
import { createEngineeringActions } from '../src/server/web/engineering-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
const id = '00000000-0000-4000-8000-000000000001';
const version = '2026-10-29T18:03:24.123456+00:00';
const body = { submissionId: id, id, celula_id: id, tipo_equipamento_id: id, expected_updated_at: version, changes: { ativo: false } };
function fixture(profile = 'administrador', failure?: string) {
  const calls: any[][] = []; const auth: string[] = [];
  const session = { client: {}, user: { id }, profile: { id, nome: 'Pessoa', perfil: profile }, sso: { sessionHash: 'hash', bindingId: id, subject: id, capabilities: ['em.portal.read', 'em.engineering.manage'] } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createEngineeringActions({
    actionUser: async capability => { auth.push(capability); return failure === 'CORP_FORBIDDEN' ? { ok: false, code: failure, error: 'Denied' } : session; },
    mutate: async (...args) => { calls.push(args); return failure ? { ok: false, code: failure, error: 'Sanitized' } : { ok: true, data: { operation: args[1], id, projeto_id: null, updated_at: version, record: { id }, idempotent_replay: false } } as WebActionResult; },
  });
  return { ...actions, calls, auth };
}
test('engineering mutations require their dedicated capability and administrator role', async () => {
  for (const f of [fixture('auditor'), fixture('padr_o'), fixture('administrador', 'CORP_FORBIDDEN')]) {
    assert.equal((await f.saveEngineering(body)).ok, false);
    assert.deepEqual(f.auth, ['em.engineering.manage']); assert.equal(f.calls.length, 0);
  }
});
test('matrix and title writes use the shared BFF with stable payloads and preserve uncertain/conflict codes', async () => {
  const f = fixture();
  await f.saveEngineering(body); await f.saveEngineering(body);
  assert.deepEqual(f.calls[0], f.calls[1]); assert.equal(f.calls[0][1], 'save_engineering');
  assert.equal(f.calls[0][3], 'em.engineering.manage'); assert.deepEqual(f.calls[0][2], body);
  const title = { submissionId: id, id, expected_updated_at: version, changes: { titulo: 'Vista' } };
  await f.savePhotoTitle(title); assert.equal(f.calls[2][1], 'save_photo_title'); assert.deepEqual(f.calls[2][2], title);
  await f.saveEngineering({ ...body, actor_id: id }); assert.equal(f.calls.length, 3);
  for (const code of ['PT409', '23503', '23505', 'UNAVAILABLE']) {
    const result = await fixture('administrador', code).saveEngineering(body); assert.ok(!result.ok); assert.equal(result.code, code);
  }
});
