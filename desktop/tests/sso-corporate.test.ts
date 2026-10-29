import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createCorporateAuth, type CorporateDependencies } from '../src/server/web/sso-corporate';
import {
  corporateSettings, CorporateAuthError, CORPORATE_CAPABILITIES, CORPORATE_FLOW_TTL_MS, CORPORATE_ISSUER,
  CORPORATE_SESSION_TTL_MS, CORPORATE_STORAGE_KEY, CORPORATE_SUPABASE_URL, validateCorporateFlow,
} from '../src/server/web/sso-policy';

const NOW = Date.parse('2026-10-29T12:00:00Z');
const SUBJECT = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const env = { EM_SSO_ENABLED: 'true', EM_CORPORATE_SUPABASE_URL: CORPORATE_SUPABASE_URL,
  EM_CORPORATE_APP_SLUG: 'em', EM_CORPORATE_PUBLISHABLE_KEY: 'sb_publishable_fictional_public_test_key', EM_PUBLIC_ORIGIN: 'https://em.example.test' };
const settings = corporateSettings(env)!;
const user = () => ({ id: SUBJECT, email: 'operator@mielectric.com.br', email_confirmed_at: '2026-01-01T12:00:00Z',
  last_sign_in_at: undefined as string | undefined,
  aud: 'authenticated', role: 'authenticated', created_at: '2026-01-01T12:00:00Z', app_metadata: { provider: 'azure', providers: ['azure'] },
  user_metadata: { full_name: 'Pessoa de teste', role: 'admin' }, identities: [{ id: OTHER, identity_id: OTHER,
    user_id: SUBJECT, provider: 'azure', updated_at: new Date(NOW).toISOString(), last_sign_in_at: undefined as string | undefined }], factors: [] as unknown[] });
function jwt(patch: Record<string, unknown> = {}) {
  const claims = { iss: CORPORATE_ISSUER, aud: 'authenticated', sub: SUBJECT, role: 'authenticated', session_id: OTHER,
    iat: NOW / 1000, exp: NOW / 1000 + 3600, aal: 'aal1', amr: [{ method: 'oauth', timestamp: NOW / 1000 }], ...patch };
  return `${Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url')}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.c2lnbmF0dXJl`;
}
const decision = () => ({ application: 'em', issuer: CORPORATE_ISSUER, subject: SUBJECT, app_access: true,
  capabilities: [...CORPORATE_CAPABILITIES], all_employees: false, fields: [], export_allowed: false });
type FixtureOptions = {
  token?: string; user?: ReturnType<typeof user>; registry?: unknown; decision?: unknown; identityStatus?: number;
  response?: (path: string) => Response | undefined; fail?: boolean;
};
function fixture(options: FixtureOptions = {}) {
  const calls: { path: string; method: string; body: any; bearer: boolean }[] = [];
  const consumed = new Set<string>(); let now = NOW; const token = options.token ?? jwt();
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input)); const headers = new Headers(init?.headers);
    assert.equal(url.origin, CORPORATE_SUPABASE_URL);
    assert.equal(init?.redirect, 'error'); assert.equal(init?.cache, 'no-store'); assert.ok(init?.signal);
    const body = typeof init?.body === 'string' ? JSON.parse(init.body) : undefined;
    calls.push({ path: url.pathname, method: init?.method || 'GET', body, bearer: headers.get('authorization') === `Bearer ${token}` });
    if (options.fail) throw new DOMException('Simulated transport timeout', 'TimeoutError');
    const overridden = options.response?.(url.pathname); if (overridden) return overridden;
    if (url.pathname === '/auth/v1/token') {
      assert.equal(url.searchParams.get('grant_type'), 'pkce');
      if (consumed.has(body.auth_code)) return Response.json({ error_code: 'flow_state_not_found', msg: 'Code already used.' }, { status: 400 });
      consumed.add(body.auth_code);
      return Response.json({ access_token: token, refresh_token: 'fictional-unused-refresh', expires_in: 3600,
        expires_at: NOW / 1000 + 3600, token_type: 'bearer', user: options.user ?? user() });
    }
    if (url.pathname === '/auth/v1/user') return options.identityStatus
      ? Response.json({ msg: 'User unavailable' }, { status: options.identityStatus }) : Response.json(options.user ?? user());
    if (url.pathname === '/rest/v1/authorized_users') {
      assert.equal(url.searchParams.get('auth_user_id'), `eq.${SUBJECT}`);
      assert.equal(url.searchParams.get('is_active'), 'eq.true'); assert.equal(url.searchParams.get('limit'), '2');
      assert.equal(url.searchParams.get('select'), 'id,email,auth_user_id,is_active');
      return Response.json(options.registry ?? [{ id: OTHER, auth_user_id: SUBJECT, email: user().email, is_active: true }]);
    }
    if (url.pathname === '/rest/v1/rpc/cp_my_permissions_v1') {
      assert.deepEqual(body, { p_app_slug: 'em' }); return Response.json(options.decision ?? decision());
    }
    assert.fail(`Unexpected corporate endpoint ${url.pathname}`);
  };
  return { auth: createCorporateAuth({ settings, fetcher, now: () => now }), calls, token, advance(ms: number) { now += ms; } };
}
function code(expected: string) { return (error: unknown) => error instanceof CorporateAuthError && error.code === expected; }

