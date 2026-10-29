import test from 'node:test';
import assert from 'node:assert/strict';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import { resolveWebAccess, sameOriginPost, webCookieOptions, hasWebCapability } from '../src/server/web/auth-policy';

const profile = { id: 'rm-user', auth_user_id: 'auth-user', nome: 'Operador', perfil: 'padr_o', status: 'ativo', cargo: 'Técnico', matricula: '123' };
function fakeClient(options: { denied?: boolean; row?: unknown; databaseError?: boolean; factors?: unknown[]; aal?: string; subject?: string; claimsError?: boolean } = {}) {
  const events: string[] = [];
  const query = {
    select() { events.push('profile'); return this; },
    eq(key: string, value: string) { events.push(`${key}:${value}`); return this; },
    async maybeSingle() { return { data: options.row === undefined ? profile : options.row, error: options.databaseError ? new Error('unavailable') : null }; },
  };
  const client = {
    auth: {
      async getUser() { events.push('getUser'); return { data: { user: options.denied ? null : { id: 'auth-user', factors: options.factors ?? [] } }, error: options.denied ? new Error('forged or revoked token') : null }; },
      getSession() { assert.fail('unverified cookie sessions must never authorize web access'); },
      async getClaims() { events.push('getClaims'); return { data: { claims: { sub: options.subject ?? 'auth-user', aal: options.aal ?? 'aal1' } }, error: options.claimsError ? new Error('invalid signature') : null }; },
    },
    from(table: string) { assert.equal(table, 'rm_users'); return query; },
  } as unknown as SupabaseClient;
  return { client, events };
}

test('web authorization rejects forged/revoked sessions before reading an RM profile', async () => {
  const { client, events } = fakeClient({ denied: true });
  assert.equal((await resolveWebAccess(client)).state, 'anonymous');
  assert.deepEqual(events, ['getUser']);
});

test('only an active RM profile bound to the server-verified Auth user can enter', async () => {
  const { client, events } = fakeClient();
  const access = await resolveWebAccess(client);
  assert.equal(access.state, 'authenticated');
  assert.deepEqual(events, ['getUser', 'profile', 'auth_user_id:auth-user', 'status:ativo']);
  if (access.state === 'authenticated') assert.deepEqual(access.profile, { id: 'rm-user', nome: 'Operador', perfil: 'padr_o', cargo: 'Técnico', matricula: '123' });
  for (const row of [null, { ...profile, status: 'inativo' }, { ...profile, auth_user_id: 'another-user' }]) {
    assert.equal((await resolveWebAccess(fakeClient({ row }).client)).state, 'inactive');
  }
  assert.equal((await resolveWebAccess(fakeClient({ databaseError: true }).client)).state, 'inactive');
});

test('management portal allows internal profiles only, even when other accounts are active', async () => {
  for (const perfil of ['administrador', 'padr_o', 'auditor']) assert.equal((await resolveWebAccess(fakeClient({ row: { ...profile, perfil } }).client)).state, 'authenticated');
  for (const perfil of ['cliente', 'mobile', 'vendedor', 'unknown', null]) assert.equal((await resolveWebAccess(fakeClient({ row: { ...profile, perfil } }).client)).state, 'inactive');
});

test('verified TOTP requires signed AAL2 for the same user; pending enrollment does not lock out password login', async () => {
  const factor = { id: 'totp-factor', status: 'verified', factor_type: 'totp', friendly_name: 'Authenticator' };
  assert.equal((await resolveWebAccess(fakeClient({ factors: [factor] }).client)).state, 'mfa');
  assert.equal((await resolveWebAccess(fakeClient({ factors: [factor], aal: 'aal2' }).client)).state, 'authenticated');
  assert.equal((await resolveWebAccess(fakeClient({ factors: [factor], aal: 'aal2', subject: 'other' }).client)).state, 'mfa');
  assert.equal((await resolveWebAccess(fakeClient({ factors: [factor], aal: 'aal2', claimsError: true }).client)).state, 'mfa');
  assert.equal((await resolveWebAccess(fakeClient({ factors: [{ ...factor, status: 'unverified' }] }).client)).state, 'authenticated');
});

