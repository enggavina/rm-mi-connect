import test from 'node:test';
import assert from 'node:assert/strict';
import { ssoFlowSchema, ssoSessionSchema } from '../src/server/web/sso-envelopes';
import { CORPORATE_CAPABILITIES, CORPORATE_ISSUER } from '../src/server/web/sso-policy';

const subject = '00000000-0000-4000-8000-000000000001';
const corporate = { accessToken: 'synthetic-test-token-'.repeat(4), user: { id: subject, email: 'person@mielectric.com.br' }, expiresAt: 20_000,
  decision: { application: 'em', issuer: CORPORATE_ISSUER, subject, app_access: true, capabilities: ['em.portal.read'], all_employees: false, fields: [], export_allowed: false } };
const contents = { corporate, localToken: 'synthetic-local-token-'.repeat(4), localSessionId: subject, expiresAt: 10_000,
  binding: { binding_id: subject, auth_user_id: subject, rm_user_id: subject, profile: { id: subject, nome: 'Person', perfil: 'auditor' } } };

test('server envelopes preserve their identity binding and cannot lengthen a corporate session', () => {
  assert.equal(ssoSessionSchema.safeParse(contents).success, true);
  for (const invalid of [
    { ...contents, expiresAt: 20_001 },
    { ...contents, expiresAt: Infinity },
    { ...contents, localSessionId: 'not-a-session' },
    { ...contents, corporate: { ...corporate, user: { ...corporate.user, id: '00000000-0000-4000-8000-000000000002' } } },
    { ...contents, binding: { ...contents.binding, profile: { ...contents.binding.profile, id: '00000000-0000-4000-8000-000000000002' } } },
  ]) assert.equal(ssoSessionSchema.safeParse(invalid).success, false);
});

test('pending MFA requires bounded attempts, UUID factors and a complete encrypted handoff', () => {
  const flow = { kind: 'local-mfa', contents, factors: [{ id: subject, name: 'Authenticator' }], expiresAt: 9_000, attempts: 0 };
  assert.equal(ssoFlowSchema.safeParse(flow).success, true);
  for (const invalid of [{ ...flow, attempts: NaN }, { ...flow, attempts: -1 }, { ...flow, attempts: 6 },
    { ...flow, factors: [] }, { ...flow, factors: [{ id: '../factor', name: 'Invalid' }] }, { ...flow, contents: {} }]) {
    assert.equal(ssoFlowSchema.safeParse(invalid).success, false);
  }
});

test('catalog capability is accepted in encrypted sessions and MFA without invalidating previous grants', () => {
  const expanded = { ...contents, corporate: { ...corporate, decision: { ...corporate.decision, capabilities: [...CORPORATE_CAPABILITIES] } } };
  assert.ok(CORPORATE_CAPABILITIES.includes('em.catalogs.manage'));
  assert.equal(ssoSessionSchema.safeParse(expanded).success, true);
  assert.equal(ssoSessionSchema.safeParse({ ...expanded, corporate: { ...expanded.corporate, decision: { ...expanded.corporate.decision, capabilities: CORPORATE_CAPABILITIES.filter(cap => cap !== 'em.catalogs.manage') } } }).success, true);
  assert.equal(ssoFlowSchema.safeParse({ kind: 'corporate-mfa', corporate: expanded.corporate, factors: [{ id: subject, name: 'MFA' }], expiresAt: 10_000, attempts: 0 }).success, true);
  assert.equal(ssoSessionSchema.safeParse({ ...expanded, corporate: { ...expanded.corporate, decision: { ...expanded.corporate.decision, capabilities: [...CORPORATE_CAPABILITIES, 'em.unknown.manage'] } } }).success, false);
});

test('fourteen-capability engineering consumer accepts old twelve-capability sessions but never unknown scopes', () => {
  assert.equal(CORPORATE_CAPABILITIES.length, 14);
  const decision = { ...corporate.decision, capabilities: [...CORPORATE_CAPABILITIES] };
  const full = { ...contents, corporate: { ...corporate, decision } };
  assert.equal(ssoSessionSchema.safeParse(full).success, true);
  const previous = { ...full, corporate: { ...full.corporate, decision: { ...decision, capabilities: CORPORATE_CAPABILITIES.filter(cap => !cap.startsWith('em.engineering.')) } } };
  assert.equal(ssoSessionSchema.safeParse(previous).success, true);
  assert.equal(ssoFlowSchema.safeParse({ kind: 'corporate-mfa', corporate: full.corporate, factors: [{ id: subject, name: 'MFA' }], expiresAt: 10_000, attempts: 0 }).success, true);
});