test('corporate configuration is opt-in and pins the issuer, app and exact HTTPS callback', () => {
  assert.equal(corporateSettings({}), null);
  assert.equal(settings.callbackUrl, 'https://em.example.test/auth/sso/callback');
  for (const patch of [
    { EM_CORPORATE_SUPABASE_URL: 'https://other.supabase.co' }, { EM_CORPORATE_APP_SLUG: 'mi-workshop' },
    { EM_CORPORATE_PUBLISHABLE_KEY: 'sb_secret_never-accepted' }, { EM_PUBLIC_ORIGIN: 'http://em.example.test' },
    { EM_PUBLIC_ORIGIN: 'https://user@em.example.test' }, { EM_PUBLIC_ORIGIN: 'https://em.example.test/?next=evil' },
    { EM_PUBLIC_ORIGIN: 'https://em.example.test/path' }, { EM_PUBLIC_ORIGIN: 'https://em.example.test/' },
  ]) assert.throws(() => corporateSettings({ ...env, ...patch }), code('CORP_UNCONFIGURED'));
  assert.throws(() => createCorporateAuth({ settings: { ...settings, issuer: 'https://other.example' } }), code('CORP_UNCONFIGURED'));
});

test('real SDK generates isolated PKCE slots and S256, with a fixed callback and no token URL', async () => {
  const { auth, calls } = fixture(); const a = await auth.beginCorporateFlow(), b = await auth.beginCorporateFlow();
  assert.notEqual(a.flow.flowId, b.flow.flowId); assert.notDeepEqual(a.flow.entries, b.flow.entries);
  const url = new URL(a.url); assert.equal(url.origin, CORPORATE_SUPABASE_URL); assert.equal(url.pathname, '/auth/v1/authorize');
  assert.equal(url.searchParams.get('redirect_to'), settings.callbackUrl);
  assert.equal(url.searchParams.get('provider'), 'azure'); assert.equal(url.searchParams.get('code_challenge_method'), 's256');
  const verifier = JSON.parse(a.flow.entries.find(([key]) => key === `${CORPORATE_STORAGE_KEY}-flow-${a.flow.flowId}-code-verifier`)![1]);
  assert.equal(url.searchParams.get('code_challenge'), createHash('sha256').update(verifier).digest('base64url'));
  assert.ok(!url.searchParams.has('access_token')); assert.ok(!url.searchParams.get('redirect_to')?.includes('sb_flow_id'));
  assert.deepEqual(calls, []);
});

