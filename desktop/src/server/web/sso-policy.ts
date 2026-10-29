/** Server-side corporate SSO policy. No claim is trusted before remote getUser(token). */
export const CORPORATE_SUPABASE_URL = 'https://kxoriwvzmxhatzqcgnht.supabase.co';
export const CORPORATE_ISSUER = `${CORPORATE_SUPABASE_URL}/auth/v1`;
export const CORPORATE_APP_SLUG = 'em' as const;
export const CORPORATE_FLOW_TTL_MS = 10 * 60_000;
export const CORPORATE_SESSION_TTL_MS = 60 * 60_000;
export const CORPORATE_STORAGE_KEY = 'em-corporate-pkce';
export const CORPORATE_CAPABILITIES = [
  'em.portal.read', 'em.projects.read', 'em.projects.manage', 'em.planning.read',
  'em.planning.manage', 'em.forms.read', 'em.forms.review', 'em.photos.read',
  'em.documents.read', 'em.catalogs.read', 'em.history.read', 'em.catalogs.manage',
  'em.engineering.read', 'em.engineering.manage',
  'em.form_templates.read', 'em.form_templates.manage',
] as const;
export type CorporateCapability = typeof CORPORATE_CAPABILITIES[number];
export interface CorporateSettings {
  supabaseUrl: string; publishableKey: string; appSlug: 'em'; publicOrigin: string; callbackUrl: string; issuer: string;
}
export interface CorporateFlow { entries: [string, string][]; flowId: string; startedAt: number }
export interface CorporateDecision {
  application: 'em'; issuer: string; subject: string; app_access: true;
  capabilities: CorporateCapability[]; all_employees: false; fields: []; export_allowed: false;
}
export interface CorporateUser { id: string; email: string; nome?: string }
export interface VerifiedCorporateSession {
  accessToken: string; user: CorporateUser; expiresAt: number; decision: CorporateDecision;
}
export type CorporateErrorCode = 'CORP_UNCONFIGURED' | 'CORP_UNAUTHORIZED' | 'CORP_FORBIDDEN' | 'CORP_UNAVAILABLE' | 'CORP_MFA_REQUIRED';
export class CorporateAuthError extends Error {
  readonly status: number;
  /** Server-only MFA handoff. Never serialize this exception to the browser/log. */
  declare readonly pending?: VerifiedCorporateSession;
  declare readonly factors?: { id: string; name: string }[];
  constructor(readonly code: CorporateErrorCode, pending?: VerifiedCorporateSession, factors?: { id: string; name: string }[]) {
    super(code === 'CORP_MFA_REQUIRED' ? 'Confirme o código do seu autenticador corporativo.'
      : code === 'CORP_UNAUTHORIZED' ? 'Entre novamente com sua conta Microsoft corporativa.'
        : code === 'CORP_FORBIDDEN' ? 'Sua conta não tem a permissão necessária para acessar esta área.'
          : 'Não foi possível confirmar o acesso corporativo. Tente novamente.');
    this.name = 'CorporateAuthError';
    this.status = code === 'CORP_UNAUTHORIZED' || code === 'CORP_MFA_REQUIRED' ? 401 : code === 'CORP_FORBIDDEN' ? 403 : 503;
    // Non-enumerable: accidental JSON serialization cannot expose the pending JWT.
    if (pending) Object.defineProperty(this, 'pending', { value: pending });
    if (factors) Object.defineProperty(this, 'factors', { value: factors });
  }
}
const object = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);
const uuid = (value: unknown): value is string => typeof value === 'string'
  && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);
const FLOW_ID = /^[A-Za-z0-9_-]{8,64}$/;
const SKEW_MS = 10_000;
const finite = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);

export function corporateSettings(env: Readonly<Record<string, string | undefined>> = process.env): CorporateSettings | null {
  if (env.EM_SSO_ENABLED !== 'true') return null;
  try {
    if (env.EM_CORPORATE_SUPABASE_URL !== CORPORATE_SUPABASE_URL || env.EM_CORPORATE_APP_SLUG !== CORPORATE_APP_SLUG) throw new Error();
    const key = env.EM_CORPORATE_PUBLISHABLE_KEY?.trim();
    if (!key || !/^sb_publishable_[A-Za-z0-9_-]{8,}$/.test(key)) throw new Error();
    const origin = new URL(env.EM_PUBLIC_ORIGIN || '');
    if (origin.protocol !== 'https:' || origin.username || origin.password || origin.search || origin.hash
      || origin.pathname !== '/' || origin.origin !== env.EM_PUBLIC_ORIGIN) throw new Error();
    return { supabaseUrl: CORPORATE_SUPABASE_URL, publishableKey: key, appSlug: CORPORATE_APP_SLUG,
      publicOrigin: origin.origin, callbackUrl: `${origin.origin}/auth/sso/callback`, issuer: CORPORATE_ISSUER };
  } catch { throw new CorporateAuthError('CORP_UNCONFIGURED'); }
}

