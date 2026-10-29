import { createServerClient } from '@supabase/ssr';
import { cache } from 'react';
import { cookies } from 'next/headers';
import { unstable_noStore as noStore } from 'next/cache';
import { redirect } from 'next/navigation';
import { required } from '../config';
import { resolveWebAccess, webCookieOptions, hasWebCapability, type WebAccess } from './auth-policy';
import { getSsoWebAccess, localSsoClient } from './sso-bridge';
import { CorporateAuthError, type CorporateCapability } from './sso-policy';

export async function serverSupabase() {
  noStore();
  const store = await cookies();
  return createServerClient(required('SUPABASE_URL'), required('SUPABASE_ANON_KEY'), {
    cookieOptions: { name: 'em-web-session', ...webCookieOptions() },
    global: { fetch: (input, init) => fetch(input, { ...init, cache: 'no-store' }) },
    cookies: {
      getAll: () => store.getAll(),
      setAll: values => {
        try { for (const { name, value, options } of values) store.set(name, value, { ...options, ...webCookieOptions() }); }
        catch {
          // Server Components cannot write cookies. Middleware refreshes before they render.
        }
      },
    },
  });
}

export const getWebAuthState = cache(async (): Promise<WebAccess | { state: 'unconfigured' }> => {
  noStore();
  if (!process.env.SUPABASE_URL?.trim() || !process.env.SUPABASE_ANON_KEY?.trim()) return { state: 'unconfigured' };
  if (process.env.EM_SSO_ENABLED === 'true') {
    try { return await getSsoWebAccess(); }
    catch (error) {
      if (error instanceof CorporateAuthError && ['CORP_UNAUTHORIZED', 'CORP_MFA_REQUIRED'].includes(error.code)) return { state: 'anonymous', client: localSsoClient() };
      throw error;
    }
  }
  return resolveWebAccess(await serverSupabase());
});

export async function getWebUser(requiredCapability?: CorporateCapability | CorporateCapability[]) {
  const access = await getWebAuthState();
  if (access.state !== 'authenticated') return null;
  const required = requiredCapability ? [requiredCapability].flat() : [];
  if (required.some(capability => !hasWebCapability(access, capability))) throw new CorporateAuthError('CORP_FORBIDDEN');
  return { client: access.client, user: access.user, profile: access.profile, sso: access.sso };
}

export async function requireWebUser(requiredCapability?: CorporateCapability | CorporateCapability[]) {
  let access;
  try { access = await getWebAuthState(); }
  catch (error) {
    if (error instanceof CorporateAuthError) redirect(`/acesso?motivo=${error.status === 403 ? 'permissao' : 'indisponivel'}`);
    throw error;
  }
  if (access.state === 'mfa') redirect('/login/mfa');
  if (access.state !== 'authenticated') redirect('/login');
  const required = requiredCapability ? [requiredCapability].flat() : [];
  if (required.some(capability => !hasWebCapability(access, capability))) redirect('/acesso?motivo=permissao');
  return { client: access.client, user: access.user, profile: access.profile, sso: access.sso };
}
