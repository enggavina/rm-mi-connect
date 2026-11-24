import { z } from 'zod';
import { CORPORATE_ISSUER, validateCorporateDecision, type VerifiedCorporateSession } from './sso-policy';

export const WORKSHOP_CONTEXT_URL = 'https://acessos.miconnect.app.br/authorization/v2/me/em/workshop-context';
export const MOBILE_WORKSHOP_CONTEXT_URL = 'https://acessos.miconnect.app.br/authorization/v2/services/em/workshop-context';
export const EM_IDENTITY_ISSUER = 'https://ellpxfbsrbhblyizvbbk.supabase.co/auth/v1';
const MAX_BYTES = 64 * 1024;
const TIMEOUT_MS = 10_000;
const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
const revision = z.number().int().min(1).max(Number.MAX_SAFE_INTEGER);
const timestamp = z.iso.datetime({ offset: true });
const principal = z.object({ kind: z.enum(['corporate', 'device', 'operator']), issuer: z.string(), subject: uuid, revision }).strict();
const contextSchema = z.object({
  version: z.literal(2), application: z.literal('em'), channel: z.enum(['web', 'mobile']), authority: z.literal(CORPORATE_ISSUER),
  workshop: z.object({ id: uuid, code: z.string().regex(/^[A-Z0-9][A-Z0-9_-]{0,39}$/),
    name: z.string().min(1).max(200).refine(value => value === value.trim() && !/[\u0000-\u001f\u007f]/.test(value)),
    active: z.literal(true), revision, updated_at: timestamp }).strict(),
  principals: z.array(principal).min(1).max(2), issued_at: timestamp, expires_at: timestamp,
}).strict();
export type WorkshopContext = z.infer<typeof contextSchema>;
export type ExpectedWorkshopIdentity = { channel: 'web'; subject: string } | { channel: 'mobile'; deviceSubject: string; operatorSubject: string };
export class WorkshopContextError extends Error {
  readonly status: 401 | 403 | 503;
  constructor(readonly code: 'WORKSHOP_UNAUTHORIZED' | 'WORKSHOP_FORBIDDEN' | 'WORKSHOP_UNAVAILABLE') {
    super(code === 'WORKSHOP_UNAUTHORIZED' ? 'Entre novamente para confirmar sua oficina.'
      : code === 'WORKSHOP_FORBIDDEN' ? 'O vínculo de oficina precisa ser revisado pela administração.'
        : 'Não foi possível confirmar a oficina. Tente novamente.');
    this.name = 'WorkshopContextError';
    this.status = code === 'WORKSHOP_UNAUTHORIZED' ? 401 : code === 'WORKSHOP_FORBIDDEN' ? 403 : 503;
  }
}
const unavailable = () => new WorkshopContextError('WORKSHOP_UNAVAILABLE');

/** Parses only an authenticated authority response. This does not authenticate a
 * mobile operator, grant capabilities, scope a query or prove data isolation. */
export function validateWorkshopContext(value: unknown, expected: ExpectedWorkshopIdentity, now = Date.now()): WorkshopContext {
  const parsed = contextSchema.safeParse(value);
  if (!parsed.success || !Number.isFinite(now)) throw unavailable();
  const context = parsed.data;
  const expectedPrincipals = expected?.channel === 'web'
    ? [{ kind: 'corporate', issuer: CORPORATE_ISSUER, subject: expected.subject }]
    : expected?.channel === 'mobile'
      ? [{ kind: 'device', issuer: EM_IDENTITY_ISSUER, subject: expected.deviceSubject },
        { kind: 'operator', issuer: EM_IDENTITY_ISSUER, subject: expected.operatorSubject }] : [];
  if (!expectedPrincipals.length || context.channel !== expected.channel || context.principals.length !== expectedPrincipals.length
    || context.principals.some((p, i) => {
      const e = expectedPrincipals[i];
      return !uuid.safeParse(e.subject).success || p.kind !== e.kind || p.issuer !== e.issuer || p.subject !== e.subject;
    })) throw unavailable();
  const issued = Date.parse(context.issued_at), expires = Date.parse(context.expires_at);
  if (Math.abs(now - issued) > 10_000 || expires <= now || expires <= issued || expires - issued > 300_000) throw unavailable();
  return context;
}

