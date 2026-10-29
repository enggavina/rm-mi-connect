import { createClient, type SupabaseClient, type SupabaseClientOptions } from '@supabase/supabase-js';
import {
  corporateSettings, CORPORATE_STORAGE_KEY, CorporateAuthError, validateCorporateDecision,
  validateCorporateFlow, validateCorporateRegistry, verifiedCorporateIdentity,
  type CorporateCapability, type CorporateFlow, type CorporateSettings, type VerifiedCorporateSession,
} from './sso-policy';
export { corporateSettings, CorporateAuthError } from './sso-policy';
export type { CorporateCapability, CorporateDecision, CorporateFlow, CorporateSettings, VerifiedCorporateSession } from './sso-policy';

type AuthClient = Pick<SupabaseClient, 'auth'>;
export interface CorporateDependencies {
  settings: CorporateSettings;
  fetcher?: typeof fetch;
  clientFactory?: (url: string, key: string, options: SupabaseClientOptions<'public'>) => AuthClient;
  now?: () => number;
}
const MAX_RESPONSE_BYTES = 256 * 1024;
const REQUEST_TIMEOUT_MS = 10_000;
class FlowStorage {
  private values: Map<string, string>;
  constructor(entries: [string, string][] = []) { this.values = new Map(entries); }
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
  removeItem(key: string) { this.values.delete(key); }
  snapshot(): [string, string][] { return [...this.values.entries()]; }
  clear() { this.values.clear(); }
}
function unavailable(error: unknown): CorporateAuthError {
  return error instanceof CorporateAuthError ? error : new CorporateAuthError('CORP_UNAVAILABLE');
}
function authFailure(error: { status?: number } | null): CorporateAuthError {
  return new CorporateAuthError(error?.status && [400, 401, 403, 422].includes(error.status) ? 'CORP_UNAUTHORIZED' : 'CORP_UNAVAILABLE');
}

