import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { createSsoHandlers, fixedOriginPost } from '../src/app/auth/sso/handlers';
import { CorporateAuthError } from '../src/server/web/sso-policy';
import { signIn } from '../src/app/login/actions';

const origin = 'https://em.example.invalid';
const callback = `${origin}/auth/sso/callback`;
const code = 'valid-oauth-code';
function setup(overrides: Partial<Parameters<typeof createSsoHandlers>[0]> = {}) {
  const events: unknown[] = [];
  const handlers = createSsoHandlers({
    settings: () => ({ publicOrigin: origin }),
    begin: async () => { events.push('begin'); return 'https://identity.example.invalid/authorize?provider=azure'; },
    finish: async (value, flow) => { events.push([value, flow]); return '/painel'; },
    ...overrides,
  });
  return { ...handlers, events };
}
function safe(response: Response) {
  assert.match(response.headers.get('cache-control') || '', /no-store/);
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
}

test('SSO start requires POST from the fixed public origin, regardless of forwarded host', async () => {
  const { start, events } = setup();
  const rejectedHeaders: Record<string, string>[] = [{}, { Origin: 'null' }, { Origin: 'https://attacker.invalid', 'X-Forwarded-Host': 'attacker.invalid' },
    { Origin: 'http://em.example.invalid' }, { Origin: `${origin}/` }, { Origin: origin, 'Sec-Fetch-Site': 'cross-site' }];
  for (const headers of rejectedHeaders) {
    const response = await start(new Request(`${origin}/auth/sso/start`, { method: 'POST', headers }));
    assert.equal(response.status, 403); safe(response);
  }
  assert.equal(fixedOriginPost(new Request(`${origin}/auth/sso/start`, { headers: { Origin: origin } }), origin), false);
  assert.deepEqual(events, []);
  const response = await start(new Request(`${origin}/auth/sso/start`, { method: 'POST', headers: { Origin: origin, 'X-Forwarded-Host': 'attacker.invalid' } }));
  assert.equal(response.status, 303); safe(response);
  assert.equal(response.headers.get('location'), 'https://identity.example.invalid/authorize?provider=azure');
  assert.deepEqual(events, ['begin']);
});

test('disabled or misconfigured SSO never starts an alternate authentication flow', async () => {
  const request = new Request(`${origin}/auth/sso/start`, { method: 'POST', headers: { Origin: origin } });
  const disabled = setup({ settings: () => null });
  assert.equal((await disabled.start(request)).status, 404);
  assert.equal((await disabled.callback(new Request(`${callback}?code=${code}`))).status, 404);
  assert.deepEqual(disabled.events, []);
  const invalid = setup({ settings: () => { throw new Error('secret configuration value'); } });
  const response = await invalid.start(request);
  assert.equal(response.headers.get('location'), '/login?erro=sso_indisponivel'); safe(response);
  assert.equal(await response.text(), ''); assert.deepEqual(invalid.events, []);
});

test('callback accepts only one code and an optional SDK flow identifier, then uses a fixed local destination', async () => {
  for (const flow of ['', '&sb_flow_id=flow-id-123456']) {
    const handlers = setup();
    const response = await handlers.callback(new Request(`https://internal-proxy.invalid/auth/sso/callback?code=${code}${flow}`, { headers: { Host: 'attacker.invalid' } }));
    assert.equal(response.status, 303); assert.equal(response.headers.get('location'), `${origin}/painel`); safe(response);
    assert.deepEqual(handlers.events, [[code, flow ? 'flow-id-123456' : undefined]]);
  }
  const mfa = setup({ finish: async () => '/login/sso-mfa' });
  assert.equal((await mfa.callback(new Request(`${callback}?code=${code}`))).headers.get('location'), `${origin}/login/sso-mfa`);
});

