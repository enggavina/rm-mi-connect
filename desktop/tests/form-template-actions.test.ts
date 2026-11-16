import test from 'node:test';
import assert from 'node:assert/strict';
import { createFormTemplateActions } from '../src/server/web/form-template-mutations';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
const content = { titulo: '', descricao: null, title: null, description: null, tipo: null, questions: [] };
const draft = { id: id(1), kind: 'new', state: 'draft', family_id: null, source_form_id: null, source_version: null, content,
  source_snapshot: { usa_aprovacao: true, imagem_capa_url: 'https://private.invalid/cover?token=secret', celulas_ids: [id(2)], equipes_ids: [] },
  created_at: version, updated_at: version, published_form_id: null, created_by: 'private-actor' };
function setup(profile = 'administrador', result?: WebActionResult, denied = false) {
  const calls: any[][] = []; const auth: string[] = [];
  const session = { client: {}, user: { id: id(8) }, profile: { id: id(8), nome: 'Pessoa', perfil: profile },
    sso: { sessionHash: 'hash', bindingId: id(8), subject: id(8), capabilities: ['em.portal.read', 'em.form_templates.manage'] } } as Awaited<ReturnType<typeof actionUser>>;
  const actions = createFormTemplateActions({
    actionUser: async capability => { auth.push(capability); return denied ? { ok: false, code: 'CORP_FORBIDDEN', error: 'Denied' } : session; },
    mutate: async (...args) => { calls.push(args); return result ?? { ok: true, data: { operation: args[1], id: id(1), projeto_id: null, updated_at: version, record: draft, idempotent_replay: false } }; },
  });
  return { ...actions, calls, auth };
}

test('builder requires its explicit capability plus administrator for every operation', async () => {
  for (const fixture of [setup('auditor'), setup('padr_o'), setup('administrador', undefined, true)]) {
    for (const execute of [fixture.createFormTemplate, fixture.saveFormTemplate, fixture.publishFormTemplate]) assert.equal((await execute({})).ok, false);
    assert.deepEqual(fixture.auth, Array(3).fill('em.form_templates.manage')); assert.deepEqual(fixture.calls, []);
  }
});

test('builder preserves stable submission/version and rejects actor or source metadata injection', async () => {
  const fixture = setup(); const body = { submissionId: id(9), id: id(1), expected_updated_at: version, content };
  assert.equal((await fixture.saveFormTemplate(body)).ok, true); assert.equal((await fixture.saveFormTemplate(body)).ok, true);
  assert.deepEqual(fixture.calls[0], fixture.calls[1]); assert.deepEqual(fixture.calls[0][2], body);
  assert.equal(fixture.calls[0][1], 'save_form_template'); assert.equal(fixture.calls[0][3], 'em.form_templates.manage');
  for (const bad of [{ ...body, actor_id: id(2) }, { ...body, content: { ...content, source_snapshot: draft.source_snapshot } }]) assert.equal((await fixture.saveFormTemplate(bad)).ok, false);
  assert.equal(fixture.calls.length, 2);
});

test('every successful action strips raw snapshot/publication, cover URLs and actor fields from SQL result', async () => {
  const raw: any = { ok: true, data: { operation: 'publish_form_template', id: id(1), projeto_id: null, updated_at: version,
    record: { ...draft, state: 'published', published_form_id: id(3) }, snapshot: { draft }, publication: { unsafe: draft.source_snapshot }, idempotent_replay: true, secret: 'private-top-level' } };
  const fixture = setup('administrador', raw);
  const requests = [
    [fixture.createFormTemplate, { submissionId: id(9), id: id(1), source_form_id: null, kind: 'new' }],
    [fixture.saveFormTemplate, { submissionId: id(9), id: id(1), expected_updated_at: version, content }],
    [fixture.publishFormTemplate, { submissionId: id(9), id: id(1), expected_updated_at: version }],
  ] as const;
  for (const [action, body] of requests) {
    const result = await action(body); assert.ok(result.ok);
    assert.equal(result.data.idempotent_replay, true); assert.equal(result.data.record.published_form_id, id(3));
    assert.deepEqual(result.data.record.source_snapshot, { usa_aprovacao: true, has_cover: true, celulas_ids: [id(2)], equipes_ids: [] });
    assert.ok(!/private|token|imagem_capa_url|created_by|unsafe/.test(JSON.stringify(result)));
    assert.equal(Object.hasOwn(result.data, 'snapshot'), false); assert.equal(Object.hasOwn(result.data, 'publication'), false);
  }
});

