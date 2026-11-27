/** Run the script with desktop's tsx from the repository root. Defaults to inventory only. */
import { createHash } from 'node:crypto';
import { open } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { parseArgs } from 'node:util';
import { crc32 } from 'node:zlib';
import { adminClient, required } from '../../desktop/src/server/config';
import { isWordDocument } from '../../desktop/src/server/bridge/docx-document';
import { inspectLegacyPdf, MAX_LEGACY_PDF_BYTES } from '../../desktop/src/server/bridge/pdf-document';
import { resolveWorkshopArchive, resolveWorkshopMedia } from '../../desktop/src/server/web/workshop-media';

const origin = 'https://ellpxfbsrbhblyizvbbk.supabase.co';
const bucket = 'rm-documentos';
const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const digest = /^[a-f0-9]{64}$/;
const hash = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
type Candidate = { reference: string; reference_sha256: string };
type Failure = { reference_sha256: string; stage: string; reason: string };
const pngMagic = Buffer.from('89504e470d0a1a0a', 'hex');

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
  if (bytes.subarray(0, 8).equals(pngMagic)) return { mime: 'image/png', suffix: 'png' };
  if (bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP') return { mime: 'image/webp', suffix: 'webp' };
  if (isWordDocument(bytes)) return { mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', suffix: 'docx' };
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

async function readRecoveryPng(path: string, expectedSha256: string) {
  const file = await open(path, 'r');
  let bytes: Buffer;
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size < 57 || stat.size > MAX_LEGACY_PDF_BYTES) throw new ArchiveError('INVALID_PNG_SIZE');
    bytes = Buffer.alloc(stat.size);
    for (let offset = 0; offset < bytes.length;) {
      const { bytesRead } = await file.read(bytes, offset, bytes.length - offset, offset);
      if (!bytesRead) throw new ArchiveError('INVALID_PNG_SIZE');
      offset += bytesRead;
    }
    if ((await file.stat()).size !== stat.size) throw new ArchiveError('INVALID_PNG_SIZE');
  } finally { await file.close(); }
  if (hash(bytes) !== expectedSha256) throw new ArchiveError('SOURCE_HASH_MISMATCH');
  if (!bytes.subarray(0, 8).equals(pngMagic)) throw new ArchiveError('INVALID_PNG');
  let hasImageData = false;
  for (let offset = 8; offset + 12 <= bytes.length;) {
    const length = bytes.readUInt32BE(offset), end = offset + 8 + length;
    if (end + 4 > bytes.length || crc32(bytes.subarray(offset + 4, end)) !== bytes.readUInt32BE(end)) break;
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (offset === 8 && (type !== 'IHDR' || length !== 13 || !bytes.readUInt32BE(offset + 8) || !bytes.readUInt32BE(offset + 12))) break;
    if (type === 'IDAT' && length > 0) hasImageData = true;
    if (type === 'IEND') {
      if (length === 0 && hasImageData && end + 4 === bytes.length) return bytes;
      break;
    }
    offset = end + 4;
  }
  throw new ArchiveError('INVALID_PNG');
}

