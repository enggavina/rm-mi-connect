import * as SecureStore from 'expo-secure-store';
import * as Crypto from 'expo-crypto';
import { pbkdf2Async } from '@noble/hashes/pbkdf2';
import { sha256 } from '@noble/hashes/sha256';
import { bytesToHex, utf8ToBytes } from '@noble/hashes/utils';
import type { Operator } from './types';

const OPTIONS = { keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY };
/** Chunk JWT sessions because some native Keychains reject values over 2 KB. */
export const secureStorage = {
  async getItem(key: string): Promise<string | null> {
    const count = Number(await SecureStore.getItemAsync(`${key}.count`, OPTIONS));
    if (!count) return null;
    const chunks = await Promise.all(Array.from({length: count}, (_, i) => SecureStore.getItemAsync(`${key}.${i}`, OPTIONS)));
    return chunks.some(v => v === null) ? null : chunks.join('');
  },
  async setItem(key: string, value: string) {
    const oldCount = Number(await SecureStore.getItemAsync(`${key}.count`, OPTIONS));
    const chunks = value.match(/[\s\S]{1,1800}/g) ?? [''];
    for (let i = 0; i < chunks.length; i++) await SecureStore.setItemAsync(`${key}.${i}`, chunks[i], OPTIONS);
    await SecureStore.setItemAsync(`${key}.count`, String(chunks.length), OPTIONS);
    for (let i = chunks.length; i < oldCount; i++) await SecureStore.deleteItemAsync(`${key}.${i}`, OPTIONS);
  },
  async removeItem(key: string) {
    const count = Number(await SecureStore.getItemAsync(`${key}.count`, OPTIONS));
    await SecureStore.deleteItemAsync(`${key}.count`, OPTIONS);
    for (let i = 0; i < count; i++) await SecureStore.deleteItemAsync(`${key}.${i}`, OPTIONS);
  },
};
interface CachedIdentity { operator: Operator; token: string; salt: string; hash: string; expires: number; attempts: number; blockedUntil: number; owner: string; }
async function identityKey(matricula: string) {
  const digest = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, matricula.trim().toLowerCase());
  return `rm.identity.${digest}`;
}
async function derive(password: string, salt: string) {
  return bytesToHex(await pbkdf2Async(sha256, utf8ToBytes(password), utf8ToBytes(salt), { c: 210_000, dkLen: 32, asyncTick: 10 }));
}
export async function cacheIdentity(operator: Operator, token: string, password: string, owner: string) {
  const salt = bytesToHex(await Crypto.getRandomBytesAsync(32));
  const entry: CachedIdentity = {
    operator, token, salt, hash: await derive(password, salt), owner,
    expires: Math.min(Date.now() + 86_400_000, Date.parse(operator.token_expires_at ?? '') || Date.now()),
    attempts: 0, blockedUntil: 0,
  };
  await secureStorage.setItem(await identityKey(operator.matricula), JSON.stringify(entry));
}
export async function offlineIdentity(matricula: string, password: string, owner: string): Promise<{operator: Operator; token: string}> {
  const key = await identityKey(matricula), raw = await secureStorage.getItem(key);
  if (!raw) throw new Error('Primeira identificação deste operador exige conexão.');
  const entry = JSON.parse(raw) as CachedIdentity;
  if (entry.owner !== owner || entry.expires < Date.now()) throw new Error('Identificação offline expirada. Conecte e identifique-se novamente.');
  if (entry.blockedUntil > Date.now()) throw new Error('Identificação temporariamente bloqueada. Aguarde 15 minutos ou conecte para validar.');
  const hash = await derive(password, entry.salt);
  let mismatch = hash.length ^ entry.hash.length;
  for (let i = 0; i < hash.length; i++) mismatch |= hash.charCodeAt(i) ^ entry.hash.charCodeAt(i);
  if (mismatch) {
    entry.attempts++;
    if (entry.attempts >= 5) { entry.blockedUntil = Date.now() + 900_000; entry.attempts = 0; }
    await secureStorage.setItem(key, JSON.stringify(entry));
    throw new Error('Matrícula ou palavra-chave inválida.');
  }
  entry.attempts = 0;
  await secureStorage.setItem(key, JSON.stringify(entry));
  return { operator: entry.operator, token: entry.token };
}