test('exchange uses its exact verifier then fresh identity, explicit registry and current permissions', async () => {
  const { auth, calls } = fixture(); const { flow } = await auth.beginCorporateFlow();
  const result = await auth.finishCorporateFlow(flow, 'fictional-once-code', flow.flowId);
  assert.equal(result.user.id, SUBJECT); assert.equal(result.user.nome, 'Pessoa de teste'); assert.equal(result.expiresAt, NOW + 3600_000);
  assert.equal(result.decision.app_access, true); assert.equal('role' in result.user, false); assert.equal('refreshToken' in result, false);
  assert.deepEqual(calls.map(call => call.path), ['/auth/v1/token', '/auth/v1/user', '/rest/v1/authorized_users', '/rest/v1/rpc/cp_my_permissions_v1']);
  const expectedVerifier = JSON.parse(flow.entries.find(([key]) => key.includes(`-flow-${flow.flowId}-`))![1]);
  assert.equal(calls[0].body.code_verifier, expectedVerifier); assert.ok(calls.slice(1).every(call => call.bearer));
  await assert.rejects(auth.finishCorporateFlow(flow, 'fictional-once-code', flow.flowId), code('CORP_UNAUTHORIZED'));
  assert.equal(calls.filter(call => call.path === '/rest/v1/rpc/cp_my_permissions_v1').length, 1);
});

test('wrong/expired flow, missing slot and callback tampering fail before any token exchange', async () => {
  const { auth, calls, advance } = fixture(); const { flow } = await auth.beginCorporateFlow();
  await assert.rejects(auth.finishCorporateFlow(flow, 'fictional-code', 'wrong-flow-id'), code('CORP_UNAUTHORIZED'));
  await assert.rejects(auth.finishCorporateFlow(flow, 'code with spaces'), code('CORP_UNAUTHORIZED'));
  await assert.rejects(auth.finishCorporateFlow({ ...flow, entries: flow.entries.filter(([key]) => !key.includes('-flow-')) }, 'fictional-code'), code('CORP_UNAUTHORIZED'));
  assert.throws(() => validateCorporateFlow({ ...flow, entries: [...flow.entries, flow.entries[0]] }, NOW), code('CORP_UNAUTHORIZED'));
  advance(CORPORATE_FLOW_TTL_MS);
  await assert.rejects(auth.finishCorporateFlow(flow, 'fictional-code'), code('CORP_UNAUTHORIZED'));
  assert.deepEqual(calls, []);
});

test('an exchange response cannot substitute a different remotely verified subject', async () => {
  const f = fixture({ response: path => path === '/auth/v1/user' ? Response.json({ ...user(), id: OTHER }) : undefined });
  const { flow } = await f.auth.beginCorporateFlow();
  await assert.rejects(f.auth.finishCorporateFlow(flow, 'fictional-code'), code('CORP_UNAUTHORIZED'));
  assert.ok(!f.calls.some(call => call.path.startsWith('/rest/')));
});

test('unverified, revoked and unavailable identity never reach operational grants', async () => {
  for (const [status, expected] of [[401, 'CORP_UNAUTHORIZED'], [403, 'CORP_UNAUTHORIZED'], [503, 'CORP_UNAVAILABLE']] as const) {
    const f = fixture({ identityStatus: status });
    await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code(expected));
    assert.deepEqual(f.calls.map(call => call.path), ['/auth/v1/user']);
  }
});

test('issuer, audience, identity, expiry and real OAuth proof are mandatory after remote verification', async () => {
  const patches = [
    { iss: 'https://other.supabase.co/auth/v1' }, { aud: 'service_role' }, { role: 'service_role' }, { sub: OTHER },
    { session_id: 'invented' }, { exp: NOW / 1000 }, { iat: NOW / 1000 + 60 }, { aal: 'aal3' },
    { amr: [{ method: 'password', timestamp: NOW / 1000 }] },
    { amr: [{ method: 'oauth', timestamp: NOW / 1000 - 3600 }] },
    { amr: [{ method: 'oauth', timestamp: NOW / 1000 }, { method: 'magiclink', timestamp: NOW / 1000 }] },
  ];
  for (const patch of patches) {
    const f = fixture({ token: jwt(patch) });
    await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT, startedAt: NOW }), code('CORP_UNAUTHORIZED'));
    assert.ok(!f.calls.some(call => call.path.startsWith('/rest/')));
  }
});

