/** Run the script with desktop's tsx from the repository root. Defaults to inventory only. */
import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
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
type Failure = { reference_sha256: string; stage: string; reason: string };

class ArchiveError extends Error {
  constructor(readonly reason: string, readonly retryable = false) { super(reason); }
}

function retryableStatus(status: number) {
  return status === 0 || status === 408 || status === 425 || status === 429 || status >= 500;
}

async function retry<T>(operation: () => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try { return await operation(); }
    catch (error) {
      const transient = error instanceof ArchiveError ? error.retryable : error instanceof TypeError
        || error instanceof DOMException && ['AbortError', 'TimeoutError'].includes(error.name);
      if (!transient || attempt === 2) throw error;
      await delay((attempt + 1) * 1_000);
    }
  }
}

async function bytesFrom(url: string) {
  const response = await fetch(url, { redirect: 'error', credentials: 'omit', signal: AbortSignal.timeout(45_000) });
  const reader = response.body?.getReader();
  if (response.status !== 200 || !reader) {
    await reader?.cancel().catch(() => undefined);
    throw new ArchiveError(`HTTP_${response.status}`, retryableStatus(response.status));
  }
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    if (Number(response.headers.get('content-length')) > MAX_LEGACY_PDF_BYTES) throw new ArchiveError('SIZE_EXCEEDED');
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_LEGACY_PDF_BYTES) throw new ArchiveError('SIZE_EXCEEDED');
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
    limit: { type: 'string', default: '25' }, apply: { type: 'boolean' }, all: { type: 'boolean' },
    concurrency: { type: 'string', default: '1' },
  } });
  const { workshop, project, provider, after } = values;
  const limit = Number(values.limit), concurrency = Number(values.concurrency);
  if (!workshop || !uuid.test(workshop) || project && !uuid.test(project) || (provider !== 'em' && provider !== 'bubble')
    || after && !digest.test(after) || !Number.isInteger(limit) || limit < 1 || limit > 100
    || !Number.isInteger(concurrency) || concurrency < 1 || concurrency > 8) throw new Error('INVALID_BATCH');

  process.loadEnvFile('desktop/.env');
  if (required('SUPABASE_URL') !== origin) throw new Error('INVALID_DESTINATION');
  const database = adminClient();
  const sign = async (name: string, path: string) => {
    return retry(async () => {
      const signed = await database.storage.from(name).createSignedUrl(path, 60);
      if (signed.error) {
        const status = Number('statusCode' in signed.error ? signed.error.statusCode : 0);
        if (retryableStatus(status)) throw new ArchiveError('SIGN_UNAVAILABLE', true);
      }
      return signed.data?.signedUrl;
    });
  };
  async function copy({ reference, reference_sha256 }: Candidate): Promise<number | Failure> {
    let stage = 'source';
    try {
      const source = await resolveWorkshopMedia(reference, origin, 'document', sign)
        ?? await resolveWorkshopMedia(reference, origin, 'project_photo', sign)
        ?? await resolveWorkshopMedia(reference, origin, 'answer_signature', sign);
      if (!source) throw new Error('SOURCE_UNAVAILABLE');
      const bytes = await retry(() => bytesFrom(source));
      stage = 'format';
      const { mime, suffix } = contentType(bytes), sha = hash(bytes);
      const path = `acervo-oficina/${workshop}/${reference_sha256}.${suffix}`;
      stage = 'copy';
      // The name is deterministic. A retry can verify a copy already present without replacing it.
      await retry(async () => {
        const { error } = await database.storage.from(bucket).upload(path, bytes, { upsert: false, contentType: mime, metadata: { sha256: sha } });
        if (!error) return;
        const status = Number('statusCode' in error ? error.statusCode : 0);
        if ((status === 400 || status === 409) && /already exists|alreadyexists|duplicate/i.test(error.message)) return;
        const code = Number.isInteger(status) && status > 0 ? `HTTP_${status}` : 'UPLOAD_UNAVAILABLE';
        throw new ArchiveError(code, retryableStatus(status));
      });
      stage = 'verify';
      const archive = await resolveWorkshopArchive(path, origin, sign, workshop);
      if (!archive) throw new Error('COPY_UNAVAILABLE');
      const verified = await retry(() => bytesFrom(archive));
      if (verified.length !== bytes.length || hash(verified) !== sha) throw new Error('COPIED_BYTES_DIVERGED');
      stage = 'confirm';
      await retry(async () => {
        const confirmation = await database.rpc('rm_confirm_workshop_archive_v1', {
          p_workshop: workshop, p_reference: reference, p_content_sha256: sha, p_mime: mime, p_size: bytes.length,
        }).abortSignal(AbortSignal.timeout(30_000));
        if (confirmation.error || confirmation.data !== path) throw new ArchiveError('CONFIRMATION_FAILED', retryableStatus(confirmation.status));
      });
      return bytes.length;
    } catch (error) {
      const reason = error instanceof ArchiveError ? error.reason : stage === 'format' ? 'UNSUPPORTED_FORMAT' : 'TRANSFER_FAILED';
      return { reference_sha256, stage, reason };
    }
  }

  const failures: Failure[] = [];
  let next = after;
  let planned = 0, copied = 0, bytesCopied = 0;
  for (;;) {
    const queue = await retry(async () => {
      const { data, error, status } = await database.rpc('rm_workshop_archive_queue_v1', {
        p_workshop: workshop, p_project: project ?? null, p_provider: provider, p_after: next ?? null, p_limit: limit,
      }).abortSignal(AbortSignal.timeout(30_000));
      if (error) throw new ArchiveError('QUEUE_UNAVAILABLE', retryableStatus(status));
      if (!Array.isArray(data) || data.length > limit || data.some((row, index) => typeof row?.reference !== 'string'
        || row.reference_sha256 !== hash(row.reference)
        || row.reference_sha256 <= (index ? data[index - 1].reference_sha256 : (next ?? '')))) throw new ArchiveError('INVALID_QUEUE');
      return data as Candidate[];
    });
    if (!queue.length) break;
    planned += queue.length;
    if (values.apply) {
      const pending = queue.entries();
      const results: (number | Failure)[] = [];
      await Promise.all(Array.from({ length: Math.min(concurrency, queue.length) }, async () => {
        for (const [index, candidate] of pending) results[index] = await copy(candidate);
      }));
      for (const result of results) {
        if (typeof result === 'number') { copied++; bytesCopied += result; }
        else failures.push(result);
      }
    }
    next = queue.at(-1)?.reference_sha256;
    if (values.all) console.log(JSON.stringify({ phase: 'batch', provider, planned, copied, bytesCopied, next, failed: failures.length }));
    if (!values.all || queue.length < limit) break;
  }
  console.log(JSON.stringify(values.apply ? { provider, planned, copied, bytesCopied, next, failures } : { provider, planned, next }));
  if (failures.length) process.exitCode = 1;
}

main().catch(() => { console.error('Não foi possível executar o lote do acervo. Confira destino, configuração e argumentos.'); process.exitCode = 1; });
