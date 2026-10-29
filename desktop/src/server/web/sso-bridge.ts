import { createClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { z } from 'zod';
import { required } from '../config';
import { resolveWebAccess, webCookieOptions, type WebAccess, type SsoContext } from './auth-policy';
import { corporateSettings, beginCorporateFlow, finishCorporateFlow, validateCorporateSession, CorporateAuthError,
  type CorporateFlow, type VerifiedCorporateSession, type CorporateCapability } from './sso-corporate';
import { opaqueToken, openSso, sealSso, tokenHash } from './sso-crypto';
import { ssoBindingSchema, ssoFlowSchema, ssoSessionSchema } from './sso-envelopes';

export const SSO_SESSION_COOKIE = 'em-sso-session';
export const SSO_FLOW_COOKIE = 'em-sso-flow';
const TEN_MINUTES = 10 * 60_000;
const NONCE = /^[A-Za-z0-9_-]{43}$/;
const uuid = z.string().uuid();
type Binding = z.infer<typeof ssoBindingSchema>;
type SessionContents = { corporate: VerifiedCorporateSession; localToken: string; binding: Binding; localSessionId: string; expiresAt: number };
type Pending = { kind: 'corporate-mfa'; corporate: VerifiedCorporateSession; factors: { id: string; name: string }[]; expiresAt: number; attempts: number }
  | { kind: 'local-mfa'; contents: SessionContents; factors: { id: string; name: string }[]; expiresAt: number; attempts: number };
type FlowContents = { kind: 'oauth'; flow: CorporateFlow; expiresAt: number } | Pending;
export type { SsoContext } from './auth-policy';
const boundedFetch: typeof fetch = (input, init) => fetch(input, { ...init, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10_000) });

