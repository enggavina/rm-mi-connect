import type { Bucket, OutboxRow } from './types';

const destination = 'https://em-web-production.up.railway.app/api/mobile/midia/envio';
const MIME_EXTENSIONS = { 'image/jpeg': 'jpg', 'image/png': 'png', 'application/pdf': 'pdf' } as const;
type Mime = keyof typeof MIME_EXTENSIONS;
type UploadOperation = 'rm_submit_recebimento_v1' | 'rm_record_cell_photo_v1' | 'rm_submit_form_inspection_v1' | 'rm_submit_form_revision_v1';
export type MediaIntent = { row: OutboxRow; operation: UploadOperation; payload: Record<string, unknown>; kind: 'photo' | 'signature' | 'document' };

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

export function queuedMediaIntents(queue: readonly OutboxRow[]): Map<string, MediaIntent> {
  const files = new Map<string, MediaIntent>();
  for (const row of queue) {
    const operation = row.rpc_name;
    if (operation !== 'rm_submit_recebimento_v1' && operation !== 'rm_record_cell_photo_v1'
      && operation !== 'rm_submit_form_inspection_v1' && operation !== 'rm_submit_form_revision_v1') continue;
    let payload: Record<string, unknown>;
    try { payload = record(JSON.parse(row.params_json)); } catch { continue; }
    const add = (reference: unknown, kind: MediaIntent['kind']) => {
      if (typeof reference === 'string' && reference.startsWith('file:///') && !files.has(reference)) {
        files.set(reference, { row, operation, payload, kind });
      }
    };
    if (operation === 'rm_submit_recebimento_v1') {
      add(payload.p_arquivo_nota_fiscal_url, 'document');
      if (Array.isArray(payload.p_fotos_recebimento)) for (const photo of payload.p_fotos_recebimento) add(record(photo).foto_url, 'photo');
    } else if (operation === 'rm_record_cell_photo_v1') {
      add(payload.p_foto_url, 'photo');
    } else {
      const answers = operation === 'rm_submit_form_revision_v1' ? payload.p_respostas_corrigidas : payload.p_respostas;
      if (Array.isArray(answers)) for (const raw of answers) {
        const answer = record(raw);
        add(answer.assinatura_url, 'signature');
        if (Array.isArray(answer.fotos_urls)) for (const photo of answer.fotos_urls) add(photo, 'photo');
      }
    }
  }
  return files;
}

export function mediaUploadMime(bucket: Bucket, mime?: string | null): Mime {
  const value = mime || (bucket === 'rm-assinaturas' ? 'image/png' : 'image/jpeg');
  if (!Object.hasOwn(MIME_EXTENSIONS, value)) throw new Error('Tipo de arquivo indisponível para o envio.');
  return value as Mime;
}

export async function sendWorkshopMediaUpload(input: { deviceToken: string; operatorToken: string; workshopOrigin: string;
  submission: string; operation: UploadOperation; payload: Record<string, unknown>; asset: string; kind: MediaIntent['kind'];
  reference: string; mime: Mime; size: number; sha256: string }, file: Blob, storageOrigin: string, request = fetch): Promise<string> {
  const { deviceToken, operatorToken, ...metadata } = input;
  const body = new FormData();
  body.append('input', JSON.stringify(metadata));
  body.append('file', file);
  const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 120_000);
  try {
    const response = await request(destination, { method: 'POST', redirect: 'error', signal: controller.signal,
      headers: { Authorization: `Bearer ${deviceToken}`, 'X-EM-Operator': operatorToken }, body });
    const saved = await response.json().catch(() => null);
    const path = `mobile-oficina/${input.workshopOrigin}/${input.submission}/${input.asset}.${MIME_EXTENSIONS[input.mime]}`;
    const url = `${storageOrigin}/storage/v1/object/authenticated/rm-documentos/${path}`;
    if (!response.ok || saved?.stored !== true || saved.asset_id !== input.asset || saved.workshop_id !== input.workshopOrigin
      || saved.submission_id !== input.submission || saved.path !== path || saved.url !== url) {
      throw new Error('O arquivo continua salvo e aguarda confirmação da oficina para envio.');
    }
    return url;
  } finally { clearTimeout(timeout); }
}
