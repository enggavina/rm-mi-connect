import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { required } from '../config';
import { attachmentSignatureMatches, projectAttachmentPath, type ProjectAttachmentInput } from './project-dossier-policy';
import { isNativeWorkshopMediaPath, resolveWorkshopArchive } from './workshop-media';

function documentStorage() {
  const url = required('SUPABASE_URL');
  if (url !== 'https://ellpxfbsrbhblyizvbbk.supabase.co') throw new Error('Invalid EM storage target');
  return createClient(url, required('EM_SSO_BRIDGE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: (resource, init) => fetch(resource, { ...init, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(30_000) }) } }).storage.from('rm-documentos');
}

// Call after the workshop reader confirms the exact stored attachment.
export async function signNativeWorkshopDocument(path: string) {
  if (!isNativeWorkshopMediaPath(path)) return undefined;
  const { data, error } = await documentStorage().createSignedUrl(path, 60);
  return error ? undefined : data?.signedUrl;
}

export async function signWorkshopArchive(path: unknown, origin: string) {
  return resolveWorkshopArchive(path, origin, async (_bucket, safePath) => {
    const { data } = await documentStorage().createSignedUrl(safePath, 60);
    return data?.signedUrl;
  });
}

/** Only this immutable, server-derived namespace uses the private EM credential. */
export async function storeProjectAttachment(input: ProjectAttachmentInput, bytes: Uint8Array): Promise<void> {
  if (bytes.length !== input.byte_size) throw new Error('Attachment does not match its frozen request');
  await storeImmutableDocument(projectAttachmentPath(input.projeto_id, input.submissionId, input.mime_type), bytes, input.mime_type, input.sha256);
}

export async function storeImmutableDocument(path: string, bytes: Uint8Array, mime: ProjectAttachmentInput['mime_type'], sha256: string): Promise<void> {
  if (createHash('sha256').update(bytes).digest('hex') !== sha256 || !attachmentSignatureMatches(bytes, mime)) {
    throw new Error('Attachment does not match its frozen request');
  }
  const bucket = documentStorage();
  const result = await bucket.upload(path, bytes, { upsert: false, contentType: mime, metadata: { sha256 } });
  if (!result.error) return;
  // A lost response may leave the exact object in place. Never overwrite it.
  if (!['409', '400'].includes(String((result.error as { statusCode?: string }).statusCode))
    || !/already exists|duplicate/i.test(result.error.message)) throw new Error('Attachment upload could not be confirmed');
  const existing = await bucket.download(path);
  if (existing.error || !existing.data || existing.data.size !== bytes.length) throw new Error('Existing attachment differs');
  const actual = new Uint8Array(await existing.data.arrayBuffer());
  if (createHash('sha256').update(actual).digest('hex') !== sha256) throw new Error('Existing attachment differs');
}
