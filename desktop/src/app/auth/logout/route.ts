import { serverSupabase } from '@/server/web/auth';
import { sameOriginPost } from '@/server/web/auth-policy';
import { endSso } from '@/server/web/sso-bridge';
import { corporateSettings } from '@/server/web/sso-policy';
import { fixedOriginPost, SSO_HEADERS } from '../sso/handlers';

export const dynamic = 'force-dynamic';
export async function POST(request: Request) {
  if (process.env.EM_SSO_ENABLED === 'true') {
    try {
      const settings = corporateSettings();
      if (!settings || !fixedOriginPost(request, settings.publicOrigin)) return Response.json({ error: 'Solicitação não autorizada.' }, { status: 403, headers: SSO_HEADERS });
      await endSso();
      return new Response(null, { status: 303, headers: { ...SSO_HEADERS, Location: new URL('/login', settings.publicOrigin).href } });
    } catch { return Response.json({ error: 'Não foi possível sair agora. Tente novamente.' }, { status: 503, headers: SSO_HEADERS }); }
  }
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host');
  if (!sameOriginPost(request.headers.get('origin'), host)) return Response.json({ error: 'Solicitação não autorizada.' }, { status: 403, headers: SSO_HEADERS });
  const client = await serverSupabase();
  const { error } = await client.auth.signOut({ scope: 'local' });
  if (error) return Response.json({ error: 'Não foi possível sair agora. Tente novamente.' }, { status: 503, headers: SSO_HEADERS });
  return new Response(null, { status: 303, headers: { Location: '/login', ...SSO_HEADERS } });
}
