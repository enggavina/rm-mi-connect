import { serverSupabase } from '@/server/web/auth';
import { sameOriginPost } from '@/server/web/auth-policy';

export const dynamic = 'force-dynamic';
export async function POST(request: Request) {
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host');
  if (!sameOriginPost(request.headers.get('origin'), host)) return Response.json({ error: 'Solicitação não autorizada.' }, { status: 403, headers: { 'Cache-Control': 'private, no-store' } });
  const client = await serverSupabase();
  const { error } = await client.auth.signOut({ scope: 'local' });
  if (error) return Response.json({ error: 'Não foi possível sair agora. Tente novamente.' }, { status: 503, headers: { 'Cache-Control': 'private, no-store' } });
  return new Response(null, { status: 303, headers: { Location: '/login', 'Cache-Control': 'private, no-store' } });
}