export function validateCorporateFlow(value: unknown, now: number, callbackFlowId?: string): CorporateFlow {
  if (!object(value) || typeof value.flowId !== 'string' || !FLOW_ID.test(value.flowId)
    || !finite(value.startedAt) || value.startedAt > now + SKEW_MS || now - value.startedAt >= CORPORATE_FLOW_TTL_MS
    || (callbackFlowId !== undefined && callbackFlowId !== value.flowId)
    || !Array.isArray(value.entries) || value.entries.length < 1 || value.entries.length > 8) throw new CorporateAuthError('CORP_UNAUTHORIZED');
  const expectedSlot = `${CORPORATE_STORAGE_KEY}-flow-${value.flowId}-code-verifier`;
  const allowed = new Set([expectedSlot, `${CORPORATE_STORAGE_KEY}-flows-code-verifier`, `${CORPORATE_STORAGE_KEY}-code-verifier`]);
  const names = new Set<string>();
  for (const entry of value.entries) {
    if (!Array.isArray(entry) || entry.length !== 2 || typeof entry[0] !== 'string' || typeof entry[1] !== 'string'
      || !allowed.has(entry[0]) || names.has(entry[0]) || entry[1].length > 1024) throw new CorporateAuthError('CORP_UNAUTHORIZED');
    names.add(entry[0]);
  }
  const slot = value.entries.find(entry => entry[0] === expectedSlot);
  try {
    const verifier = slot && JSON.parse(slot[1]);
    if (typeof verifier !== 'string' || !/^[A-Za-z0-9._~-]{43,128}$/.test(verifier)
      || JSON.stringify(value.entries).length > 4096) throw new Error();
  } catch { throw new CorporateAuthError('CORP_UNAUTHORIZED'); }
  return { flowId: value.flowId, startedAt: value.startedAt, entries: value.entries.map(entry => [entry[0], entry[1]]) };
}

