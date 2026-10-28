import type { Answer, Row } from './types';

export async function uploadThenMutate(upload: () => Promise<void>, mutate: () => Promise<void>): Promise<void> {
  await upload();
  await mutate();
}
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(v => canonicalJson(v === undefined ? null : v)).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.entries(value).filter(([,v]) => v !== undefined).sort(([a],[b]) => a.localeCompare(b)).map(([k,v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(',')}}`;
  return JSON.stringify(value);
}
/** A rejected credential must never be accepted through the offline cache fallback. */
export function isConnectivityError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const value = error as {code?: string; status?: number; message?: string};
  if (value.code || value.status === 401 || value.status === 403) return false;
  return /network request failed|failed to fetch|fetch failed|networkerror|network error|timed?\s?out|connection (reset|refused)/i.test(value.message ?? '');
}

export function retryDelay(attempts: number, random = Math.random): number {
  return Math.min(300_000, 1_000 * 2 ** Math.min(Math.max(attempts - 1, 0), 8))
    + Math.floor(random() * 1_000);
}
export function isLocalUri(value: string): boolean {
  return /^(file|content|data):/.test(value);
}
/** Recursively resolve whole values, never partial strings. Missing uploads block RPCs. */
export function replaceMedia<T>(value: T, uploaded: ReadonlyMap<string, string>): T {
  if (typeof value === 'string' && isLocalUri(value)) {
    const url = uploaded.get(value);
    if (!url) throw new Error('Uma mídia ainda não foi enviada. A operação foi preservada na fila.');
    return url as T;
  }
  if (Array.isArray(value)) return value.map(v => replaceMedia(v, uploaded)) as T;
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, replaceMedia(v, uploaded)])) as T;
  }
  return value;
}
export function validateAnswers(questions: Row[], answers: Answer[]): string[] {
  return questions.filter(q => q.obrigatorio && q.tipo !== 'subt_tulo').flatMap(q => {
    const a = answers.find(item => item.questao_id === q.id);
    if (a?.is_na) return [];
    let valid = !!a;
    if (a) {
      switch (q.tipo) {
        case 'foto': valid = !!a.fotos_urls?.length; break;
        case 'foto_antes_depois': valid = a.fotos_urls?.length === 2 && a.fotos_urls.every(Boolean); break;
        case 'assinatura': valid = !!a.assinatura_url; break;
        case 'data': valid = !!a.date_inicio && (q.subtipo !== 'intervalo_de_datas' || !!a.data_fim); break;
        case 'hora': valid = !!a.hora; break;
        case 'caixas_de_sele__o':
        case 'lista_multi_sele__o': valid = !!a.itens?.length; break;
        case 'numero': valid = a.resposta != null && a.resposta.trim() !== '' && Number.isFinite(Number(a.resposta.replace(',', '.'))); break;
        default: valid = !!a.resposta?.trim() || !!a.itens?.length;
      }
      if (valid && q.tipo === 'data' && a.data_fim && a.date_inicio) valid = a.data_fim >= a.date_inicio;
    }
    return valid ? [] : [String(q.enunciado)];
  });
}
/** Data APIs expect raw bytes. React Native Blob/FormData are not reliable for Storage. */
export function decodeBase64(encoded: string): Uint8Array {
  const clean = encoded.replace(/\s/g, '');
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const payloadLength = clean.indexOf('=') < 0 ? clean.length : clean.indexOf('=');
  const bytes = new Uint8Array(Math.floor(payloadLength * 6 / 8));
  let accumulator = 0, bits = 0, position = 0;
  for (const ch of clean) {
    if (ch === '=') break;
    const index = alphabet.indexOf(ch);
    if (index < 0) throw new Error('Mídia Base64 inválida.');
    accumulator = (accumulator << 6) | index;
    bits += 6;
    if (bits >= 8) { bits -= 8; bytes[position++] = (accumulator >> bits) & 255; }
  }
  return bytes;
}
