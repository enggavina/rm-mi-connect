import type { SupabaseClient, User } from '@supabase/supabase-js';
import type { CorporateCapability } from './sso-policy';

export interface SsoContext { sessionHash: string; bindingId: string; subject: string; capabilities: CorporateCapability[] }

export interface WebProfile { id: string; nome: string; perfil: string; cargo?: string | null; matricula?: string | null }
const INTERNAL_WEB_PROFILES = new Set(['administrador', 'padr_o', 'auditor']);
export type WebAccess =
  | { state: 'anonymous' | 'inactive'; client: SupabaseClient }
  | { state: 'mfa'; client: SupabaseClient; user: User; profile: WebProfile; factors: { id: string; name: string }[] }
  | { state: 'authenticated'; client: SupabaseClient; user: User; profile: WebProfile; sso?: SsoContext };

export function hasWebCapability(session: { sso?: Pick<SsoContext, 'capabilities'> }, capability: CorporateCapability): boolean {
  return !session.sso || session.sso.capabilities.includes(capability);
}

export function webCookieOptions(production = process.env.NODE_ENV === 'production') {
  return { path: '/', httpOnly: true, sameSite: 'lax' as const, secure: production };
}

/** A cookie's embedded user/profile is never an authorization source. */
export async function resolveWebAccess(client: SupabaseClient, jwt?: string): Promise<WebAccess> {
  const { data: identity, error } = await client.auth.getUser(jwt);
  if (error || !identity.user) return { state: 'anonymous', client };
  const user = identity.user;
  const { data: row, error: profileError } = await client.from('rm_users')
    .select('id,auth_user_id,nome,perfil,cargo,matricula,status').eq('auth_user_id', user.id).eq('status', 'ativo').maybeSingle();
  if (profileError || !row || row.auth_user_id !== user.id || row.status !== 'ativo'
    || typeof row.id !== 'string' || typeof row.nome !== 'string' || !INTERNAL_WEB_PROFILES.has(row.perfil)) return { state: 'inactive', client };
  const profile: WebProfile = { id: row.id, nome: row.nome, perfil: row.perfil, cargo: row.cargo, matricula: row.matricula };
  const factors = (user.factors ?? []).filter(factor => factor.factor_type === 'totp' && factor.status === 'verified')
    .map(factor => ({ id: factor.id, name: (factor.friendly_name || 'Aplicativo autenticador').slice(0, 100) }));
  if (factors.length) {
    const { data, error: claimsError } = await client.auth.getClaims(jwt);
    if (claimsError || data?.claims?.sub !== user.id || data.claims.aal !== 'aal2') return { state: 'mfa', client, user, profile, factors };
  }
  return { state: 'authenticated', client, user, profile };
}

export function sameOriginPost(origin: string | null, host: string | null): boolean {
  if (!origin || !host || /[,\s]/.test(host)) return false;
  try { const parsed = new URL(origin); return ['http:', 'https:'].includes(parsed.protocol) && !parsed.username && !parsed.password && parsed.host === host; }
  catch { return false; }
}