/** Called only with a user freshly returned by auth.getUser(the same token). */
export function verifiedCorporateIdentity(token: string, rawUser: unknown, now: number, expected: { subject?: string; startedAt?: number } = {}) {
  const denied = () => new CorporateAuthError('CORP_UNAUTHORIZED');
  if (!object(rawUser) || !uuid(rawUser.id) || rawUser.is_anonymous === true
    || typeof rawUser.email !== 'string' || !/^[^\s@]+@mielectric\.com\.br$/i.test(rawUser.email)
    || typeof rawUser.email_confirmed_at !== 'string' || !Number.isFinite(Date.parse(rawUser.email_confirmed_at))
    || (expected.subject !== undefined && expected.subject !== rawUser.id)) throw denied();
  const startedAt = expected.startedAt;
  if (startedAt !== undefined && (!finite(startedAt) || startedAt > now + SKEW_MS || now - startedAt >= CORPORATE_SESSION_TTL_MS)) throw denied();
  const identities = Array.isArray(rawUser.identities) ? rawUser.identities : [];
  const azureTimes = identities.flatMap(identity => {
    if (!object(identity) || identity.provider !== 'azure' || identity.user_id !== rawUser.id) return [];
    // Both fields belong to this verified provider identity. A fresh global user
    // timestamp or another provider's login must never renew an old Azure proof.
    const times = [identity.last_sign_in_at, identity.updated_at]
      .filter((value): value is string => typeof value === 'string').map(Date.parse).filter(Number.isFinite);
    const signedInAt = Math.max(...times);
    return Number.isFinite(signedInAt) && signedInAt <= now + SKEW_MS
      && (startedAt === undefined || signedInAt >= startedAt - SKEW_MS) ? [signedInAt] : [];
  });
  if (!azureTimes.length) throw denied();
  let claims: Record<string, unknown>;
  try {
    if (token.length > 16384 || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) throw new Error();
    const decoded: unknown = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    if (!object(decoded)) throw new Error();
    claims = decoded;
  } catch { throw denied(); }
  if (claims.iss !== CORPORATE_ISSUER || claims.aud !== 'authenticated' || claims.role !== 'authenticated'
    || claims.sub !== rawUser.id || !uuid(claims.session_id) || !finite(claims.iat) || !finite(claims.exp)
    || claims.iat * 1000 > now + SKEW_MS || claims.exp * 1000 <= now || claims.exp <= claims.iat
    || (startedAt !== undefined && claims.iat * 1000 < startedAt - SKEW_MS)
    || (claims.aal !== 'aal1' && claims.aal !== 'aal2') || !Array.isArray(claims.amr) || claims.amr.length < 1 || claims.amr.length > 8
    || !claims.amr.every(item => object(item) && typeof item.method === 'string'
      && ['oauth', 'totp', 'mfa/totp', 'token_refresh'].includes(item.method) && finite(item.timestamp)
      && item.timestamp * 1000 <= now + SKEW_MS)) throw denied();
  const oauth = claims.amr.filter(item => object(item) && item.method === 'oauth');
  if (oauth.length !== 1 || !object(oauth[0]) || !finite(oauth[0].timestamp)
    || now - oauth[0].timestamp * 1000 >= CORPORATE_SESSION_TTL_MS
    || Math.max(...azureTimes) < oauth[0].timestamp * 1000 - SKEW_MS
    || (startedAt !== undefined && oauth[0].timestamp * 1000 < startedAt - SKEW_MS)) throw denied();
  const expiresAt = Math.min(claims.exp * 1000, (startedAt ?? oauth[0].timestamp * 1000) + CORPORATE_SESSION_TTL_MS);
  const factors = (Array.isArray(rawUser.factors) ? rawUser.factors : []).filter(factor => object(factor)
    && factor.factor_type === 'totp' && factor.status === 'verified');
  if (factors.some(factor => !object(factor) || !uuid(factor.id))) throw denied();
  const metadata = object(rawUser.user_metadata) ? rawUser.user_metadata : {};
  const nome = typeof metadata.full_name === 'string' && metadata.full_name.length <= 200 ? metadata.full_name : undefined;
  const user: CorporateUser = { id: rawUser.id, email: rawUser.email.toLowerCase(), ...(nome ? { nome } : {}) };
  return { user, expiresAt, mfaRequired: factors.length > 0 && claims.aal !== 'aal2',
    factors: factors.map(factor => ({ id: (factor as Record<string, unknown>).id as string,
      name: typeof (factor as Record<string, unknown>).friendly_name === 'string'
        ? String((factor as Record<string, unknown>).friendly_name).slice(0, 100) : 'Aplicativo autenticador' })) };
}

export function validateCorporateRegistry(value: unknown, user: CorporateUser): void {
  if (!Array.isArray(value) || value.length !== 1 || !object(value[0]) || !uuid(value[0].id)
    || value[0].auth_user_id !== user.id || value[0].is_active !== true || typeof value[0].email !== 'string'
    || value[0].email.toLowerCase() !== user.email) throw new CorporateAuthError('CORP_FORBIDDEN');
}

export function validateCorporateDecision(value: unknown, subject: string, requiredCapability: CorporateCapability = 'em.portal.read'): CorporateDecision {
  if (!CORPORATE_CAPABILITIES.includes(requiredCapability)) throw new CorporateAuthError('CORP_FORBIDDEN');
  if (!object(value) || value.application !== CORPORATE_APP_SLUG || value.issuer !== CORPORATE_ISSUER || value.subject !== subject
    || typeof value.app_access !== 'boolean' || !Array.isArray(value.capabilities) || value.capabilities.length > CORPORATE_CAPABILITIES.length
    || !value.capabilities.every(code => typeof code === 'string' && CORPORATE_CAPABILITIES.includes(code as CorporateCapability))
    || new Set(value.capabilities).size !== value.capabilities.length || value.all_employees !== false
    || !Array.isArray(value.fields) || value.fields.length !== 0 || value.export_allowed !== false) throw new CorporateAuthError('CORP_UNAVAILABLE');
  if (value.app_access !== true || !value.capabilities.includes('em.portal.read') || !value.capabilities.includes(requiredCapability)) throw new CorporateAuthError('CORP_FORBIDDEN');
  return { application: 'em', issuer: CORPORATE_ISSUER, subject, app_access: true,
    capabilities: [...value.capabilities] as CorporateCapability[], all_employees: false, fields: [], export_allowed: false };
}
