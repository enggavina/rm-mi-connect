import type { WorkshopMediaSource } from '@/shared/workshop-media';
import { getWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { uuid } from '@/server/web/policy';
import { CorporateAuthError } from '@/server/web/sso-policy';
import { WorkshopContextError } from '@/server/web/workshop-context';
import { workshopMediaTarget } from '@/server/web/workshop-media';
import { readWorkshopOperations } from '@/server/web/workshop-operation-reader';

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
    const read = await readWorkshopOperations(access);
    if (!read) return failure(404);
    const value = await read('media_reference', { id, source, ...(index === null ? {} : { index: Number(index) }) });
    if (value === null) return failure(404);
    if (value?.id !== id.toLowerCase() || typeof value.file !== 'string' && value.file !== null) return failure(503);
    const target = workshopMediaTarget(value.file, process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '', source);
    if (!target) return failure(404);
    if (target.kind === 'legacy') return new Response(null, { status: 303, headers: { ...headers, Location: target.url } });

    const signed = await access.client.storage.from(target.bucket).createSignedUrl(target.path, 60);
    if (signed.error || !signed.data?.signedUrl) return failure(403);
    const destination = new URL(signed.data.signedUrl);
    if (destination.origin !== target.origin || destination.username || destination.password
      || !destination.pathname.startsWith(`/storage/v1/object/sign/${target.bucket}/`)) return failure(503);
    return new Response(null, { status: 303, headers: { ...headers, Location: destination.href } });
  } catch (error) {
    return failure(error instanceof CorporateAuthError || error instanceof WorkshopContextError ? error.status : 503);
  }
}
