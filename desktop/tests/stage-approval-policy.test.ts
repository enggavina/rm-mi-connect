import test from 'node:test';
import assert from 'node:assert/strict';
import { transitionStageApprovalSchema } from '../src/server/web/stage-approval-policy';
import { createStageApprovalActions } from '../src/server/web/stage-approval-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00', cellVersion = '2026-10-29T18:03:25.654321+00:00';
const request = { submissionId: id(1), aprovacao_etapa_id: id(2), expected_updated_at: version, expected_cell_updated_at: cellVersion, acao: 'liberar', observacao: '' };

test('stage decisions require both exact versions and an actor-free bounded payload', () => {
  assert.deepEqual(transitionStageApprovalSchema.parse(request), request);
  for (const acao of ['liberar', 'retornar', 'aprovar']) assert.equal(transitionStageApprovalSchema.safeParse({ ...request, acao, observacao: 'Contexto' }).success, true);
  for (const invalid of [
    { ...request, acao: 'finalizar_ciclo' }, { ...request, aprovacao_etapa_id: 'invalid' },
    { ...request, actor_id: id(3) }, { ...request, p_operador_id: id(3) },
    { ...request, expected_updated_at: null }, { ...request, expected_cell_updated_at: null },
    { ...request, expected_updated_at: '2026-10-29' }, { ...request, expected_cell_updated_at: 'not-a-date' },
    { ...request, observacao: 'a'.repeat(10_001) }, { ...request, record: { status: 'aprovado' } },
  ]) assert.equal(transitionStageApprovalSchema.safeParse(invalid).success, false);
  assert.equal(transitionStageApprovalSchema.safeParse({ ...request, observacao: 'a'.repeat(10_000) }).success, true);
});

test('only returning requires a substantive observation and no transformation changes a retry body', () => {
  for (const observacao of [null, '', '  \n\t ']) assert.equal(transitionStageApprovalSchema.safeParse({ ...request, acao: 'retornar', observacao }).success, false);
  for (const acao of ['liberar', 'aprovar']) assert.equal(transitionStageApprovalSchema.safeParse({ ...request, acao, observacao: null }).success, true);
  const withReason = { ...request, acao: 'retornar', observacao: '  Corrigir equipamento  ' };
  assert.deepEqual(transitionStageApprovalSchema.parse(withReason), withReason);
});

function setup(profile = 'administrador', denied = false, result?: WebActionResult) {
  const calls: any[][] = [], auth: string[] = [];
  const access = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Pessoa', perfil: profile },
    sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities: ['em.portal.read', 'em.approvals.decide'] } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createStageApprovalActions({
    actionUser: async capability => { auth.push(capability); return denied ? { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' } : access; },
    mutate: async (...args) => { calls.push(args); return result ?? { ok: true, data: { operation: args[1], id: id(2), projeto_id: id(4), updated_at: version, record: { raw: 'private-receipt' }, idempotent_replay: false } }; },
  });
  return { ...actions, auth, calls };
}

test('stage mutation has its own live corporate grant and rejects read-only profiles before touching SQL', async () => {
  for (const fixture of [setup('auditor'), setup('mobile'), setup('administrador', true)]) {
    assert.equal((await fixture.transitionStageApproval(request)).ok, false);
    assert.deepEqual(fixture.auth, ['em.approvals.decide']); assert.deepEqual(fixture.calls, []);
  }
  for (const profile of ['administrador', 'padr_o']) {
    const fixture = setup(profile); assert.equal((await fixture.transitionStageApproval(request)).ok, true);
    assert.equal(fixture.calls[0][1], 'transition_stage_approval');
    assert.equal(fixture.calls[0][3], 'em.approvals.decide');
  }
});

test('stage action preserves the UUID/body/version for retry while SQL independently authorizes the actor', async () => {
  const fixture = setup('padr_o');
  await fixture.transitionStageApproval(request); await fixture.transitionStageApproval(request);
  assert.deepEqual(fixture.calls[0], fixture.calls[1]); assert.deepEqual(fixture.calls[0][2], request);
  assert.equal((await fixture.transitionStageApproval({ ...request, operator_id: id(9) })).ok, false);
  assert.equal(fixture.calls.length, 2);
});

test('stage action sanitizes successful SQL envelopes without losing replay or definitive failure codes', async () => {
  const raw: any = { ok: true, data: { operation: 'transition_stage_approval', id: id(2), projeto_id: id(4), updated_at: version,
    record: { secret: 'private-record' }, secret: 'private-receipt', snapshot: { token: 'private-auth' }, idempotent_replay: true } };
  const result = await setup('administrador', false, raw).transitionStageApproval(request);
  assert.ok(result.ok); assert.equal(result.data.idempotent_replay, true); assert.deepEqual(result.data.record, {});
  assert.ok(!/private|secret|token|snapshot/.test(JSON.stringify(result)));
  for (const code of ['PT409', '42501', '23505', 'UNAVAILABLE']) {
    const failure = await setup('administrador', false, { ok: false, code, error: 'Sanitized' }).transitionStageApproval(request);
    assert.ok(!failure.ok); assert.equal(failure.code, code);
  }
  raw.data.id = id(10);
  const mismatch = await setup('administrador', false, raw).transitionStageApproval(request);
  assert.ok(!mismatch.ok); assert.equal(mismatch.code, 'UNAVAILABLE');
});