test('definitive conflicts remain distinct from uncertain malformed responses for safe replay', async () => {
  const body = { submissionId: id(9), id: id(1), expected_updated_at: version };
  for (const code of ['23503', '23505', 'PT409', 'UNAVAILABLE']) {
    const result = await setup('administrador', { ok: false, code, error: 'Sanitized' }).publishFormTemplate(body);
    assert.ok(!result.ok); assert.equal(result.code, code);
  }
  const malformed = await setup('administrador', { ok: true, data: { operation: 'publish_form_template', id: id(1), projeto_id: null, updated_at: version, record: {}, idempotent_replay: false } }).publishFormTemplate(body);
  assert.ok(!malformed.ok); assert.equal(malformed.code, 'UNAVAILABLE');
});

test('template deletion requires explicit confirmation, exact target/version, capability and administrator', async () => {
  const body = { submissionId: id(9), id: id(1), kind: 'form', expected_updated_at: version, confirmed: true };
  for (const fixture of [setup('auditor'), setup('padr_o'), setup('administrador', undefined, true)]) {
    assert.equal((await fixture.deleteFormTemplate(body)).ok, false); assert.deepEqual(fixture.calls, []);
    assert.deepEqual(fixture.auth, ['em.form_templates.manage']);
  }
  const fixture = setup();
  for (const bad of [{ ...body, confirmed: false }, { ...body, confirmed: undefined }, { ...body, kind: 'family' }, { ...body, expected_updated_at: '' }, { ...body, actor_id: id(4) }]) {
    assert.equal((await fixture.deleteFormTemplate(bad)).ok, false);
  }
  assert.deepEqual(fixture.calls, []);
});

test('deletion keeps frozen retry context and never forwards private deletion audit or source URLs', async () => {
  const body = { submissionId: id(9), id: id(1), kind: 'form', expected_updated_at: version, confirmed: true };
  const fixture = setup('administrador', { ok: true, data: { operation: 'delete_form_template', id: id(1), projeto_id: null,
    updated_at: version, idempotent_replay: true, record: { id: id(1), kind: 'form', deleted: true, private_audit: draft } } });
  const result = await fixture.deleteFormTemplate(body); assert.ok(result.ok);
  assert.deepEqual(result.data.record, { id: id(1), kind: 'form', deleted: true });
  assert.equal(result.data.idempotent_replay, true);
  assert.ok((await fixture.deleteFormTemplate(body)).ok); assert.deepEqual(fixture.calls[0], fixture.calls[1]);
  const invalid = setup('administrador', { ok: true, data: { ...result.data, record: { id: id(2), kind: 'form', deleted: true } } });
  assert.equal((await invalid.deleteFormTemplate(body)).ok, false);
  const used = await setup('administrador', { ok: false, code: '23503', error: 'raw' }).deleteFormTemplate(body);
  assert.ok(!used.ok); assert.equal(used.code, '23503'); assert.match(used.error, /histórico/);
});

test('deletion canonicalizes a UUID from a mixed-case route before checking the acknowledgement', async () => {
  const target = 'abcdefab-cdef-4abc-8abc-abcdefabcdef';
  const fixture = setup('administrador', { ok: true, data: { operation: 'delete_form_template', id: target, projeto_id: null,
    updated_at: version, idempotent_replay: false, record: { id: target, kind: 'form', deleted: true } } });
  const result = await fixture.deleteFormTemplate({ submissionId: id(9), id: target.toUpperCase(), kind: 'form', expected_updated_at: version, confirmed: true });
  assert.ok(result.ok); assert.equal(fixture.calls[0][2].id, target);
});
