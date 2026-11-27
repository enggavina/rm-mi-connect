/** Run with desktop's tsx from the repository root. A Storage object ID is required. */
import { createHash } from 'node:crypto';
import { parseArgs } from 'node:util';
import { adminClient, required } from '../../desktop/src/server/config';

const origin = 'https://ellpxfbsrbhblyizvbbk.supabase.co';
const destination = 'rm-documentos';
const original = 'rm-fotos';
const objectIdPattern = '[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}';
const originalPath = new RegExp(`^${objectIdPattern}/[a-z0-9_-]+\\.(?:jpe?g|png|webp)$`, 'i');
const digest = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
const suffixes = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' } as const;
class RecoveryError extends Error {}

function detectedMime(bytes: Buffer) {
  if (bytes.subarray(0, 3).toString('hex') === 'ffd8ff') return 'image/jpeg';
  if (bytes.subarray(0, 8).toString('hex') === '89504e470d0a1a0a') return 'image/png';
  if (bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP') return 'image/webp';
}

async function main() {
  const { values } = parseArgs({ options: { object: { type: 'string' }, apply: { type: 'boolean' } } });
  const object = values.object;
  if (!object || !new RegExp(`^${objectIdPattern}$`).test(object)) throw new RecoveryError('Objeto inválido.');
  process.loadEnvFile('desktop/.env');
  if (required('SUPABASE_URL') !== origin) throw new RecoveryError('Destino inválido.');
  const db = adminClient();
  const resolveTarget = await db.rpc('rm_workshop_legacy_photo_recovery_target_v1', { p_object: object })
    .abortSignal(AbortSignal.timeout(30_000));
  const target = resolveTarget.data;
  if (resolveTarget.error || !target || typeof target.path !== 'string' || !originalPath.test(target.path)
    || typeof target.version !== 'string' || !target.version
    || !Number.isInteger(target.size) || target.size < 1 || target.size > 15 * 1024 * 1024) {
    throw new RecoveryError('Origem sem comprovação para recuperação.');
  }

  async function download(bucket: string, path: string) {
    const { data } = await db.storage.from(bucket).createSignedUrl(path, 60);
    const url = data?.signedUrl && new URL(data.signedUrl);
    if (!url || url.origin !== origin || url.pathname !== `/storage/v1/object/sign/${bucket}/${path}`) {
      throw new RecoveryError('Endereço de verificação inválido.');
    }
    const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(45_000) });
    const reader = response.body?.getReader();
    if (!response.ok || !reader) throw new RecoveryError('Não foi possível ler os bytes para conferência.');
    const bytes = Buffer.alloc(target.size);
    let offset = 0;
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        if (offset + value.length > bytes.length) throw new RecoveryError('Tamanho dos bytes divergente.');
        bytes.set(value, offset);
        offset += value.length;
      }
      if (offset !== bytes.length) throw new RecoveryError('Tamanho dos bytes divergente.');
      return bytes;
    } finally {
      await reader.cancel().catch(() => undefined);
    }
  }

  const bytes = await download(original, target.path);
  const mime = detectedMime(bytes);
  if (!mime || mime !== target.mime) throw new RecoveryError('Tipo do arquivo divergente.');
  if (!values.apply) {
    console.log(JSON.stringify({ eligible: true, bytes: bytes.length, mime }));
    return;
  }
  const { data: bucket } = await db.storage.getBucket(destination);
  if (bucket?.public !== false) throw new RecoveryError('Destino de recuperação indisponível.');
  const sha = digest(bytes);
  const path = `recuperacao-fotos-legadas/${object}/${sha}.${suffixes[mime]}`;
  const { error } = await db.storage.from(destination).upload(path, bytes, {
    upsert: false, contentType: mime, metadata: { sha256: sha },
  });
  if (error && !/already exists|alreadyexists|duplicate/i.test(error.message)) throw new RecoveryError('A cópia privada não foi armazenada.');
  const [verifiedCopy, currentSource] = await Promise.all([download(destination, path), download(original, target.path)]);
  if (digest(verifiedCopy) !== sha || digest(currentSource) !== sha) throw new RecoveryError('A conferência de integridade encontrou divergência.');

  const receipt = await db.rpc('rm_confirm_workshop_legacy_photo_recovery_v1', {
    p_object: object, p_source_version: target.version, p_content_sha256: sha,
  }).abortSignal(AbortSignal.timeout(30_000));
  if (receipt.error || receipt.data !== path) throw new RecoveryError('O comprovante da versão não foi confirmado.');
  console.log(JSON.stringify({ verified: true, bytes: bytes.length, mime }));
}

main().catch((error: unknown) => {
  // The origin and signed download tokens must stay out of the logs.
  console.error(error instanceof RecoveryError ? error.message : 'Não foi possível preservar a foto legada.');
  process.exitCode = 1;
});
