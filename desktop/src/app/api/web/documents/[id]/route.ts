import { getWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { documentSource, documentTarget, uuid } from '@/server/web/policy';
import { CorporateAuthError } from '@/server/web/sso-policy';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const headers = { 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  try {
    const current = await getWebUser();
    if (!current) return Response.json({ error: 'Autenticação necessária.' }, { status: 401, headers });
    if (!hasWebCapability(current, 'em.documents.read')) return Response.json({ error: 'Acesso a documentos não autorizado.' }, { status: 403, headers });
    const { id } = await context.params;
    const source = documentSource(new URL(request.url).searchParams.get('source'));
    if (!uuid.safeParse(id).success || !source) return Response.json({ error: 'Documento inválido.' }, { status: 400, headers });
    const { data, error } = await current.client.from(source.table)
      .select(source.column === 'arquivo_nota_fiscal_url' ? 'id,file:arquivo_nota_fiscal_url' : 'id,file:arquivo_url').eq('id', id).maybeSingle();
    if (error) return Response.json({ error: 'Não foi possível consultar o documento.' }, { status: 503, headers });
    if (!data) return Response.json({ error: 'Documento não encontrado.' }, { status: 404, headers });
    const target = documentTarget(data.file, process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '');
    if (!target) return Response.json({ error: 'Este documento ainda não possui um arquivo disponível para leitura.' }, { status: 404, headers });
    let destination: string;
    if (target.kind === 'private') {
      const signed = await current.client.storage.from(target.bucket).createSignedUrl(target.path, 60);
      if (signed.error || !signed.data?.signedUrl) return Response.json({ error: 'Não foi possível autorizar o download.' }, { status: 403, headers });
      destination = signed.data.signedUrl;
    } else destination = target.url;
    // Only a redirect is emitted. This server never fetches a stored arbitrary URL.
    return new Response(null, { status: 303, headers: { ...headers, Location: destination } });
  } catch (error) {
    const status = error instanceof CorporateAuthError ? error.status : 503;
    return Response.json({ error: status === 403 ? 'Acesso a documentos não autorizado.' : 'Não foi possível consultar o documento.' }, { status, headers });
  }
}