/** Dependency injection is per instance/request; no account/session is cached globally. */
export function createCorporateAuth({ settings, fetcher = fetch, clientFactory = createClient, now = Date.now }: CorporateDependencies) {
  // Revalidate injected settings too: there is no alternate issuer or arbitrary destination.
  const verifiedSettings = corporateSettings({ EM_SSO_ENABLED: 'true', EM_CORPORATE_SUPABASE_URL: settings.supabaseUrl,
    EM_CORPORATE_PUBLISHABLE_KEY: settings.publishableKey, EM_CORPORATE_APP_SLUG: settings.appSlug, EM_PUBLIC_ORIGIN: settings.publicOrigin });
  if (!verifiedSettings || settings.callbackUrl !== verifiedSettings.callbackUrl || settings.issuer !== verifiedSettings.issuer) throw new CorporateAuthError('CORP_UNCONFIGURED');
  const boundedFetch: typeof fetch = async (input, init) => {
    try {
      const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
      if (url.origin !== settings.supabaseUrl || url.username || url.password || url.hash) throw new Error();
      const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
      const response = await fetcher(url, { ...init, cache: 'no-store', redirect: 'error',
        signal: init?.signal ? AbortSignal.any([timeout, init.signal]) : timeout });
      if (response.status >= 300 && response.status < 400) throw new Error();
      if (Number(response.headers.get('content-length')) > MAX_RESPONSE_BYTES) throw new Error();
      if (response.status === 204) return new Response(null, { status: 204, headers: response.headers });
      if (!response.headers.get('content-type')?.toLowerCase().startsWith('application/json') || !response.body) throw new Error();
      const reader = response.body.getReader(); const chunks: Uint8Array[] = []; let length = 0;
      try {
        while (true) { const { value, done } = await reader.read(); if (done) break;
          length += value.byteLength; if (length > MAX_RESPONSE_BYTES) throw new Error(); chunks.push(value); }
      } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
      return new Response(Buffer.concat(chunks), { status: response.status, headers: response.headers });
    } catch (error) { throw unavailable(error); }
  };
  const client = (storage: FlowStorage) => clientFactory(settings.supabaseUrl, settings.publishableKey, {
    auth: { flowType: 'pkce', autoRefreshToken: false, persistSession: true, detectSessionInUrl: false,
      skipAutoInitialize: true, storage, storageKey: CORPORATE_STORAGE_KEY, experimental: { appendPkceFlowIdToRedirects: false } },
    global: { fetch: boundedFetch },
  });
  async function json(path: string, token: string, body?: unknown): Promise<unknown> {
    const response = await boundedFetch(`${settings.supabaseUrl}${path}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { apikey: settings.publishableKey, Authorization: `Bearer ${token}`, Accept: 'application/json',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) throw new CorporateAuthError(response.status === 401 ? 'CORP_UNAUTHORIZED' : response.status === 403 ? 'CORP_FORBIDDEN' : 'CORP_UNAVAILABLE');
    try { return await response.json(); } catch { throw new CorporateAuthError('CORP_UNAVAILABLE'); }
  }
  async function verify(auth: AuthClient, token: string, expected: { subject?: string; startedAt?: number }, requiredCapability?: CorporateCapability): Promise<VerifiedCorporateSession> {
    if (typeof token !== 'string' || token.length > 16384 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
    const { data, error } = await auth.auth.getUser(token);
    if (error || !data.user) throw authFailure(error);
    const identity = verifiedCorporateIdentity(token, data.user, now(), expected);
    const query = new URLSearchParams({ select: 'id,email,auth_user_id,is_active', auth_user_id: `eq.${identity.user.id}`, is_active: 'eq.true', limit: '2' });
    validateCorporateRegistry(await json(`/rest/v1/authorized_users?${query}`, token), identity.user);
    const decision = validateCorporateDecision(await json('/rest/v1/rpc/cp_my_permissions_v1', token, { p_app_slug: settings.appSlug }), identity.user.id, requiredCapability);
    if (identity.expiresAt <= now()) throw new CorporateAuthError('CORP_UNAUTHORIZED');
    const verified = { accessToken: token, user: identity.user, expiresAt: identity.expiresAt, decision };
    if (identity.mfaRequired) throw new CorporateAuthError('CORP_MFA_REQUIRED', verified, identity.factors);
    return verified;
  }
  return {
    async beginCorporateFlow(): Promise<{ url: string; flow: CorporateFlow }> {
      const storage = new FlowStorage(); const auth = client(storage); const startedAt = now();
      try {
        const { data, error } = await auth.auth.signInWithOAuth({ provider: 'azure', options: {
          scopes: 'email profile openid', redirectTo: settings.callbackUrl, skipBrowserRedirect: true,
        } });
        if (error || data.provider !== 'azure' || !data.url || !data.flowId) throw new CorporateAuthError('CORP_UNAVAILABLE');
        const url = new URL(data.url);
        if (url.origin !== settings.supabaseUrl || url.pathname !== '/auth/v1/authorize' || url.username || url.password || url.hash
          || url.searchParams.getAll('provider').length !== 1 || url.searchParams.get('provider') !== 'azure'
          || url.searchParams.getAll('redirect_to').length !== 1 || url.searchParams.get('redirect_to') !== settings.callbackUrl
          || url.searchParams.get('code_challenge_method') !== 's256' || !/^[A-Za-z0-9_-]{43}$/.test(url.searchParams.get('code_challenge') || '')) throw new CorporateAuthError('CORP_UNAVAILABLE');
        const flow = validateCorporateFlow({ entries: storage.snapshot(), flowId: data.flowId, startedAt }, now());
        return { url: url.toString(), flow };
      } catch (error) { throw unavailable(error); }
      finally { storage.clear(); }
    },
    async finishCorporateFlow(input: CorporateFlow, code: string, callbackFlowId?: string): Promise<VerifiedCorporateSession> {
      const flow = validateCorporateFlow(input, now(), callbackFlowId);
      if (typeof code !== 'string' || !/^[A-Za-z0-9_-]{8,2048}$/.test(code)) throw new CorporateAuthError('CORP_UNAUTHORIZED');
      const storage = new FlowStorage(flow.entries); const auth = client(storage);
      try {
        // Always address the precise stored slot; never borrow the legacy verifier.
        const { data, error } = await auth.auth.exchangeCodeForSession(code, { flowId: flow.flowId });
        if (error || !data.session?.access_token || !data.user?.id) throw authFailure(error);
        return await verify(auth, data.session.access_token, { subject: data.user.id, startedAt: flow.startedAt });
      } catch (error) { throw unavailable(error); }
      finally { storage.clear(); }
    },
    async validateCorporateSession(token: string, expected: { subject: string; startedAt?: number }, requiredCapability?: CorporateCapability): Promise<VerifiedCorporateSession> {
      if (!expected || typeof expected.subject !== 'string') throw new CorporateAuthError('CORP_UNAUTHORIZED');
      const storage = new FlowStorage(); const auth = client(storage);
      try { return await verify(auth, token, expected, requiredCapability); }
      catch (error) { throw unavailable(error); }
      finally { storage.clear(); }
    },
  };
}
function configured() { const settings = corporateSettings(); if (!settings) throw new CorporateAuthError('CORP_UNCONFIGURED'); return createCorporateAuth({ settings }); }
export async function beginCorporateFlow() { return configured().beginCorporateFlow(); }
export async function finishCorporateFlow(flow: CorporateFlow, code: string, callbackFlowId?: string) { return configured().finishCorporateFlow(flow, code, callbackFlowId); }
export async function validateCorporateSession(token: string, expected: { subject: string; startedAt?: number }, requiredCapability?: CorporateCapability) { return configured().validateCorporateSession(token, expected, requiredCapability); }
