import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectDossierActions } from '../src/server/web/project-dossier-mutations';
import { addProjectCommentSchema } from '../src/server/web/project-dossier-policy';
import { freezeEngineeringRequest } from '../src/components/web/engineering-model';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00';
const input = { submissionId: id(1), projeto_id: id(2), celula_projeto_id: id(3),
  expected_project_updated_at: version, expected_allocation_updated_at: version, evento: 'Observação da equipe na célula.' };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.projects.manage', 'em.planning.read', 'em.history.read'];
type Options = { role?: string; capabilities?: CorporateCapability[]; failure?: string; patch?: (value: WebActionResult) => WebActionResult };

function fixture(options: Options = {}) {
  const auth: string[] = [], calls: any[][] = [], capabilities = options.capabilities ?? caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role ?? 'administrador' },
    sso: { sessionHash: 'session', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createProjectDossierActions({
    actionUser: async capability => { auth.push(capability); return capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' }; },
    mutate: async (...args) => {
      calls.push(args); const request = args[2];
      const result: WebActionResult = options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'add_project_comment', id: request.submissionId, projeto_id: id(2), updated_at: version, idempotent_replay: calls.length > 1,
        record: { projeto_id: id(2), celula_projeto_id: id(3), cadastrado_por_id: id(11), evento: request.evento,
          private_payload: 'must not be exposed', actor_auth_user_id: id(10), internal_history: ['private'] },
      } };
      return options.patch ? options.patch(result) : result;
    },
  });
  return { ...actions, calls, auth };
}

test('project comments require the exact allocated destination and versions without accepting injected authors or configuration', async () => {
  assert.deepEqual(addProjectCommentSchema.parse(input), input);
  assert.equal(addProjectCommentSchema.parse({ ...input, evento: '  Observação  ' }).evento, 'Observação');
  const invalid = [
    { ...input, celula_projeto_id: undefined }, { ...input, celula_projeto_id: null }, { ...input, celula_projeto_id: id(1).toUpperCase().replace('0000', 'bad!') },
    { ...input, expected_project_updated_at: null }, { ...input, expected_allocation_updated_at: 'yesterday' },
    { ...input, evento: '   ' }, { ...input, evento: 'a'.repeat(10_001) }, { ...input, evento: 'text\u0000hidden' },
    ...['actor_id', 'cadastrado_por_id', 'created_by', 'created_at', 'celula_id', 'status', 'visibilidade', 'retirada'].map(key => ({ ...input, [key]: id(99) })),
  ];
  for (const value of invalid) {
    assert.equal(addProjectCommentSchema.safeParse(value).success, false);
    const f = fixture(), result = await f.addProjectComment(value);
    assert.ok(!result.ok); assert.equal(result.code, 'INVALID_INPUT'); assert.equal(f.calls.length, 0);
  }
});

test('comment authorization precedes mutation and requires management plus project, planning and history visibility', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ role: 'mobile' }), ...caps.map(capability => fixture({ capabilities: caps.filter(value => value !== capability) })),
    fixture({ capabilities: ['em.engineering.manage', 'em.approvals.decide', 'em.documents.read'] })]) {
    const result = await f.addProjectComment(input);
    assert.ok(!result.ok); assert.deepEqual(f.auth, ['em.projects.manage']); assert.equal(f.calls.length, 0);
  }
  const unauthorized = fixture({ capabilities: [] }), invalid = await unauthorized.addProjectComment({});
  assert.ok(!invalid.ok); assert.equal(invalid.code, 'CORP_FORBIDDEN'); assert.equal(invalid.fieldErrors, undefined);
  const standard = fixture({ role: 'padr_o' }); assert.equal((await standard.addProjectComment(input)).ok, true);
});

test('comment retries preserve the frozen UUID, microsecond versions, intended text and current SSO context', async () => {
  const f = fixture(), frozen = freezeEngineeringRequest(input);
  const first = await f.addProjectComment(frozen), replay = await f.addProjectComment(frozen);
  assert.ok(first.ok && replay.ok); assert.equal(replay.data.idempotent_replay, true);
  assert.deepEqual(f.calls[0], f.calls[1]); assert.deepEqual(f.calls[0][2], input);
  assert.equal(f.calls[0][1], 'add_project_comment'); assert.equal(f.calls[0][3], 'em.projects.manage');
  assert.equal(f.calls[0][4].subject, id(13)); assert.equal(f.calls[0][2].expected_allocation_updated_at, version);
  assert.deepEqual(first.data.record, { projeto_id: id(2), celula_projeto_id: id(3), cadastrado_por_id: id(11), evento: input.evento });
  assert.equal('actor_auth_user_id' in first.data.record, false); assert.equal('private_payload' in first.data.record, false);
});

test('comment gateway conflicts, expired authorization and uncertain confirmation keep their existing error semantics', async () => {
  for (const code of ['PT409', 'P0002', '22023', '42501', 'UNAVAILABLE', 'CORP_UNAVAILABLE']) {
    const f = fixture({ failure: code }), result = await f.addProjectComment(input);
    assert.ok(!result.ok); assert.equal(result.code, code); assert.equal(result.error, 'Sanitized'); assert.equal(f.calls.length, 1);
  }
});

test('unrelated or malformed comment receipts cannot confirm another project, destination, author or text', async () => {
  for (const patch of [
    { operation: 'plan_cell' }, { id: id(99) }, { projeto_id: id(99) }, { updated_at: 'invalid' }, { idempotent_replay: null },
    { record: null }, { record: undefined }, { record: [] },
    ...['projeto_id', 'celula_projeto_id', 'cadastrado_por_id'].map(key => ({ nested: { [key]: id(99) } })),
    { nested: { evento: 'A different comment' } },
  ]) {
    const f = fixture({ patch: result => result.ok ? { ok: true, data: { ...result.data, ...patch,
      ...('nested' in patch ? { record: { ...result.data.record, ...patch.nested } } : {}) } } as unknown as WebActionResult : result });
    const result = await f.addProjectComment(input);
    assert.ok(!result.ok); assert.equal(result.code, 'UNAVAILABLE'); assert.equal('data' in result, false);
  }
});
