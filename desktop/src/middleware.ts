import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { webCookieOptions } from './server/web/auth-policy';

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_ANON_KEY;
  if (url && key && process.env.EM_SSO_ENABLED !== 'true') {
    const client = createServerClient(url, key, {
      cookieOptions: { name: 'em-web-session', ...webCookieOptions() },
      global: { fetch: (input, init) => fetch(input, { ...init, cache: 'no-store' }) },
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (values, headers) => {
          for (const { name, value } of values) request.cookies.set(name, value);
          const previous = response.cookies.getAll();
          response = NextResponse.next({ request });
          for (const cookie of previous) response.cookies.set(cookie);
          for (const { name, value, options } of values) response.cookies.set(name, value, { ...options, ...webCookieOptions() });
          for (const [name, value] of Object.entries(headers)) response.headers.set(name, value);
        },
      },
    });
    // Verifies and refreshes; the page/API still checks the active RM profile and MFA.
    await client.auth.getUser();
  }
  response.headers.set('Cache-Control', 'private, no-store, max-age=0');
  response.headers.set('Pragma', 'no-cache');
  response.headers.set('Expires', '0');
  if (request.nextUrl.pathname.startsWith('/auth/') || request.nextUrl.pathname.startsWith('/login')) response.headers.set('Referrer-Policy', 'no-referrer');
  return response;
}

export const config = {
  matcher: ['/((?!api/health|api/sync|api/webhooks|api/reports|api/auth/totp|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)'],
};
