import { timingSafeEqual } from 'node:crypto';

export function matchesBearer(header: string | null, expected: string | undefined): boolean {
  if (!expected || expected.length < 32 || !header?.startsWith('Bearer ')) return false;
  const supplied = Buffer.from(header.slice(7));
  const secret = Buffer.from(expected);
  return supplied.length === secret.length && timingSafeEqual(supplied, secret);
}
export function authorized(request: Request, envName = 'INTERNAL_API_SECRET') {
  return matchesBearer(request.headers.get('authorization'), process.env[envName]);
}
export async function readJson(request: Request, limit = 1024 * 1024): Promise<unknown> {
  if (!request.headers.get('content-type')?.includes('application/json')) throw new Error('Content-Type application/json obrigatório.');
  if (Number(request.headers.get('content-length')) > limit) throw new Error('Payload excede o limite.');
  const reader = request.body?.getReader();
  if (!reader) throw new Error('Body obrigatório.');
  const chunks: Uint8Array[] = []; let length = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    length += value.length;
    if (length > limit) { await reader.cancel(); throw new Error('Payload excede o limite.'); }
    chunks.push(value);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
}
export function allowedWebhook(url: string, allowlist: string[]): boolean {
  try { const parsed = new URL(url); return parsed.protocol === 'https:' && !parsed.username && !parsed.password && allowlist.includes(parsed.toString()); }
  catch { return false; }
}
