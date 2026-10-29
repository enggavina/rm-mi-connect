import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const MAX_ENVELOPE = 60_000;
export type SsoPurpose = 'flow' | 'session';
function encryptionKey(value = process.env.EM_SSO_ENCRYPTION_KEY): Buffer {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_+\/-]{43}=?$/.test(value)) throw new Error('Configuração de sessão corporativa indisponível.');
  const key = Buffer.from(value, 'base64url');
  if (key.length !== 32) throw new Error('Configuração de sessão corporativa indisponível.');
  return key;
}
export const opaqueToken = () => randomBytes(32).toString('base64url');
export function tokenHash(value: string): string {
  if (!TOKEN.test(value)) throw new Error('Sessão corporativa inválida.');
  return createHash('sha256').update(value).digest('hex');
}
export function sealSso(value: unknown, purpose: SsoPurpose, keyValue?: string): string {
  const text = JSON.stringify(value);
  if (!text || Buffer.byteLength(text) > 40_000) throw new Error('Sessão corporativa inválida.');
  const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', encryptionKey(keyValue), iv);
  cipher.setAAD(Buffer.from(`em-sso:v1:${purpose}`));
  const encrypted = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), encrypted.toString('base64url')].join('.');
}
export function openSso(value: string, purpose: SsoPurpose, keyValue?: string): unknown {
  try {
    if (typeof value !== 'string' || value.length > MAX_ENVELOPE) throw new Error();
    const parts = value.split('.');
    if (parts.length !== 4 || parts[0] !== 'v1' || parts.slice(1).some(part => !/^[A-Za-z0-9_-]+$/.test(part))) throw new Error();
    const iv = Buffer.from(parts[1], 'base64url'), tag = Buffer.from(parts[2], 'base64url');
    if (iv.length !== 12 || tag.length !== 16) throw new Error();
    const decipher = createDecipheriv('aes-256-gcm', encryptionKey(keyValue), iv);
    decipher.setAAD(Buffer.from(`em-sso:v1:${purpose}`)); decipher.setAuthTag(tag);
    return JSON.parse(Buffer.concat([decipher.update(Buffer.from(parts[3], 'base64url')), decipher.final()]).toString('utf8')) as unknown;
  } catch { throw new Error('Não foi possível confirmar a sessão corporativa. Entre novamente.'); }
}
