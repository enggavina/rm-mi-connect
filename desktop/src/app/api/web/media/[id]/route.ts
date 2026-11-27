import type { WorkshopMediaSource } from '@/shared/workshop-media';
import { getWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { uuid } from '@/server/web/policy';
import { CorporateAuthError } from '@/server/web/sso-policy';
import { WorkshopContextError } from '@/server/web/workshop-context';
import { isNativeWorkshopMediaPath, resolveWorkshopMedia, workshopMediaTarget } from '@/server/web/workshop-media';
import { readWorkshopOperations } from '@/server/web/workshop-operation-reader';
import { ssoWorkshopRead } from '@/server/web/sso-bridge';
import { signNativeWorkshopDocument } from '@/server/web/project-dossier-storage';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
const headers = { 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };
const failure = (status: number) => Response.json({ error: 'Mídia indisponível.' }, { status, headers });

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  try {
    const access = await getWebUser();
    if (!access) return failure(401);
    if (!hasWebCapability(access, 'em.photos.read')) return failure(403);
    const { id } = await context.params;
    const query = new URL(request.url).searchParams;
    const source = query.get('source') as WorkshopMediaSource | null;
    const index = query.get('index');
    if (!uuid.safeParse(id).success || (source !== 'project_photo' && source !== 'answer_signature' && source !== 'answer_photo')
      || (source === 'answer_photo' ? query.size !== 2 || !/^(0|[1-9]\d{0,5})$/.test(index ?? '') : query.size !== 1)) return failure(400);
    if (!hasWebCapability(access, source === 'project_photo' ? 'em.projects.read' : 'em.forms.read')) return failure(403);
    const read = await readWorkshopOperations(access) ?? (access.sso && await ssoWorkshopRead(access.sso, access.client));
    if (!read) return failure(404);
    const value = await read('media_reference', { id, source, ...(index === null ? {} : { index: Number(index) }) });
    if (value === null) return failure(404);
    if (value?.id !== id.toLowerCase() || typeof value.file !== 'string' && value.file !== null) return failure(503);
    if (typeof value.file !== 'string') return failure(404);
    const origin = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '';
    const target = workshopMediaTarget(value.file, origin, source);
    if (!target) return failure(404);
    let issued = false;
    const destination = await resolveWorkshopMedia(value.file, origin, source, async (bucket, path) => {
      const signed = bucket === 'rm-documentos' && isNativeWorkshopMediaPath(path) ? await signNativeWorkshopDocument(path)
        : (await access.client.storage.from(bucket).createSignedUrl(path, 60)).data?.signedUrl;
      issued = !!signed;
      return signed;
    });
    return destination ? new Response(null, { status: 303, headers: { ...headers, Location: destination } }) : failure(issued ? 503 : 403);
  } catch (error) {
    return failure(error instanceof CorporateAuthError || error instanceof WorkshopContextError ? error.status : 503);
  }
}
