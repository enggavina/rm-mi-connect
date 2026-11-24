import { z } from 'zod';
import { openSso, sealSso } from '../web/sso-crypto';
import { EM_IDENTITY_ISSUER } from '../web/workshop-context';

export const OPERATION_COOKIE = 'em-operation-session';
export const OPERATION_PATH = '/operacao';
const MAX_COOKIE_BYTES = 3_800;
const MAX_REQUEST_BYTES = 8_192;
const id = z.string().uuid();
const token = z.string().max(2_800).regex(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
export const operatorToken = z.string().regex(/^[0-9a-f]{64}$/);
const expiry = z.number().int().positive();
const session = z.object({ token, operatorToken, expiresAt: expiry }).strict();
export type OperationSession = z.infer<typeof session>;
const claimsSchema = z.object({
  iss: z.literal(EM_IDENTITY_ISSUER), sub: id, session_id: id, exp: expiry,
  aud: z.literal('authenticated'), role: z.literal('authenticated'), aal: z.string().optional(),
});

export function operationCookieOptions(maxAge: number) {
  return { path: OPERATION_PATH, maxAge, httpOnly: true, sameSite: 'lax' as const, secure: process.env.NODE_ENV === 'production' };
}

export function sealOperationSession(value: OperationSession, key?: string): string {
  const envelope = sealSso(session.parse(value), 'operation', key);
  if (Buffer.byteLength(envelope) > MAX_COOKIE_BYTES) throw new Error('Sessão excede o limite do navegador.');
  return envelope;
}

export function openOperationSession(value: unknown, now = Date.now(), key?: string): OperationSession | null {
  if (typeof value !== 'string' || Buffer.byteLength(value) > MAX_COOKIE_BYTES) return null;
  try {
    const result = session.safeParse(openSso(value, 'operation', key));
    return result.success && result.data.expiresAt > now ? result.data : null;
  } catch { return null; }
}

/** Call only after Supabase Auth has verified this exact JWT. */
export function operationClaims(value: string, userId: string, now = Date.now()) {
  const checked = token.safeParse(value);
  if (!checked.success) return null;
  try {
    const result = claimsSchema.safeParse(JSON.parse(Buffer.from(value.split('.')[1], 'base64url').toString('utf8')));
    if (!result.success || result.data.sub !== userId || result.data.exp * 1000 <= now) return null;
    return { authUserId: result.data.sub, sessionId: result.data.session_id, expiresAt: result.data.exp * 1000, aal: result.data.aal };
  } catch { return null; }
}

const credentials = z.object({
  email: z.string().trim().max(254).email(), password: z.string().min(1).max(1024),
  matricula: z.string().trim().min(1).max(80), palavra_chave: z.string().min(1).max(256),
}).strict();
export type OperationCredentials = z.infer<typeof credentials>;

export async function readOperationCredentials(request: Request): Promise<OperationCredentials | null> {
  const length = request.headers.get('content-length');
  if (!/^application\/x-www-form-urlencoded(?:\s*;|$)/i.test(request.headers.get('content-type') ?? '')
    || !request.body || length !== null && (!/^\d+$/.test(length) || Number(length) > MAX_REQUEST_BYTES)) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      size += result.value.byteLength;
      if (size > MAX_REQUEST_BYTES) return null;
      chunks.push(result.value);
    }
    const params = new URLSearchParams(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
    const fields = [...params.keys()];
    if (fields.length !== 4 || new Set(fields).size !== 4) return null;
    const result = credentials.safeParse(Object.fromEntries(params));
    return result.success ? result.data : null;
  } catch { return null; }
  finally { void reader.cancel().catch(() => {}); reader.releaseLock(); }
}

const cell = z.object({ id, nome: z.string() }).strict();
const project = z.object({
  id, numero: z.string().nullable(), nome: z.string().nullable(), cliente: z.string().nullable(),
  descricao: z.string().nullable(), status: z.string().nullable(),
}).strict();
const form = z.object({ id, titulo: z.string().nullable() }).strict();
const dataSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('cells'), items: z.array(cell) }).strict(),
  z.object({ kind: z.literal('projects'), cell, items: z.array(project).max(25), page: z.number().int().positive(),
    total: z.number().int().nonnegative(), page_size: z.literal(25) }).strict(),
  z.object({ kind: z.literal('project'), cell, project, forms: z.array(form) }).strict(),
]);
export type OperationData = z.infer<typeof dataSchema>;
export type OperationSelection = { cellId?: string; projectId?: string; page?: string | number };
export type OperationQuery = { cellId: string | null; projectId: string | null; page: number };

export function operationQuery(input: OperationSelection): OperationQuery | null {
  const { cellId, projectId, page } = input;
  if (cellId != null && !id.safeParse(cellId).success || projectId != null && !id.safeParse(projectId).success
      || projectId != null && cellId == null) return null;
  const currentPage = page == null ? 1 : typeof page === 'string' && /^\d{1,5}$/.test(page) ? Number(page) : page;
  if (typeof currentPage !== 'number' || !Number.isInteger(currentPage) || currentPage < 1 || currentPage > 10_000) return null;
  return { cellId: cellId?.toLowerCase() ?? null, projectId: projectId?.toLowerCase() ?? null, page: currentPage };
}

export function operationData(value: unknown, query: OperationQuery): OperationData | null {
  if (value === null) return null;
  const result = dataSchema.parse(value);
  const items = result.kind === 'project' ? result.forms : result.items;
  const expected = query.projectId ? 'project' : query.cellId ? 'projects' : 'cells';
  if (expected !== result.kind || new Set(items.map(item => item.id)).size !== items.length
    || result.kind !== 'cells' && result.cell.id !== query.cellId
    || result.kind === 'project' && result.project.id !== query.projectId
    || result.kind === 'projects' && (result.page !== query.page || result.items.length > result.total)) {
    throw new Error('Projeção operacional divergente.');
  }
  return result;
}