function bridge() {
  const url = required('SUPABASE_URL');
  if (new URL(url).hostname !== 'ellpxfbsrbhblyizvbbk.supabase.co') throw new CorporateAuthError('CORP_UNCONFIGURED');
  return createClient(url, required('EM_SSO_BRIDGE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: boundedFetch } });
}
async function rpc(name: string, args: Record<string, unknown>): Promise<any> {
  const { data, error } = await bridge().rpc(name, args);
  if (error) throw new CorporateAuthError('CORP_UNAVAILABLE');
  return data;
}
export function localSsoClient(token?: string) {
  if (token !== undefined && (typeof token !== 'string' || token.length < 50 || token.length > 32_768)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  return createClient(required('SUPABASE_URL'), required('SUPABASE_ANON_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { ...(token ? { headers: { Authorization: `Bearer ${token}` } } : {}), fetch: boundedFetch },
  });
}
function localClaims(token: string, expectedUserId: string) {
  // Call only after the same JWT has been verified by getUser(token).
  try {
    const parts = token.split('.'); if (parts.length !== 3 || parts[1].length > 16_384) throw new Error();
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (claims.iss !== `${required('SUPABASE_URL')}/auth/v1` || claims.sub !== expectedUserId || claims.aud !== 'authenticated'
      || claims.role !== 'authenticated' || !uuid.safeParse(claims.session_id).success || !Number.isFinite(claims.exp) || claims.exp * 1000 <= Date.now()) throw new Error();
    return { sessionId: claims.session_id as string, expiresAt: claims.exp * 1000 as number };
  } catch { throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
}
async function setCookie(name: string, value: string, expiresAt: number) {
  (await cookies()).set(name, value, { ...webCookieOptions(), maxAge: Math.max(0, Math.floor((expiresAt - Date.now()) / 1000)) });
}
async function clearCookie(name: string) {
  try { (await cookies()).set(name, '', { ...webCookieOptions(), maxAge: 0 }); } catch { /* A guarded page can redirect; routes clear cookies. */ }
}
async function putFlow(value: FlowContents) {
  const nonce = opaqueToken();
  await rpc('rm_sso_flow_put_v1', { p_hash: tokenHash(nonce), p_ciphertext: sealSso(value, 'flow'), p_expires_at: new Date(value.expiresAt).toISOString() });
  await setCookie(SSO_FLOW_COOKIE, nonce, value.expiresAt);
}
async function takeFlow(): Promise<FlowContents> {
  const nonce = (await cookies()).get(SSO_FLOW_COOKIE)?.value;
  await clearCookie(SSO_FLOW_COOKIE);
  if (!nonce || !NONCE.test(nonce)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  const ciphertext = await rpc('rm_sso_flow_take_v1', { p_hash: tokenHash(nonce) });
  if (typeof ciphertext !== 'string') throw new CorporateAuthError('CORP_UNAUTHORIZED');
  let value: FlowContents;
  try { value = ssoFlowSchema.parse(openSso(ciphertext, 'flow')); } catch { throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
  if (!value || !['oauth', 'corporate-mfa', 'local-mfa'].includes(value.kind) || !Number.isFinite(value.expiresAt) || value.expiresAt <= Date.now()) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  return value;
}
async function getBinding(corporate: VerifiedCorporateSession) {
  const data = await rpc('rm_sso_binding_v1', { p_issuer: corporate.decision.issuer, p_subject: corporate.user.id });
  const result = ssoBindingSchema.safeParse(data);
  if (!result.success || result.data.profile.id !== result.data.rm_user_id) throw new CorporateAuthError('CORP_FORBIDDEN');
  return result.data;
}
async function saveSession(contents: SessionContents) {
  const nonce = opaqueToken();
  await rpc('rm_sso_session_put_v1', { p_hash: tokenHash(nonce), p_binding_id: contents.binding.binding_id,
    p_local_session_id: contents.localSessionId, p_ciphertext: sealSso(contents, 'session'), p_expires_at: new Date(contents.expiresAt).toISOString() });
  await setCookie(SSO_SESSION_COOKIE, nonce, contents.expiresAt);
  await clearCookie(SSO_FLOW_COOKIE);
}

export async function beginSso(): Promise<string> {
  if (!corporateSettings()) throw new CorporateAuthError('CORP_UNCONFIGURED');
  await endSso();
  const { url, flow } = await beginCorporateFlow();
  await putFlow({ kind: 'oauth', flow, expiresAt: flow.startedAt + TEN_MINUTES });
  return url;
}

async function exchangeLocal(corporate: VerifiedCorporateSession): Promise<'/painel' | '/login/sso-mfa'> {
  const binding = await getBinding(corporate); const admin = bridge();
  const found = await admin.auth.admin.getUserById(binding.auth_user_id);
  if (found.error || !found.data.user || found.data.user.id !== binding.auth_user_id || !found.data.user.email) throw new CorporateAuthError('CORP_FORBIDDEN');
  // The email comes only from the UUID that was explicitly approved locally.
  const generated = await admin.auth.admin.generateLink({ type: 'magiclink', email: found.data.user.email });
  if (generated.error || generated.data.user?.id !== binding.auth_user_id || !generated.data.properties?.hashed_token) throw new CorporateAuthError('CORP_FORBIDDEN');
  const client = createClient(required('SUPABASE_URL'), required('SUPABASE_ANON_KEY'), { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: boundedFetch } });
  const verified = await client.auth.verifyOtp({ type: 'magiclink', token_hash: generated.data.properties.hashed_token });
  const token = verified.data.session?.access_token;
  if (verified.error || !token || verified.data.user?.id !== binding.auth_user_id) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  const local = localSsoClient(token); const access = await resolveWebAccess(local, token);
  if (!['mfa', 'authenticated'].includes(access.state) || !('profile' in access) || access.profile.id !== binding.rm_user_id) throw new CorporateAuthError('CORP_FORBIDDEN');
  const claims = localClaims(token, binding.auth_user_id);
  const contents: SessionContents = { corporate, localToken: token, binding, localSessionId: claims.sessionId,
    expiresAt: Math.min(corporate.expiresAt, claims.expiresAt, Date.now() + 60 * 60_000) };
  if (access.state === 'mfa') {
    await putFlow({ kind: 'local-mfa', contents, factors: access.factors, expiresAt: Math.min(contents.expiresAt, Date.now() + TEN_MINUTES), attempts: 0 });
    return '/login/sso-mfa';
  }
  await saveSession(contents); return '/painel';
}
export async function finishSso(code: string, callbackFlowId?: string): Promise<'/painel' | '/login/sso-mfa'> {
  const saved = await takeFlow();
  if (saved.kind !== 'oauth' || !/^[A-Za-z0-9_-]{8,2048}$/.test(code)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  let corporate: VerifiedCorporateSession;
  try { corporate = await finishCorporateFlow(saved.flow, code, callbackFlowId); }
  catch (error) {
    if (error instanceof CorporateAuthError && error.code === 'CORP_MFA_REQUIRED' && error.pending && error.factors?.length) {
      await putFlow({ kind: 'corporate-mfa', corporate: error.pending, factors: error.factors,
        expiresAt: Math.min(saved.expiresAt, error.pending.expiresAt), attempts: 0 });
      return '/login/sso-mfa';
    }
    throw error;
  }
  return exchangeLocal(corporate);
}

export async function pendingSsoMfa() {
  // A Server Component can read the encrypted flow but cannot rotate cookies.
  // Verification consumes this same record atomically before doing any work.
  const nonce = (await cookies()).get(SSO_FLOW_COOKIE)?.value;
  if (!nonce || !NONCE.test(nonce)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  const ciphertext = await rpc('rm_sso_flow_get_v1', { p_hash: tokenHash(nonce) });
  if (typeof ciphertext !== 'string') throw new CorporateAuthError('CORP_UNAUTHORIZED');
  let pending: FlowContents;
  try { pending = ssoFlowSchema.parse(openSso(ciphertext, 'flow')); } catch { throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
  if (!pending || !['corporate-mfa', 'local-mfa'].includes(pending.kind) || pending.kind === 'oauth'
    || pending.expiresAt <= Date.now() || pending.attempts >= 5) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  return { provider: pending.kind === 'corporate-mfa' ? 'corporate' as const : 'local' as const, factors: pending.factors };
}
export async function verifySsoMfa(factor: string, code: string): Promise<'/painel' | '/login/sso-mfa'> {
  const pending = await takeFlow();
  if (pending.kind === 'oauth' || pending.attempts >= 5) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  if (!/^\d{6}$/.test(code) || !pending.factors.some(item => item.id === factor)) {
    await putFlow({ ...pending, attempts: pending.attempts + 1 }); throw new CorporateAuthError('CORP_UNAUTHORIZED');
  }
  if (pending.kind === 'corporate-mfa') {
    const config = corporateSettings(); if (!config) throw new CorporateAuthError('CORP_UNCONFIGURED');
    const client = createClient(config.supabaseUrl, config.publishableKey, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: `Bearer ${pending.corporate.accessToken}` }, fetch: boundedFetch } });
    const result = await client.auth.mfa.challengeAndVerify({ factorId: factor, code });
    if (result.error || !result.data?.access_token) { await putFlow({ ...pending, attempts: pending.attempts + 1 }); throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
    const corporate = await validateCorporateSession(result.data.access_token, { subject: pending.corporate.user.id });
    return exchangeLocal(corporate);
  }
  await validateCorporateSession(pending.contents.corporate.accessToken, { subject: pending.contents.corporate.user.id });
  const client = localSsoClient(pending.contents.localToken);
  const result = await client.auth.mfa.challengeAndVerify({ factorId: factor, code });
  if (result.error || !result.data?.access_token) { await putFlow({ ...pending, attempts: pending.attempts + 1 }); throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
  const token = result.data.access_token, local = localSsoClient(token), access = await resolveWebAccess(local, token);
  if (access.state !== 'authenticated' || access.profile.id !== pending.contents.binding.rm_user_id) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  const claims = localClaims(token, pending.contents.binding.auth_user_id);
  await saveSession({ ...pending.contents, localToken: token, localSessionId: claims.sessionId,
    expiresAt: Math.min(pending.contents.expiresAt, claims.expiresAt) });
  return '/painel';
}

export async function getSsoWebAccess(): Promise<WebAccess> {
  const nonce = (await cookies()).get(SSO_SESSION_COOKIE)?.value;
  if (!nonce) return { state: 'anonymous', client: localSsoClient() };
  if (!NONCE.test(nonce)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  const hash = tokenHash(nonce);
  const record = await rpc('rm_sso_session_get_v1', { p_hash: hash });
  if (!record || typeof record.ciphertext !== 'string') return { state: 'anonymous', client: localSsoClient() };
  let contents: SessionContents;
  try { contents = ssoSessionSchema.parse(openSso(record.ciphertext, 'session')); } catch { throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
  if (!contents || !Number.isFinite(contents.expiresAt) || contents.expiresAt <= Date.now()
    || record.binding_id !== contents.binding.binding_id || record.local_session_id !== contents.localSessionId) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  let corporate: VerifiedCorporateSession;
  try { corporate = await validateCorporateSession(contents.corporate.accessToken, { subject: contents.corporate.user.id }); }
  catch (error) {
    if (error instanceof CorporateAuthError && ['CORP_FORBIDDEN', 'CORP_UNAUTHORIZED'].includes(error.code)) await rpc('rm_sso_session_delete_v1', { p_hash: hash });
    throw error;
  }
  const binding = await getBinding(corporate);
  if (binding.binding_id !== contents.binding.binding_id || binding.auth_user_id !== contents.binding.auth_user_id || binding.rm_user_id !== contents.binding.rm_user_id) throw new CorporateAuthError('CORP_FORBIDDEN');
  const client = localSsoClient(contents.localToken), access = await resolveWebAccess(client, contents.localToken);
  if (access.state !== 'authenticated' || access.profile.id !== binding.rm_user_id || localClaims(contents.localToken, binding.auth_user_id).sessionId !== contents.localSessionId) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  return { ...access, sso: { sessionHash: hash, bindingId: binding.binding_id, subject: corporate.user.id, capabilities: corporate.decision.capabilities } };
}
export async function authorizeSsoAction(context: SsoContext, submissionId: string, operation: string, payload: Record<string, unknown>, capability: CorporateCapability) {
  // The capability was checked freshly by getSsoWebAccess in this same request.
  if (!context.capabilities.includes(capability)) throw new CorporateAuthError('CORP_FORBIDDEN');
  await rpc('rm_sso_action_permit_v1', { p_session_hash: context.sessionHash, p_submission_id: submissionId,
    p_operation: operation, p_payload: payload, p_capability: capability });
}
export async function endSso() {
  const config = corporateSettings();
  async function revoke(corporateToken: string, localToken?: string) {
    if (!config) return;
    await Promise.allSettled([
      ...(localToken ? [localSsoClient(localToken).auth.admin.signOut(localToken, 'local')] : []),
      createClient(config.supabaseUrl, config.publishableKey, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: boundedFetch } }).auth.admin.signOut(corporateToken, 'local'),
    ]);
  }
  const flowNonce = (await cookies()).get(SSO_FLOW_COOKIE)?.value;
  if (flowNonce && NONCE.test(flowNonce)) {
    try {
      const encrypted = await rpc('rm_sso_flow_take_v1', { p_hash: tokenHash(flowNonce) });
      if (typeof encrypted === 'string') {
        const pending = ssoFlowSchema.parse(openSso(encrypted, 'flow'));
        if (pending.kind === 'corporate-mfa') await revoke(pending.corporate.accessToken);
        if (pending.kind === 'local-mfa') await revoke(pending.contents.corporate.accessToken, pending.contents.localToken);
      }
    } catch { /* Cancellation discards the browser nonce even if a remote service is unavailable. */ }
  }
  const nonce = (await cookies()).get(SSO_SESSION_COOKIE)?.value;
  if (nonce && NONCE.test(nonce)) {
    try {
      const hash = tokenHash(nonce), record = await rpc('rm_sso_session_get_v1', { p_hash: hash });
      await rpc('rm_sso_session_delete_v1', { p_hash: hash });
      if (typeof record?.ciphertext === 'string') {
        const contents = ssoSessionSchema.parse(openSso(record.ciphertext, 'session'));
        await revoke(contents.corporate.accessToken, contents.localToken);
      }
    } catch { /* Session lookup is fail-closed; remove this browser's cookie even on service failure. */ }
  }
  await clearCookie(SSO_SESSION_COOKIE); await clearCookie(SSO_FLOW_COOKIE);
}
