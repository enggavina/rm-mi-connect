import type { WorkshopMediaSource } from '@/shared/workshop-media';

export function workshopMediaTarget(raw: unknown, supabaseOrigin: string, source: WorkshopMediaSource) {
  if (typeof raw !== 'string') return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash) return null;
    if (url.hostname.endsWith('.cdn.bubble.io')) return { kind: 'legacy' as const, url: url.href };
    const origin = new URL(supabaseOrigin);
    if (url.origin !== origin.origin || url.search) return null;
    const bucket = source === 'answer_signature' ? 'rm-assinaturas' : 'rm-fotos';
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
