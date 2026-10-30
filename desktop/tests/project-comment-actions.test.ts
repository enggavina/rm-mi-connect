import test from 'node:test';
import assert from 'node:assert/strict';
import { createProjectCommentActions } from '../src/server/web/project-comment-mutations';
import { editProjectCommentSchema } from '../src/server/web/project-comment-policy';
import { freezeEngineeringRequest } from '../src/components/web/engineering-model';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', hash = 'a'.repeat(64);
const input = { submissionId: id(1), projeto_id: id(2), comentario_id: id(3), expected_project_updated_at: version,
  expected_comment_updated_at: version, expected_context_version: hash, evento: 'Texto corrigido\ncom informação técnica.',
  motivo: 'Correção da descrição após conferência.', confirm_change: true as const };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.history.read', 'em.projects.manage'];
type Options = { role?: string; capabilities?: CorporateCapability[]; failure?: string; changed?: boolean; revision?: number;
  timestamp?: string; patch?: (value: WebActionResult) => WebActionResult };
function fixture(options: Options = {}) {
  const auth: string[] = [], calls: any[][] = [], capabilities = options.capabilities ?? caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role ?? 'administrador' },
    sso: { sessionHash: 'session', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createProjectCommentActions({
    actionUser: async capability => { auth.push(capability); return capabilities.includes(capability) ? access : { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' }; },
    mutate: async (...args) => {
      calls.push(args); const request = args[2];
      const result = (options.failure ? { ok: false, code: options.failure, error: 'Sanitized' } : { ok: true, data: {
        operation: 'edit_project_comment', id: request.comentario_id, projeto_id: request.projeto_id,
        updated_at: options.timestamp ?? version, idempotent_replay: calls.length > 1,
        record: { projeto_id: request.projeto_id, comentario_id: request.comentario_id, project_updated_at: version,
          changed: options.changed ?? true, revision: options.revision ?? 1, context_version: hash,
          private_audit: { auth_user_id: id(10), before_record: 'private' }, full_receipt: 'private' },
        private_journal: 'not public', actor_auth_user_id: id(10),
      } }) as WebActionResult;
      return options.patch ? options.patch(result) : result;
    },
  });
  return { ...actions, calls, auth };
}

test('comment corrections accept only text and reason, trim edges and preserve internal formatting', async () => {
  const f = fixture(), result = await f.editProjectComment({ ...input, evento: `  ${input.evento}  `, motivo: `\n ${input.motivo} \n` });
  assert.ok(result.ok); assert.deepEqual(f.calls[0][2], input);
  assert.equal(editProjectCommentSchema.parse({ ...input, evento: 'x'.repeat(10_000), motivo: 'm'.repeat(2000) }).evento.length, 10_000);
  const noIdentityChanges = f.calls[0][2];
  for (const key of ['cadastrado_por_id', 'celula_id', 'created_at', 'bubble_id']) assert.equal(Object.hasOwn(noIdentityChanges, key), false);
});

test('comment correction rejects missing confirmation, invalid versions and any attempt to alter identities or recipient', async () => {
  const invalid: unknown[] = [null, {}, [],
    ...['id', 'actor_id', 'auth_user_id', 'cadastrado_por_id', 'celula_id', 'celula_projeto_id', 'created_at', 'updated_at', 'bubble_id', 'sync_source', 'private_journal']
      .map(key => ({ ...input, [key]: id(99) })),
    ...['submissionId', 'projeto_id', 'comentario_id'].map(key => ({ ...input, [key]: 'invalid' })),
    ...['evento', 'motivo'].flatMap(key => ['', '  \n\t', null, undefined, 42, ['value'], 'before' + String.fromCharCode(0) + 'after'].map(value => ({ ...input, [key]: value }))),
    { ...input, evento: 'x'.repeat(10_001) }, { ...input, motivo: 'x'.repeat(2001) },
    ...[false, 'true', 1, null, undefined].map(confirm_change => ({ ...input, confirm_change })),
    ...['expected_project_updated_at', 'expected_comment_updated_at'].flatMap(key => ['2026-10-30', '2026-10-30T15:30:02', null, undefined].map(value => ({ ...input, [key]: value }))),
    ...['a'.repeat(63), 'g'.repeat(64), hash.toUpperCase(), null, undefined].map(expected_context_version => ({ ...input, expected_context_version })),
  ];
  for (const request of invalid) {
    const f = fixture(), result = await f.editProjectComment(request);
    assert.ok(!result.ok, JSON.stringify(request)); assert.equal(result.code, 'INVALID_INPUT'); assert.equal(f.calls.length, 0);
  }
});

test('comment corrections check current management and reading scopes before parsing without prefetching another author', async () => {
  for (const f of [fixture({ role: 'auditor' }), fixture({ role: 'mobile' }), fixture({ role: 'supervisor' }),
    ...caps.map(capability => fixture({ capabilities: caps.filter(value => value !== capability) })),
    fixture({ capabilities: ['em.portal.read', 'em.projects.read', 'em.history.read', 'em.approvals.decide'] })]) {
    const result = await f.editProjectComment(input); assert.ok(!result.ok);
    assert.deepEqual(f.auth, ['em.projects.manage']); assert.equal(f.calls.length, 0);
  }
  const denied = await fixture({ capabilities: [] }).editProjectComment({});
  assert.ok(!denied.ok); assert.equal(denied.code, 'CORP_FORBIDDEN'); assert.equal(denied.fieldErrors, undefined);
  for (const role of ['administrador', 'padr_o']) {
    const f = fixture({ role }); assert.equal((await f.editProjectComment(input)).ok, true);
    assert.equal(f.calls.length, 1, 'author ownership is revalidated in the SQL transaction, not by a separate BFF read');
  }
});

test('comment correction retries carry one exact UUID, microsecond context, intent and current SSO binding', async () => {
  const f = fixture(), frozen = freezeEngineeringRequest({ ...input, submissionId: input.submissionId.toUpperCase(),
    projeto_id: input.projeto_id.toUpperCase(), comentario_id: input.comentario_id.toUpperCase() });
  const first = await f.editProjectComment(frozen), retry = await f.editProjectComment(frozen);
  assert.ok(first.ok && retry.ok); assert.equal(retry.data.idempotent_replay, true); assert.deepEqual(f.calls[0], f.calls[1]);
  assert.deepEqual(f.calls[0][2], input); assert.equal(f.calls[0][1], 'edit_project_comment'); assert.equal(f.calls[0][3], 'em.projects.manage');
  assert.equal(f.calls[0][4].bindingId, id(12)); assert.equal(f.calls[0][4].subject, id(13));
  assert.deepEqual(Object.keys(first.data).sort(), ['id', 'idempotent_replay', 'operation', 'projeto_id', 'record', 'updated_at']);
  assert.deepEqual(first.data.record, { projeto_id: id(2), comentario_id: id(3), project_updated_at: version,
    changed: true, revision: 1, context_version: hash });
  assert.ok(!JSON.stringify(first).includes('private')); assert.equal(Object.hasOwn(first.data, 'actor_auth_user_id'), false);
});

test('comment no-op accepts equivalent PostgreSQL timestamp notation without losing fractional precision', async () => {
  for (const expected_comment_updated_at of ['2026-10-30T15:30:02.123456Z', '2026-10-30T12:30:02.123456-03:00', version]) {
    for (const revision of [0, 3]) {
      const f = fixture({ changed: false, revision }), result = await f.editProjectComment({ ...input, expected_comment_updated_at });
      assert.ok(result.ok, expected_comment_updated_at); assert.equal(result.data.record.changed, false); assert.equal(result.data.record.revision, revision);
      assert.equal(result.data.updated_at, version); assert.equal(f.calls[0][2].expected_comment_updated_at, expected_comment_updated_at);
    }
  }
});

test('comment corrections preserve conflict, current authorization, unavailable and idempotency errors', async () => {
  for (const code of ['PT409', 'P0002', '22023', '23505', '42501', 'UNAVAILABLE', 'CORP_UNAVAILABLE', 'CORP_FORBIDDEN']) {
    const f = fixture({ failure: code }), result = await f.editProjectComment(input);
    assert.ok(!result.ok); assert.equal(result.code, code); assert.equal(result.error, 'Sanitized'); assert.equal(f.calls.length, 1);
  }
});

test('comment correction never confirms a receipt for another project/comment or exposes private before/after data', async () => {
  const patches = [{ operation: 'add_project_comment' }, { id: id(99) }, { id: 'invalid' }, { projeto_id: id(99) },
    { updated_at: 'invalid' }, { idempotent_replay: 'true' }, { record: null }, { record: [] },
    ...['projeto_id', 'comentario_id'].flatMap(key => [{ nested: { [key]: id(99) } }, { nested: { [key]: 'invalid' } }]),
    { nested: { project_updated_at: 'invalid' } }, { nested: { context_version: 'wrong' } },
    { nested: { changed: 'true' } }, { nested: { changed: null } }, { nested: { revision: -1 } },
    { nested: { revision: 1.5 } }, { nested: { revision: 0, changed: true } }];
  for (const patch of patches) {
    const f = fixture({ patch: value => value.ok ? { ok: true, data: { ...value.data, ...patch,
      ...('nested' in patch ? { record: { ...value.data.record, ...patch.nested } } : {}) } } as unknown as WebActionResult : value });
    const result = await f.editProjectComment(input); assert.ok(!result.ok, JSON.stringify(patch));
    assert.equal(result.code, 'UNAVAILABLE'); assert.equal('data' in result, false);
  }
});
