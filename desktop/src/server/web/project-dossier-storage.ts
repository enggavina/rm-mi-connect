import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { required } from '../config';
import { attachmentSignatureMatches, projectAttachmentPath, type ProjectAttachmentInput } from './project-dossier-policy';

/** Only this immutable, server-derived namespace uses the private EM credential. */
export async function storeProjectAttachment(input: ProjectAttachmentInput, bytes: Uint8Array): Promise<void> {
  const url = required('SUPABASE_URL');
  if (url !== 'https://ellpxfbsrbhblyizvbbk.supabase.co') throw new Error('Invalid EM storage target');
  const path = projectAttachmentPath(input.projeto_id, input.submissionId, input.mime_type);
  if (bytes.length !== input.byte_size || createHash('sha256').update(bytes).digest('hex') !== input.sha256
    || !attachmentSignatureMatches(bytes, input.mime_type)) throw new Error('Attachment does not match its frozen request');
  const client = createClient(url, required('EM_SSO_BRIDGE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: (resource, init) => fetch(resource, { ...init, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(30_000) }) } });
  const bucket = client.storage.from('rm-documentos');
  const result = await bucket.upload(path, bytes, { upsert: false, contentType: input.mime_type, metadata: { sha256: input.sha256 } });
  if (!result.error) return;
  // A lost response may leave the exact object in place. Never overwrite it.
  if (!['409', '400'].includes(String((result.error as { statusCode?: string }).statusCode))
    || !/already exists|duplicate/i.test(result.error.message)) throw new Error('Attachment upload could not be confirmed');
  const existing = await bucket.download(path);
  if (existing.error || !existing.data || existing.data.size !== input.byte_size) throw new Error('Existing attachment differs');
  const actual = new Uint8Array(await existing.data.arrayBuffer());
  if (createHash('sha256').update(actual).digest('hex') !== input.sha256) throw new Error('Existing attachment differs');
}
