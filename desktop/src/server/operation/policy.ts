import { z } from 'zod';
import { openSso, sealSso, type SsoPurpose } from '../web/sso-crypto';
import { EM_IDENTITY_ISSUER } from '../web/workshop-context';

export const OPERATION_COOKIE = 'em-operation-session';
export const OPERATION_DEVICE_COOKIE = 'em-operation-device';
export const OPERATION_PATH = '/operacao';
export const OPERATION_LOGIN_PATH = '/operacao/login';
const MAX_COOKIE_BYTES = 3_800;
const MAX_REQUEST_BYTES = 8_192;
const id = z.string().uuid();
const token = z.string().max(2_800).regex(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
export const operatorToken = z.string().regex(/^[0-9a-f]{64}$/);
const receivingResult = z.object({
  projeto_id: id, equipamento_id: id, receiving_id: id.optional(), attachments_pending: z.boolean().optional(),
  confirmacao: z.object({ protocolo: id, oficina_id: id, fase: z.enum(['open', 'complete']), projeto_id: id, equipamento_id: id }).strict(),
});
const mutationResult = z.object({
  projeto_id: id.optional(), confirmacao: z.object({ protocolo: id, operacao: z.string(), dispositivo_id: id,
    operador_id: id, oficina_id: id, projeto_id: id }).strict(),
});
const expiry = z.number().int().positive();
const deviceSession = z.object({ token, expiresAt: expiry }).strict();
const session = deviceSession.extend({ operatorToken });
export type OperationSession = z.infer<typeof session>;
const claimsSchema = z.object({
  iss: z.literal(EM_IDENTITY_ISSUER), sub: id, session_id: id, exp: expiry,
  aud: z.literal('authenticated'), role: z.literal('authenticated'), aal: z.string().optional(),
});

export function operationCookieOptions(maxAge: number, path = OPERATION_PATH) {
  return { path, maxAge, httpOnly: true, sameSite: 'lax' as const, secure: process.env.NODE_ENV === 'production' };
}

export function confirmsReceivingResult(value: unknown, submission: string, phase: 'open' | 'complete', workshop: string) {
  const parsed = receivingResult.safeParse(value);
  if (!parsed.success) return false;
  const receipt = parsed.data;
  const confirmation = receipt.confirmacao;
  return confirmation.protocolo === submission.toLowerCase() && confirmation.oficina_id === workshop.toLowerCase()
    && confirmation.fase === phase && confirmation.projeto_id === receipt.projeto_id && confirmation.equipamento_id === receipt.equipamento_id
    && (phase === 'open' ? receipt.receiving_id === confirmation.protocolo : receipt.attachments_pending !== true);
}

export function confirmsMutationResult(value: unknown, expected: { submission: string; operation: string;
  device: string; operator?: string; workshop: string }) {
  const parsed = mutationResult.safeParse(value);
  if (!parsed.success) return false;
  const { confirmacao, projeto_id } = parsed.data;
  return confirmacao.protocolo === expected.submission.toLowerCase() && confirmacao.operacao === expected.operation
    && confirmacao.oficina_id === expected.workshop && confirmacao.dispositivo_id === expected.device
    && confirmacao.operador_id === expected.operator && (projeto_id === undefined || confirmacao.projeto_id === projeto_id);
}

function sealCookie(value: unknown, purpose: SsoPurpose, key?: string) {
  const envelope = sealSso(value, purpose, key);
  if (Buffer.byteLength(envelope) > MAX_COOKIE_BYTES) throw new Error('Sessão excede o limite do navegador.');
  return envelope;
}

function openCookie<T extends { expiresAt: number }>(value: unknown, schema: z.ZodType<T>, purpose: SsoPurpose, now: number, key?: string): T | null {
  if (typeof value !== 'string' || Buffer.byteLength(value) > MAX_COOKIE_BYTES) return null;
  try {
    const result = schema.safeParse(openSso(value, purpose, key));
    return result.success && result.data.expiresAt > now ? result.data : null;
  } catch { return null; }
}

export function sealOperationSession(value: OperationSession, key?: string) {
  return sealCookie(session.parse(value), 'operation', key);
}

export function openOperationSession(value: unknown, now = Date.now(), key?: string) {
  return openCookie(value, session, 'operation', now, key);
}

export function sealDeviceLogin(value: z.infer<typeof deviceSession>, key?: string) {
  return sealCookie(deviceSession.parse(value), 'operation-device', key);
}

export function openDeviceLogin(value: unknown, now = Date.now(), key?: string) {
  return openCookie(value, deviceSession, 'operation-device', now, key);
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

const deviceCredentials = z.object({
  email: z.string().trim().max(254).email(), password: z.string().min(1).max(1024),
}).strict();
const operatorCredentials = z.object({
  matricula: z.string().trim().min(1).max(80), palavra_chave: z.string().min(1).max(256),
}).strict();
const credentials = deviceCredentials.extend(operatorCredentials.shape);
export type DeviceCredentials = z.infer<typeof deviceCredentials>;
export type OperatorCredentials = z.infer<typeof operatorCredentials>;
export type OperationCredentials = z.infer<typeof credentials>;

export async function readOperationText(request: Request, type: RegExp, maxBytes: number): Promise<string | null> {
  const length = request.headers.get('content-length');
  if (!type.test(request.headers.get('content-type') ?? '') || !request.body
    || length !== null && (!/^\d+$/.test(length) || Number(length) > maxBytes)) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      size += result.value.byteLength;
      if (size > maxBytes) return null;
      chunks.push(result.value);
    }
    return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
  } catch { return null; }
  finally { void reader.cancel().catch(() => {}); reader.releaseLock(); }
}