test('Azure link, verified corporate email and recent OAuth identity are required, metadata role is irrelevant', async () => {
  for (const patch of [
    { email: 'operator@mielectric.com.br.evil.test' }, { email_confirmed_at: '' }, { is_anonymous: true }, { identities: [] },
    { identities: [{ ...user().identities[0], user_id: OTHER }] },
    { identities: [{ ...user().identities[0], updated_at: '2026-01-01T00:00:00Z' }] },
  ]) {
    const f = fixture({ user: { ...user(), ...patch } as ReturnType<typeof user> });
    await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT, startedAt: NOW }), code('CORP_UNAUTHORIZED'));
  }
  const f = fixture(); f.advance(CORPORATE_SESSION_TTL_MS);
  await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT, startedAt: NOW }), code('CORP_UNAUTHORIZED'));
});

test('registry lookup requires one active account with the same UUID and never links matching email', async () => {
  const row = { id: OTHER, email: user().email, auth_user_id: SUBJECT, is_active: true };
  for (const registry of [[], [row, row], [{ ...row, auth_user_id: null }], [{ ...row, auth_user_id: OTHER }], [{ ...row, is_active: false }]]) {
    const f = fixture({ registry });
    await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code('CORP_FORBIDDEN'));
    assert.ok(!f.calls.some(call => call.path.includes('/rpc/')));
  }
});

test('fresh Azure last_sign_in_at is accepted, while another provider cannot refresh stale Azure proof', async () => {
  const stale = '2026-01-01T00:00:00Z';
  const azure = { ...user().identities[0], updated_at: stale, last_sign_in_at: new Date(NOW).toISOString() };
  const fresh = fixture({ user: { ...user(), identities: [azure] } });
  assert.equal((await fresh.auth.validateCorporateSession(fresh.token, { subject: SUBJECT, startedAt: NOW })).user.id, SUBJECT);
  const mixed = fixture({ user: { ...user(), last_sign_in_at: new Date(NOW).toISOString(), identities: [
    { ...azure, last_sign_in_at: stale }, { ...azure, provider: 'google' },
  ] } as ReturnType<typeof user> });
  await assert.rejects(mixed.auth.validateCorporateSession(mixed.token, { subject: SUBJECT, startedAt: NOW }), code('CORP_UNAUTHORIZED'));
  await assert.rejects(mixed.auth.validateCorporateSession(mixed.token, { subject: SUBJECT }), code('CORP_UNAUTHORIZED'));
});

test('a token that expires while the current permission check is in flight never reaches the bridge', async () => {
  const f = fixture({ response: path => { if (path.includes('/rpc/')) f.advance(CORPORATE_SESSION_TTL_MS); return undefined; } });
  await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code('CORP_UNAUTHORIZED'));
});

test('central response is bound to exact app/issuer/subject and known functions, with no employee-field escalation', async () => {
  for (const patch of [
    { application: 'mi-workshop' }, { issuer: 'https://other.example/auth/v1' }, { subject: OTHER },
    { capabilities: ['em.portal.read', 'em.admin'] }, { capabilities: ['em.portal.read', 'em.portal.read'] },
    { all_employees: true }, { fields: ['cpf'] }, { export_allowed: true }, { app_access: 'true' },
  ]) {
    const f = fixture({ decision: { ...decision(), ...patch } });
    await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code('CORP_UNAVAILABLE'));
  }
});

