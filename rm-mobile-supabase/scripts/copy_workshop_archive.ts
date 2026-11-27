/** Run the script with desktop's tsx from the repository root. Defaults to inventory only. */
import { createHash } from 'node:crypto';
import { parseArgs } from 'node:util';
import { adminClient, required } from '../../desktop/src/server/config';
import { inspectLegacyPdf, MAX_LEGACY_PDF_BYTES } from '../../desktop/src/server/bridge/pdf-document';
import { resolveWorkshopArchive, resolveWorkshopMedia } from '../../desktop/src/server/web/workshop-media';

const origin = 'https://ellpxfbsrbhblyizvbbk.supabase.co';
const bucket = 'rm-documentos';
const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const digest = /^[a-f0-9]{64}$/;
const hash = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
type Candidate = { reference: string; reference_sha256: string };

async function bytesFrom(url: string) {
  const response = await fetch(url, { redirect: 'error', credentials: 'omit', signal: AbortSignal.timeout(45_000) });
  const reader = response.body?.getReader();
  if (!reader || response.status !== 200 || Number(response.headers.get('content-length')) > MAX_LEGACY_PDF_BYTES) {
    await reader?.cancel().catch(() => undefined);
    throw new Error('DOWNLOAD_FAILED');
  }
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_LEGACY_PDF_BYTES) throw new Error('SIZE_EXCEEDED');
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    throw error;
  }
  return Buffer.concat(chunks, size);
}

function contentType(bytes: Buffer) {
  if (bytes.subarray(0, 5).toString('ascii') === '%PDF-') {
    inspectLegacyPdf(bytes);
    return { mime: 'application/pdf', suffix: 'pdf' };
  }
  if (bytes.subarray(0, 3).toString('hex') === 'ffd8ff') return { mime: 'image/jpeg', suffix: 'jpg' };
  if (bytes.subarray(0, 8).toString('hex') === '89504e470d0a1a0a') return { mime: 'image/png', suffix: 'png' };
  if (bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP') return { mime: 'image/webp', suffix: 'webp' };
  if (bytes.length > 16 && bytes.subarray(4, 8).toString('ascii') === 'ftyp') {
    const size = bytes.readUInt32BE(0);
    if (size < 16 || size > bytes.length || size % 4 !== 0) throw new Error('INVALID_FORMAT');
    const brands = [bytes.subarray(8, 12).toString('ascii')];
    for (let offset = 16; offset < size; offset += 4) brands.push(bytes.subarray(offset, offset + 4).toString('ascii'));
    if (brands.some(brand => ['heic', 'heix', 'hevc', 'hevx'].includes(brand))) return { mime: 'image/heic', suffix: 'heic' };
    if (brands.some(brand => ['mif1', 'msf1'].includes(brand))) return { mime: 'image/heif', suffix: 'heif' };
  }
  throw new Error('UNSUPPORTED_FORMAT');
}

async function main() {
  const { values } = parseArgs({ options: {
    workshop: { type: 'string' }, project: { type: 'string' }, provider: { type: 'string' }, after: { type: 'string' },
    limit: { type: 'string', default: '25' }, apply: { type: 'boolean' },
  } });
  const { workshop, project, provider, after } = values;
  const limit = Number(values.limit);
  if (!workshop || !uuid.test(workshop) || project && !uuid.test(project) || (provider !== 'em' && provider !== 'bubble')
    || after && !digest.test(after) || !Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('INVALID_BATCH');

  process.loadEnvFile('desktop/.env');
  if (required('SUPABASE_URL') !== origin) throw new Error('INVALID_DESTINATION');
  const database = adminClient();
  const { data, error } = await database.rpc('rm_workshop_archive_queue_v1', {
    p_workshop: workshop, p_project: project ?? null, p_provider: provider, p_after: after ?? null, p_limit: limit,
  });
  if (error || !Array.isArray(data) || data.length > limit || data.some(row => typeof row?.reference !== 'string'
    || row.reference_sha256 !== hash(row.reference))) throw new Error('INVALID_QUEUE');
  const queue = data as Candidate[];
  const next = queue.at(-1)?.reference_sha256;
  if (!values.apply) { console.log(JSON.stringify({ provider, planned: queue.length, next })); return; }

  const sign = async (name: string, path: string) => {
    const signed = await database.storage.from(name).createSignedUrl(path, 60);
    return signed.data?.signedUrl;
  };
  const failures: { reference_sha256: string; stage: string }[] = [];
  let copied = 0, bytesCopied = 0;
  for (const { reference, reference_sha256 } of queue) {
    let stage = 'source';
    try {
      const source = await resolveWorkshopMedia(reference, origin, 'document', sign)
        ?? await resolveWorkshopMedia(reference, origin, 'project_photo', sign)
        ?? await resolveWorkshopMedia(reference, origin, 'answer_signature', sign);
      if (!source) throw new Error('SOURCE_UNAVAILABLE');
      const bytes = await bytesFrom(source);
      stage = 'format';
      const { mime, suffix } = contentType(bytes), sha = hash(bytes);
      const path = `acervo-oficina/${workshop}/${reference_sha256}.${suffix}`;
      stage = 'copy';
      // The name is deterministic. A retry can verify a copy already present without replacing it.
      await database.storage.from(bucket).upload(path, bytes, { upsert: false, contentType: mime, metadata: { sha256: sha } });
      stage = 'verify';
      const archive = await resolveWorkshopArchive(path, origin, sign, workshop);
      if (!archive) throw new Error('COPY_UNAVAILABLE');
      const verified = await bytesFrom(archive);
      if (verified.length !== bytes.length || hash(verified) !== sha) throw new Error('COPIED_BYTES_DIVERGED');
      stage = 'confirm';
      const confirmation = await database.rpc('rm_confirm_workshop_archive_v1', {
        p_workshop: workshop, p_reference: reference, p_content_sha256: sha, p_mime: mime, p_size: bytes.length,
      });
      if (confirmation.error || confirmation.data !== path) throw new Error('CONFIRMATION_FAILED');
      copied++;
      bytesCopied += bytes.length;
    } catch {
      failures.push({ reference_sha256, stage });
    }
  }
  console.log(JSON.stringify({ provider, planned: queue.length, copied, bytesCopied, next, failures }));
  if (failures.length) process.exitCode = 1;
}

main().catch(() => { console.error('Não foi possível executar o lote do acervo. Confira destino, configuração e argumentos.'); process.exitCode = 1; });