async function readCredentials<T>(request: Request, schema: z.ZodType<T>): Promise<T | null> {
  const body = await readOperationText(request, /^application\/x-www-form-urlencoded(?:\s*;|$)/i, MAX_REQUEST_BYTES);
  if (body === null) return null;
  const params = new URLSearchParams(body);
  const fields = [...params.keys()];
  if (new Set(fields).size !== fields.length) return null;
  const result = schema.safeParse(Object.fromEntries(params));
  return result.success ? result.data : null;
}

export function readOperationCredentials(request: Request) {
  return readCredentials(request, z.union([deviceCredentials, credentials]));
}

export function readOperatorCredentials(request: Request) {
  return readCredentials(request, operatorCredentials);
}

const cell = z.object({ id, nome: z.string() }).strict();
const project = z.object({
  id, numero: z.string().nullable(), nome: z.string().nullable(), cliente: z.string().nullable(),
  descricao: z.string().nullable(), status: z.string().nullable(),
}).strict();
const form = z.object({ id, titulo: z.string().nullable() }).strict();
export const formVersion = z.string().regex(/^[0-9a-f]{64}$/);
const question = z.object({
  id, indice: z.string(), enunciado: z.string(), subtitulo: z.string().nullable(),
  tipo: z.string(), obrigatorio: z.boolean(),
  items: z.array(z.object({ id, descricao: z.string() }).strict()),
}).strict();
const dataSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('cells'), items: z.array(cell) }).strict(),
  z.object({ kind: z.literal('projects'), cell, items: z.array(project).max(25), page: z.number().int().positive(),
    total: z.number().int().nonnegative(), page_size: z.literal(25) }).strict(),
  z.object({ kind: z.literal('project'), cell, project, forms: z.array(form) }).strict(),
  z.object({ kind: z.literal('form'), cell, project, form: form.extend({ descricao: z.string().nullable() }),
    questions: z.array(question), edition: z.object({ version: formVersion, dateIntervals: z.array(id) }).strict().optional() }).strict(),
]);
export type OperationData = z.infer<typeof dataSchema>;
export type OperationSelection = { cellId?: string; projectId?: string; formId?: string; page?: string | number };
export type OperationQuery =
  | { cellId: string | null; projectId: string | null; formId: null; page: number }
  | { cellId: string; projectId: string; formId: string; page: 1 };

export function operationQuery(input: OperationSelection): OperationQuery | null {
  const { cellId, projectId, formId, page } = input;
  if (cellId != null && !id.safeParse(cellId).success || projectId != null && !id.safeParse(projectId).success
      || projectId != null && cellId == null) return null;
  const currentPage = page == null ? 1 : typeof page === 'string' && /^\d{1,5}$/.test(page) ? Number(page) : page;
  if (typeof currentPage !== 'number' || !Number.isInteger(currentPage) || currentPage < 1 || currentPage > 10_000) return null;
  if (formId != null) {
    if (!cellId || !projectId || currentPage !== 1 || !id.safeParse(formId).success) return null;
    return { cellId: cellId.toLowerCase(), projectId: projectId.toLowerCase(), formId: formId.toLowerCase(), page: 1 };
  }
  return { cellId: cellId?.toLowerCase() ?? null, projectId: projectId?.toLowerCase() ?? null, formId: null, page: currentPage };
}

export function operationData(value: unknown, query: OperationQuery): OperationData | null {
  if (value === null) return null;
  const result = dataSchema.parse(value);
  const items = result.kind === 'form' ? result.questions : result.kind === 'project' ? result.forms : result.items;
  const expected = query.formId ? 'form' : query.projectId ? 'project' : query.cellId ? 'projects' : 'cells';
  if (expected !== result.kind || new Set(items.map(item => item.id)).size !== items.length
    || result.kind !== 'cells' && result.cell.id !== query.cellId
    || (result.kind === 'project' || result.kind === 'form') && result.project.id !== query.projectId
    || result.kind === 'form' && result.form.id !== query.formId
    || result.kind === 'projects' && (result.page !== query.page || result.items.length > result.total)) {
    throw new Error('Projeção operacional divergente.');
  }
  return result;
}
