import { z } from 'zod';
import type { WorkshopMediaSource } from '@/shared/workshop-media';

export const workshopMediaMatch = z.object({ url: z.string().max(2048),
  source: z.enum(['document', 'project_photo', 'answer_photo', 'answer_signature']) }).strict();

export function workshopMediaTarget(raw: unknown, supabaseOrigin: string, source: WorkshopMediaSource | 'document') {
  if (typeof raw !== 'string') return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash) return null;
    if (url.hostname.endsWith('.cdn.bubble.io')) return { kind: 'legacy' as const, url: url.href };
    const origin = new URL(supabaseOrigin);
    if (url.origin !== origin.origin || url.search || raw.includes('\\')
      || /\/(?:\.|%2e){1,2}(?=\/|$)/i.test(raw)) return null;
    const bucket = source === 'document' ? 'rm-documentos' : source === 'answer_signature' ? 'rm-assinaturas' : 'rm-fotos';
    const prefix = [`/storage/v1/object/public/${bucket}/`, `/storage/v1/object/authenticated/${bucket}/`]
      .find(path => url.pathname.startsWith(path));
    if (!prefix) return null;
    const path = decodeURIComponent(url.pathname.slice(prefix.length));
    if (!path || /[%\\\x00-\x1f]/.test(path) || path.split('/').some(part => !part || part === '.' || part === '..')) return null;
    return { kind: 'storage' as const, origin: origin.origin, bucket, path };
  } catch {
    return null;
  }
}

export async function resolveWorkshopMedia(reference: string, origin: string, source: z.infer<typeof workshopMediaMatch>['source'],
  sign: (bucket: string, path: string) => Promise<string | undefined>): Promise<string | null> {
  const target = workshopMediaTarget(reference, origin, source);
  if (!target) return null;
  if (target.kind === 'legacy') return target.url;
  const signed = await sign(target.bucket, target.path);
  if (!signed) return null;
  try {
    const destination = new URL(signed);
    const path = `/storage/v1/object/sign/${target.bucket}/${target.path}`;
    if (destination.origin !== target.origin || destination.username || destination.password || destination.hash
      || decodeURIComponent(destination.pathname) !== path || destination.searchParams.size !== 1
      || !destination.searchParams.get('token')) return null;
    return destination.href;
  } catch {
    return null;
  }
}