test('session cookies are HttpOnly/Lax and secure in production; logout rejects cross-site or absent origins', () => {
  assert.deepEqual(webCookieOptions(true), { path: '/', httpOnly: true, sameSite: 'lax', secure: true });
  assert.equal(webCookieOptions(false).secure, false);
  assert.equal(sameOriginPost('https://em.example', 'em.example'), true);
  assert.equal(sameOriginPost('http://localhost:3000', 'localhost:3000'), true);
  for (const origin of [null, 'null', 'https://evil.example', 'https://em.example.evil.example', 'https://user@em.example']) assert.equal(sameOriginPost(origin, 'em.example'), false);
  assert.equal(sameOriginPost('https://em.example', 'em.example,evil.example'), false);
});

test('BFF local identity and MFA verification use the explicit JWT rather than a cookie session', async () => {
  const jwt = 'verified-server-only-access-token';
  const { client } = fakeClient({ factors: [{ id: 'factor', factor_type: 'totp', status: 'verified' }] });
  client.auth.getUser = (async (token?: string) => { assert.equal(token, jwt); return { data: { user: { id: 'auth-user', factors: [{ id: 'factor', factor_type: 'totp', status: 'verified' }] } }, error: null }; }) as any;
  client.auth.getClaims = (async (token?: string) => { assert.equal(token, jwt); return { data: { claims: { sub: 'auth-user', aal: 'aal2' } }, error: null }; }) as any;
  assert.equal((await resolveWebAccess(client, jwt)).state, 'authenticated');
});

test('web capabilities preserve staged legacy access but an SSO portal grant cannot imply a write grant', () => {
  assert.equal(hasWebCapability({}, 'em.projects.manage'), true);
  const viewer = { sso: { capabilities: ['em.portal.read', 'em.projects.read'] as const as any } };
  assert.equal(hasWebCapability(viewer, 'em.projects.read'), true);
  for (const capability of ['em.projects.manage', 'em.planning.manage', 'em.forms.review'] as const) assert.equal(hasWebCapability(viewer, capability), false);
});

test('SSR password session stays in its own cookie jar and logout revokes only the local session', async () => {
  const jar = new Map<string, string>(); const writes: CookieOptions[] = []; const requests: string[] = [];
  const expires = Math.floor(Date.now() / 1000) + 3600;
  const jwt = `${Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url')}.${Buffer.from(JSON.stringify({ sub: 'auth-user', exp: expires, aal: 'aal1' })).toString('base64url')}.c2lnbmF0dXJl`;
  const user = { id: 'auth-user', aud: 'authenticated', role: 'authenticated', email: 'test@example.invalid', app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' };
  const client = createServerClient('https://example.supabase.co', 'public-test-key', {
    cookieOptions: { name: 'em-web-session', ...webCookieOptions(true) },
    global: { fetch: async input => {
      const url = new URL(String(input)); requests.push(url.pathname + url.search);
      if (url.pathname.endsWith('/logout')) { assert.equal(url.searchParams.get('scope'), 'local'); return new Response(null, { status: 204 }); }
      return Response.json({ access_token: jwt, refresh_token: 'test-refresh', expires_in: 3600, expires_at: expires, token_type: 'bearer', user });
    } },
    cookies: { getAll: () => [...jar].map(([name, value]) => ({ name, value })), setAll: cookies => { for (const cookie of cookies) { writes.push(cookie.options); if (cookie.options.maxAge === 0) jar.delete(cookie.name); else jar.set(cookie.name, cookie.value); } } },
  });
  assert.equal((await client.auth.signInWithPassword({ email: user.email, password: 'not-a-real-password' })).error, null);
  assert.ok(jar.size > 0);
  assert.ok(writes.every(options => options.httpOnly && options.secure && options.sameSite === 'lax'));
  assert.ok([...jar.keys()].every(name => name.startsWith('em-web-session')));
  const separate = createServerClient('https://example.supabase.co', 'public-test-key', { cookies: { getAll: () => [], setAll: () => {} }, global: { fetch: async () => { assert.fail('empty request must not inherit another request session'); } } });
  assert.equal((await separate.auth.getUser()).data.user, null);
  assert.equal((await client.auth.signOut({ scope: 'local' })).error, null);
  assert.equal(jar.size, 0);
  assert.ok(requests.includes('/auth/v1/logout?scope=local'));
});