/** O09/O10 writes and O11 selected portal reads use this reader.
 * Call only AFTER current corporate SSO/MFA and capabilities have been verified.
 * This targeted guard does not activate read, Storage or offline isolation. */
export function createWorkshopContextReader({ fetcher = fetch, now = Date.now }: { fetcher?: typeof fetch; now?: () => number } = {}) {
  async function readContext(url: string, request: RequestInit, expected: ExpectedWorkshopIdentity, expiresAt: number) {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(unavailable()); }, TIMEOUT_MS);
    });
    try {
      const response = await Promise.race([fetcher(url, { ...request, cache: 'no-store', redirect: 'error', signal: controller.signal }), deadline]);
      if (response.status === 401) throw new WorkshopContextError(expected.channel === 'web' ? 'WORKSHOP_UNAUTHORIZED' : 'WORKSHOP_UNAVAILABLE');
      if (response.status === 403) throw new WorkshopContextError('WORKSHOP_FORBIDDEN');
      const length = response.headers.get('content-length');
      if (response.status !== 200 || response.redirected
        || response.url && response.url !== url
        || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body
        || length !== null && (!/^\d+$/.test(length) || Number(length) > MAX_BYTES)) throw unavailable();
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      while (true) {
        const chunk = await Promise.race([reader.read(), deadline]);
        if (chunk.done) break;
        size += chunk.value.byteLength;
        if (size > MAX_BYTES) throw unavailable();
        chunks.push(chunk.value);
      }
      if (expiresAt <= now()) throw new WorkshopContextError('WORKSHOP_UNAUTHORIZED');
      return validateWorkshopContext(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))), expected, now());
    } catch (error) {
      throw error instanceof WorkshopContextError ? error : unavailable();
    } finally {
      clearTimeout(timer);
      controller.abort();
      // A failed stream must not postpone the request deadline.
      if (reader) { void reader.cancel().catch(() => {}); reader.releaseLock(); }
    }
  }
  return {
    async readWeb(session: VerifiedCorporateSession): Promise<WorkshopContext> {
      const subject = session?.user?.id;
      if (!uuid.safeParse(subject).success || !Number.isFinite(session?.expiresAt) || session.expiresAt <= now()
        || typeof session?.accessToken !== 'string' || session.accessToken.length > 16384
        || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(session.accessToken)) {
        throw new WorkshopContextError('WORKSHOP_UNAUTHORIZED');
      }
      try { validateCorporateDecision(session.decision, subject); }
      catch { throw new WorkshopContextError('WORKSHOP_FORBIDDEN'); }
      return readContext(WORKSHOP_CONTEXT_URL, {
        method: 'GET', headers: { Authorization: `Bearer ${session.accessToken}`, Accept: 'application/json' },
      }, { channel: 'web', subject }, session.expiresAt);
    },
    async readMobile(expected: Extract<ExpectedWorkshopIdentity, { channel: 'mobile' }>, expiresAt: number, key: string): Promise<WorkshopContext> {
      if (!uuid.safeParse(expected?.deviceSubject).success || !uuid.safeParse(expected?.operatorSubject).success
        || !Number.isFinite(expiresAt) || expiresAt <= now()) throw new WorkshopContextError('WORKSHOP_UNAUTHORIZED');
      if (!/^[A-Za-z0-9_-]{43,128}$/.test(key)) throw unavailable();
      return readContext(MOBILE_WORKSHOP_CONTEXT_URL, {
        method: 'POST', headers: { Authorization: `Bearer ${key}`, Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({ device_subject: expected.deviceSubject, operator_subject: expected.operatorSubject }),
      }, expected, expiresAt);
    },
  };
}
