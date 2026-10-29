import { createServerClient } from '@supabase/ssr';
import { cache } from 'react';
import { cookies } from 'next/headers';
import { unstable_noStore as noStore } from 'next/cache';
import { redirect } from 'next/navigation';
import { required } from '../config';
import { resolveWebAccess, webCookieOptions, type WebAccess } from './auth-policy';

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
  return resolveWebAccess(await serverSupabase());
});

export async function getWebUser() {
  const access = await getWebAuthState();
  return access.state === 'authenticated' ? { client: access.client, user: access.user, profile: access.profile } : null;
}

export async function requireWebUser() {
  const access = await getWebAuthState();
  if (access.state === 'mfa') redirect('/login/mfa');
  if (access.state !== 'authenticated') redirect('/login');
  return { client: access.client, user: access.user, profile: access.profile };
}
