import { getWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { documentSource, documentTarget, uuid } from '@/server/web/policy';
import { CorporateAuthError } from '@/server/web/sso-policy';
import { WorkshopContextError } from '@/server/web/workshop-context';
import { readWorkshopOperations } from '@/server/web/workshop-operation-reader';
import { isNativeWorkshopMediaPath, resolveWorkshopMedia } from '@/server/web/workshop-media';
import { signNativeWorkshopDocument, signWorkshopArchive, signWorkshopDossierDocument } from '@/server/web/project-dossier-storage';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const headers = { 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  try {
    const current = await getWebUser();
    if (!current) return Response.json({ error: 'Autenticação necessária.' }, { status: 401, headers });
    if (!hasWebCapability(current, 'em.documents.read')) return Response.json({ error: 'Acesso a documentos não autorizado.' }, { status: 403, headers });
    const { id } = await context.params;
    const kind = new URL(request.url).searchParams.get('source');
    const source = documentSource(kind);
    if (!uuid.safeParse(id).success || !source) return Response.json({ error: 'Documento inválido.' }, { status: 400, headers });
    const read = await readWorkshopOperations(current);
    let data: { id: string; file: unknown; archive_path?: unknown; web_dossier_path?: unknown } | null;
    if (read) {
      data = await read('document_link', { id, source: kind ?? 'documentos' });
      if (data && (data.id !== id.toLowerCase() || typeof data.file !== 'string' && data.file !== null)) {
        throw new WorkshopContextError('WORKSHOP_UNAVAILABLE');
      }
    } else {
      const lookup = await current.client.from(source.table)
        .select(source.column === 'arquivo_nota_fiscal_url' ? 'id,file:arquivo_nota_fiscal_url' : 'id,file:arquivo_url').eq('id', id).maybeSingle();
      if (lookup.error) return Response.json({ error: 'Não foi possível consultar o documento.' }, { status: 503, headers });
      data = lookup.data as { id: string; file: unknown } | null;
    }
    if (!data) return Response.json({ error: 'Documento não encontrado.' }, { status: 404, headers });
    const storageOrigin = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '';
    if (data.archive_path !== undefined) {
      const signed = await signWorkshopArchive(data.archive_path, storageOrigin);
      if (!signed) throw new WorkshopContextError('WORKSHOP_UNAVAILABLE');
      return new Response(null, { status: 303, headers: { ...headers, Location: signed } });
    }
    const target = documentTarget(data.file, storageOrigin, !read);
    if (!target) return Response.json({ error: 'Este documento ainda não possui um arquivo disponível para leitura.' }, { status: 404, headers });
    let destination: string;
    if (target.kind === 'private' && isNativeWorkshopMediaPath(target.path)) {
      if (!read) throw new WorkshopContextError('WORKSHOP_FORBIDDEN');
      const signed = typeof data.file === 'string' && await resolveWorkshopMedia(data.file, storageOrigin, 'document', (_bucket, path) => signNativeWorkshopDocument(path));
      if (!signed) throw new WorkshopContextError('WORKSHOP_UNAVAILABLE');
      destination = signed;
    } else if (target.kind === 'private' && target.path.startsWith('web-dossier/') && read) {
      if (data.web_dossier_path !== target.path || typeof data.file !== 'string') {
        return Response.json({ error: 'Documento não encontrado.' }, { status: 404, headers });
      }
      const signed = await resolveWorkshopMedia(data.file, storageOrigin, 'document', (_bucket, path) => signWorkshopDossierDocument(path));
      if (!signed) throw new WorkshopContextError('WORKSHOP_UNAVAILABLE');
      destination = signed;
    } else if (target.kind === 'private') {
      const signed = await current.client.storage.from(target.bucket).createSignedUrl(target.path, 60);
      if (signed.error || !signed.data?.signedUrl) return Response.json({ error: 'Não foi possível autorizar o download.' }, { status: 403, headers });
      destination = signed.data.signedUrl;
    } else destination = target.url;
    // Only a redirect is emitted. This server never fetches a stored arbitrary URL.
    return new Response(null, { status: 303, headers: { ...headers, Location: destination } });
  } catch (error) {
    const status = error instanceof CorporateAuthError || error instanceof WorkshopContextError ? error.status : 503;
    return Response.json({ error: status === 403 ? 'Acesso a documentos não autorizado.' : 'Não foi possível consultar o documento.' }, { status, headers });
  }
}