async function main() {
  const { values } = parseArgs({ options: {
    workshop: { type: 'string' }, project: { type: 'string' }, provider: { type: 'string' }, after: { type: 'string' },
    limit: { type: 'string', default: '25' }, apply: { type: 'boolean' }, all: { type: 'boolean' },
    concurrency: { type: 'string', default: '1' },
    'recover-png': { type: 'string' }, 'reference-sha256': { type: 'string' }, 'content-sha256': { type: 'string' },
  } });
  const { workshop, project, provider, after } = values;
  const recoveryPath = values['recover-png'], referenceHash = values['reference-sha256'], contentHash = values['content-sha256'];
  const limit = Number(values.limit), concurrency = Number(values.concurrency);
  if (!workshop || !uuid.test(workshop) || project && !uuid.test(project) || (provider !== 'em' && provider !== 'bubble')
    || after && !digest.test(after) || !Number.isInteger(limit) || limit < 1 || limit > 100
    || !Number.isInteger(concurrency) || concurrency < 1 || concurrency > 8) throw new Error('INVALID_BATCH');
  if ([recoveryPath, referenceHash, contentHash].some(value => value !== undefined) && (!recoveryPath || !project || provider !== 'bubble'
    || !referenceHash || !digest.test(referenceHash) || !contentHash || !digest.test(contentHash)
    || after || values.all || concurrency !== 1)) throw new Error('INVALID_RECOVERY');

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
  async function copy({ reference, reference_sha256 }: Candidate, recovered?: { bytes: Buffer; confirmed: boolean }): Promise<number | Failure> {
    let stage = 'source';
    try {
      let bytes = recovered?.bytes;
      if (!bytes) {
        const source = await resolveWorkshopMedia(reference, origin, 'document', sign)
          ?? await resolveWorkshopMedia(reference, origin, 'project_photo', sign)
          ?? await resolveWorkshopMedia(reference, origin, 'answer_signature', sign);
        if (!source) throw new Error('SOURCE_UNAVAILABLE');
        bytes = await retry(() => bytesFrom(source));
      }
      const original = bytes;
      stage = 'format';
      const { mime, suffix } = contentType(bytes), sha = hash(bytes);
      const path = `acervo-oficina/${workshop}/${reference_sha256}.${suffix}`;
      stage = 'copy';
      // The name is deterministic. A retry can verify a copy already present without replacing it.
      if (!recovered?.confirmed) await retry(async () => {
        const { error } = await database.storage.from(bucket).upload(path, original, { upsert: false, contentType: mime, metadata: { sha256: sha } });
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
      if (!recovered?.confirmed) await retry(async () => {
        const confirmation = await database.rpc('rm_confirm_workshop_archive_v1', {
          p_workshop: workshop, p_reference: reference, p_content_sha256: sha, p_mime: mime, p_size: original.length,
        }).abortSignal(AbortSignal.timeout(30_000));
        if (confirmation.error || confirmation.data !== path) throw new ArchiveError('CONFIRMATION_FAILED', retryableStatus(confirmation.status));
      });
      return bytes.length;
    } catch (error) {
      const reason = error instanceof ArchiveError ? error.reason : stage === 'format' ? 'UNSUPPORTED_FORMAT' : 'TRANSFER_FAILED';
      return { reference_sha256, stage, reason };
    }
  }

  if (recoveryPath && referenceHash && contentHash) {
    const bytes = await readRecoveryPng(recoveryPath, contentHash);
    const target = await retry(async () => {
      const response = await database.rpc('rm_workshop_archive_recovery_target_v1', {
        p_workshop: workshop, p_project: project, p_reference_sha256: referenceHash,
      }).abortSignal(AbortSignal.timeout(30_000));
      if (response.error) throw new ArchiveError('RECOVERY_TARGET_UNAVAILABLE', retryableStatus(response.status));
      return response.data;
    });
    if (typeof target?.reference !== 'string' || target.reference_sha256 !== referenceHash || hash(target.reference) !== referenceHash
      || !Object.hasOwn(target, 'existing')) throw new ArchiveError('RECOVERY_TARGET_UNAVAILABLE');
    const confirmed = target.existing !== null;
    if (confirmed && (target.existing?.sha256 !== contentHash || target.existing?.size !== bytes.length
      || target.existing?.mime !== 'image/png' || target.existing?.path !== `acervo-oficina/${workshop}/${referenceHash}.png`)) {
      throw new ArchiveError('ARCHIVE_RECEIPT_MISMATCH');
    }
    const result = values.apply ? await copy(target, { bytes, confirmed }) : null;
    console.log(JSON.stringify({ reference_sha256: referenceHash, content_sha256: contentHash, bytes: bytes.length,
      status: result === null ? (confirmed ? 'already_confirmed' : 'ready') : typeof result === 'number' ? 'verified' : 'failed',
      ...(result && typeof result !== 'number' && { failure: result }) }));
    if (result && typeof result !== 'number') process.exitCode = 1;
    return;
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

main().catch(error => {
  if (error instanceof ArchiveError) console.error(JSON.stringify({ status: 'failed', reason: error.reason }));
  else console.error('Não foi possível executar o lote do acervo. Confira destino, configuração e argumentos.');
  process.exitCode = 1;
});