test('each protected validation rechecks grants; portal entry never implies management authority', async () => {
  const access = decision(); const f = fixture({ decision: access });
  await f.auth.validateCorporateSession(f.token, { subject: SUBJECT }, 'em.projects.manage');
  access.capabilities = ['em.portal.read'];
  await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }, 'em.projects.manage'), code('CORP_FORBIDDEN'));
  await f.auth.validateCorporateSession(f.token, { subject: SUBJECT });
  access.app_access = false; access.capabilities = [];
  await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code('CORP_FORBIDDEN'));
  assert.equal(f.calls.filter(call => call.path.includes('/rpc/')).length, 4);
  const withoutPortal = fixture({ decision: { ...decision(), capabilities: ['em.projects.manage'] } });
  await assert.rejects(withoutPortal.auth.validateCorporateSession(withoutPortal.token, { subject: SUBJECT }, 'em.projects.manage'), code('CORP_FORBIDDEN'));
});

test('verified corporate TOTP requires AAL2 before bridging, pending token is not JSON-serializable', async () => {
  const factors = [{ id: OTHER, factor_type: 'totp', status: 'verified', friendly_name: 'Autenticador de teste' }];
  const f = fixture({ user: { ...user(), factors } });
  try { await f.auth.validateCorporateSession(f.token, { subject: SUBJECT }); assert.fail('MFA must block the bridge'); }
  catch (error) {
    assert.ok(error instanceof CorporateAuthError); assert.equal(error.code, 'CORP_MFA_REQUIRED');
    assert.equal(error.pending?.accessToken, f.token); assert.equal(error.pending?.decision.subject, SUBJECT);
    assert.deepEqual(error.factors, [{ id: OTHER, name: 'Autenticador de teste' }]);
    assert.ok(!JSON.stringify(error).includes(f.token)); assert.ok(!error.message.includes(f.token));
  }
  const aal2 = fixture({ user: { ...user(), factors }, token: jwt({ aal: 'aal2', amr: [{ method: 'oauth', timestamp: NOW / 1000 }, { method: 'mfa/totp', timestamp: NOW / 1000 }] }) });
  assert.equal((await aal2.auth.validateCorporateSession(aal2.token, { subject: SUBJECT })).user.id, SUBJECT);
  const pendingEnrollment = fixture({ user: { ...user(), factors: [{ ...factors[0], status: 'unverified' }] } });
  assert.equal((await pendingEnrollment.auth.validateCorporateSession(pendingEnrollment.token, { subject: SUBJECT })).user.id, SUBJECT);
});

test('transport failure, redirects, oversized and non-JSON responses fail closed with sanitized errors', async () => {
  const responses = [
    () => new Response('upstream page', { status: 200, headers: { 'content-type': 'text/html' } }),
    () => new Response(null, { status: 302, headers: { location: 'https://evil.example' } }),
    () => Response.json({}, { headers: { 'content-length': '300000' } }),
    () => new Response(' '.repeat(262145), { headers: { 'content-type': 'application/json' } }),
  ];
  for (const response of responses) {
    const f = fixture({ response: path => path.includes('/rpc/') ? response() : undefined });
    await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code('CORP_UNAVAILABLE'));
  }
  const f = fixture({ fail: true });
  await assert.rejects(f.auth.validateCorporateSession(f.token, { subject: SUBJECT }), code('CORP_UNAVAILABLE'));
});

test('an injected SDK cannot redirect OAuth to another host or degrade PKCE to plain', async () => {
  for (const address of ['https://evil.example/auth', `${CORPORATE_SUPABASE_URL}/auth/v1/authorize?provider=azure&redirect_to=${encodeURIComponent(settings.callbackUrl)}&code_challenge_method=plain&code_challenge=test`]) {
    const factory: CorporateDependencies['clientFactory'] = () => ({ auth: { signInWithOAuth: async () => ({ error: null,
      data: { provider: 'azure', url: address, flowId: 'fictional-flow-id' } }) } } as any);
    const auth = createCorporateAuth({ settings, clientFactory: factory, now: () => NOW });
    await assert.rejects(auth.beginCorporateFlow(), code('CORP_UNAVAILABLE'));
  }
});