test('callback rejects query confusion, token parameters, arbitrary returns and malformed input before exchanging', async () => {
  const handlers = setup();
  for (const query of ['', `code=${code}&code=other-code-123`, `code=${code}&sb_flow_id=short`,
    `code=${code}&sb_flow_id=flow-id-123&sb_flow_id=flow-id-456`, `code=${code}&flow_id=alternate-123`,
    `code=${code}&access_token=private-token`, `code=${code}&refresh_token=private-token`,
    `code=${code}&returnTo=https://attacker.invalid`, `code=${code}&next=//attacker.invalid`,
    'error=access_denied&error_description=private-detail', `code=${code}&error_code=private-detail`,
    'code=short', 'code=invalid.code', 'code=invalid~code', 'code=invalid%0Avalue', `code=${'a'.repeat(4096)}`]) {
    const response = await handlers.callback(new Request(`${callback}?${query}`));
    assert.equal(response.status, 303); assert.equal(response.headers.get('location'), `${origin}/login?erro=sso`); safe(response);
    assert.equal(await response.text(), '');
  }
  assert.deepEqual(handlers.events, []);
});

test('callback reports only fixed errors and permits no bridge-supplied open redirect', async () => {
  for (const [error, path] of [
    [new CorporateAuthError('CORP_FORBIDDEN'), '/acesso?motivo=permissao'],
    [new CorporateAuthError('CORP_UNAUTHORIZED'), '/login?erro=sso'],
    [new Error('private token or upstream response'), '/login?erro=sso_indisponivel'],
  ] as const) {
    const response = await setup({ finish: async () => { throw error; } }).callback(new Request(`${callback}?code=${code}`));
    assert.equal(response.headers.get('location'), origin + path); safe(response); assert.equal(await response.text(), '');
  }
  const response = await setup({ finish: async () => 'https://attacker.invalid' as '/painel' }).callback(new Request(`${callback}?code=${code}`));
  assert.equal(response.headers.get('location'), `${origin}/login?erro=sso`);
});

test('manual password server action is disabled when corporate SSO is enabled', async () => {
  const previous = process.env.EM_SSO_ENABLED;
  try {
    process.env.EM_SSO_ENABLED = 'true';
    const form = new FormData(); form.set('email', 'test@example.invalid'); form.set('password', 'test-password');
    const state = await signIn({ error: '' }, form);
    assert.equal(state.error, 'Use o acesso corporativo para entrar no EM.');
  } finally { if (previous === undefined) delete process.env.EM_SSO_ENABLED; else process.env.EM_SSO_ENABLED = previous; }
});

test('the installed Supabase SDK sends explicit server bearer headers for MFA without a stored session', async () => {
  const bearer = 'server-only-test-bearer', factorId = 'f409c405-a0a8-4d90-9ac0-493e101b3e9f';
  const requests: string[] = [];
  const client = createClient('https://example.supabase.co', 'public-test-key', {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { Authorization: `Bearer ${bearer}` }, fetch: async (input, init) => {
      const path = new URL(String(input)).pathname; requests.push(path);
      assert.equal(new Headers(init?.headers).get('authorization'), `Bearer ${bearer}`);
      if (path.endsWith('/challenge')) return Response.json({ id: 'challenge-id', type: 'totp', expires_at: Math.floor(Date.now() / 1000) + 60 });
      assert.equal(path, `/auth/v1/factors/${factorId}/verify`);
      assert.deepEqual(JSON.parse(String(init?.body)), { code: '123456', challenge_id: 'challenge-id' });
      return Response.json({ access_token: 'verified-server-token', refresh_token: 'never-return-to-browser', token_type: 'bearer', expires_in: 3600,
        user: { id: '18c3bce0-04bd-43c4-85ee-473ae07ca51d', aud: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' } });
    } },
  });
  const result = await client.auth.mfa.challengeAndVerify({ factorId, code: '123456' });
  assert.equal(result.error, null); assert.equal(result.data?.access_token, 'verified-server-token');
  assert.deepEqual(requests, [`/auth/v1/factors/${factorId}/challenge`, `/auth/v1/factors/${factorId}/verify`]);
});
