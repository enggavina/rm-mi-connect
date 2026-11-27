import { z } from 'zod';
import type { WorkshopMediaSource } from '@/shared/workshop-media';

export const workshopMediaMatch = z.object({ url: z.string().max(2048),
  source: z.enum(['document', 'project_photo', 'answer_photo', 'answer_signature']), archive_path: z.string().optional() }).strict();

const uuidSegment = '[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}';
const nativePath = new RegExp(`^mobile-oficina/${uuidSegment}/${uuidSegment}/${uuidSegment}\\.(jpg|png|pdf)$`);
const dossierPath = new RegExp(`^web-dossier/${uuidSegment}/${uuidSegment}\\.(jpg|png|pdf)$`);
const archivePath = new RegExp(`^acervo-oficina/(${uuidSegment})/[a-f0-9]{64}\\.(jpg|png|pdf|webp|heic|heif|docx)$`);
const legacyImagePath = new RegExp(`^${uuidSegment}/${uuidSegment}\\.(jpg|png)$`);
const nativePrefix = '/storage/v1/object/authenticated/rm-documentos/';
export function isNativeWorkshopMediaPath(path: string) {
  return nativePath.test(path);
}

export function isWorkshopDossierPath(path: string) {
  return dossierPath.test(path);
}

export function workshopMediaTarget(raw: unknown, supabaseOrigin: string, source: WorkshopMediaSource | 'document') {
  if (typeof raw !== 'string') return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash) return null;
    const origin = new URL(supabaseOrigin);
    if (url.origin !== origin.origin || url.search || raw.includes('\\')
      || /\/(?:\.|%2e){1,2}(?=\/|$)/i.test(raw)) return null;
    if (url.pathname.startsWith(`${nativePrefix}mobile-oficina/`)) {
      const path = url.pathname.slice(nativePrefix.length);
      if (!isNativeWorkshopMediaPath(path) || raw !== `${origin.origin}${nativePrefix}${path}`) return null;
      return { kind: 'storage' as const, origin: origin.origin, bucket: 'rm-documentos', path };
    }
    const bucket = source === 'document' ? 'rm-documentos' : source === 'answer_signature' ? 'rm-assinaturas' : 'rm-fotos';
    const prefix = [`/storage/v1/object/public/${bucket}/`, `/storage/v1/object/authenticated/${bucket}/`]
      .find(path => url.pathname.startsWith(path));
    if (!prefix) return null;
    const path = decodeURIComponent(url.pathname.slice(prefix.length));
    if (!path || path.startsWith('mobile-oficina/') || path.startsWith('acervo-oficina/') || /[%\\\x00-\x1f]/.test(path)
      || path.split('/').some(part => !part || part === '.' || part === '..')) return null;
    if (path.startsWith('web-dossier/') && (source !== 'document' || !isWorkshopDossierPath(path)
      || raw !== `${origin.origin}${nativePrefix}${path}`)) return null;
    return { kind: 'storage' as const, origin: origin.origin, bucket, path };
  } catch {
    return null;
  }
}

export function isNativeWorkshopMedia(raw: unknown, origin: string) {
  const target = workshopMediaTarget(raw, origin, 'document');
  return target !== null && isNativeWorkshopMediaPath(target.path);
}

type StorageSigner = (bucket: string, path: string) => Promise<string | undefined>;

async function signedStorageUrl(target: { origin: string; bucket: string; path: string }, sign: StorageSigner) {
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

export async function resolveWorkshopMedia(reference: string, origin: string, source: z.infer<typeof workshopMediaMatch>['source'],
  sign: StorageSigner): Promise<string | null> {
  const target = workshopMediaTarget(reference, origin, source);
  return target ? signedStorageUrl(target, sign) : null;
}

/** The archive path is issued by a scoped reader, never taken from a catalog URL. */
export async function resolveWorkshopArchive(path: unknown, origin: string, sign: StorageSigner, workshop?: string) {
  if (typeof path !== 'string') return null;
  const match = archivePath.exec(path);
  if (!match || workshop && match[1] !== workshop) return null;
  return signedStorageUrl({ origin: new URL(origin).origin, bucket: 'rm-documentos', path }, sign);
}

/** Only the scoped database reader can supply the approved original path. */
export async function resolvePrivateLegacyWorkshopImage(reference: string, path: unknown, origin: string,
  source: WorkshopMediaSource, sign: StorageSigner) {
  if (typeof path !== 'string' || !legacyImagePath.test(path)) return null;
  const target = workshopMediaTarget(reference, origin, source);
  if (!target || target.path !== path || target.bucket === 'rm-documentos'
    || (source === 'answer_signature' && !path.endsWith('.png'))) return null;
  return signedStorageUrl(target, sign);
}

const legacyImageTypes = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/avif', 'image/bmp', 'image/tiff',
  'image/heic', 'image/heif', 'image/heic-sequence', 'image/heif-sequence',
]);
const legacyImageMaxBytes = 20 * 1024 * 1024;

/** Relay an approved public image without returning its historical address. */
export async function relayLegacyWorkshopImage(url: string, signal: AbortSignal): Promise<{ body: ReadableStream<Uint8Array>; type: string } | null> {
  const upstream = await fetch(url, {
    cache: 'no-store', redirect: 'error', credentials: 'omit',
    signal: AbortSignal.any([signal, AbortSignal.timeout(12_000)]),
  });
  const type = upstream.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase();
  const length = upstream.headers.get('content-length');
  if (upstream.status !== 200 || !upstream.body || !type || !legacyImageTypes.has(type)
    || (length !== null && (!/^\d+$/.test(length) || Number(length) < 1 || Number(length) > legacyImageMaxBytes))) {
    await upstream.body?.cancel().catch(() => undefined);
    return null;
  }
  let transferred = 0;
  const body = upstream.body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      transferred += chunk.byteLength;
      if (transferred > legacyImageMaxBytes) throw new Error('Imagem histórica excede o limite.');
      controller.enqueue(chunk);
    },
  }));
  return { body, type };
}
