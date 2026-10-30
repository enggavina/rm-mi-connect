import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { attachmentReservationId, handleProjectAttachmentUpload } from '../src/server/web/project-dossier-upload';
import { MAX_PROJECT_ATTACHMENT_BYTES, projectAttachmentPath, projectAttachmentSchema, type ProjectAttachmentInput } from '../src/server/web/project-dossier-policy';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', origin = 'https://em.example.test';
const pdf = new TextEncoder().encode('%PDF-1.7\nEM private attachment\n%%EOF');
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const input: ProjectAttachmentInput = { submissionId: id(1), projeto_id: id(2), expected_project_updated_at: version,
  nome: 'Placa e inspeção', descricao: 'Observação privada da equipe.', filename: 'equipamento.pdf', mime_type: 'application/pdf',
  byte_size: pdf.length, sha256: hash(pdf), data_vencimento: null, status: 'No prazo' };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.projects.manage', 'em.documents.read'];
type Patch = (result: WebActionResult) => WebActionResult;
type Options = { role?: string; capabilities?: CorporateCapability[]; authFailure?: string; reserveFailure?: string; finalFailure?: string;
  reservePatch?: Patch; finalPatch?: Patch; store?: (value: ProjectAttachmentInput, bytes: Uint8Array) => Promise<void> };

function fixture(options: Options = {}) {
  const auth: string[] = [], calls: any[][] = [], uploads: { input: ProjectAttachmentInput; bytes: Uint8Array }[] = [];
  const capabilities = options.capabilities ?? caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role ?? 'administrador' },
    sso: { sessionHash: 'current-session', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const dependencies = {
    actionUser: (async (capability: CorporateCapability) => {
      auth.push(capability); return options.authFailure || !capabilities.includes(capability)
        ? { ok: false as const, code: options.authFailure ?? 'CORP_FORBIDDEN', error: 'Sanitized' } : access;
    }) as typeof actionUser,
    mutate: async (...args: any[]): Promise<WebActionResult> => {
      calls.push(args); const [client, operation, request] = args;
      assert.equal(client, (access as any).client);
      const isReserve = operation === 'reserve_project_attachment', failure = isReserve ? options.reserveFailure : options.finalFailure;
      if (failure) return { ok: false, code: failure, error: 'Sanitized' };
      const data: WebActionResult = { ok: true, data: { operation, id: request.upload_id, projeto_id: request.projeto_id,
        updated_at: version, idempotent_replay: calls.filter(call => call[1] === operation).length > 1,
        record: isReserve ? { upload_id: request.upload_id, projeto_id: request.projeto_id,
          path: projectAttachmentPath(request.projeto_id, request.upload_id, request.mime_type), sha256: request.sha256,
          byte_size: request.byte_size, mime_type: request.mime_type, private_payload: 'private reservation' }
          : { upload_id: request.upload_id, attachment_id: request.upload_id, projeto_id: request.projeto_id,
            nome: input.nome, descricao: input.descricao, tipo_arquivo: input.mime_type, status: input.status,
            data_vencimento: input.data_vencimento, visivel_cliente: false, updated_at: version,
            private_path: 'private/object/key', arquivo_url: 'https://private.invalid/never-exposed', actor_auth_user_id: id(10) },
      } };
      return (isReserve ? options.reservePatch : options.finalPatch)?.(data) ?? data;
    },
    storeAttachment: async (value: ProjectAttachmentInput, bytes: Uint8Array) => {
      uploads.push({ input: structuredClone(value), bytes: new Uint8Array(bytes) }); await options.store?.(value, bytes);
    },
  };
  return { auth, calls, uploads, dependencies, handle: (request: Request, projectId = id(2)) => handleProjectAttachmentUpload(request, projectId, dependencies) };
}

function request(value: unknown = input, options: { bytes?: Uint8Array; name?: string; mime?: string; extra?: boolean; duplicate?: boolean; headers?: Record<string, string> } = {}) {
  const form = new FormData(); form.append('input', typeof value === 'string' ? value : JSON.stringify(value));
  form.append('file', new Blob([new Uint8Array(options.bytes ?? pdf)], { type: options.mime ?? input.mime_type }), options.name ?? input.filename);
  if (options.extra) form.append('actor_id', id(99));
  if (options.duplicate) form.append('input', JSON.stringify(input));
  return new Request(`${origin}/api/web/projects/${id(2)}/attachments`, { method: 'POST', body: form,
    headers: { host: 'em.example.test', origin, ...options.headers } });
}
function unreadRequest(headers: Record<string, string> = {}) {
  let reads = 0;
  const result = new Request(`${origin}/upload`, { method: 'POST', body: 'must never be parsed',
    headers: { host: 'em.example.test', origin, 'content-type': 'multipart/form-data; boundary=test', ...headers } });
  Object.defineProperty(result, 'body', { get() { reads++; throw new Error('Body read before authorization'); } });
  return { request: result, reads: () => reads };
}
const patch = (changes: Record<string, unknown>, nested?: Record<string, unknown>): Patch => result => result.ok
  ? { ok: true, data: { ...result.data, ...changes, ...(nested ? { record: { ...result.data.record, ...nested } } : {}) } } as unknown as WebActionResult : result;

test('attachment authorization, current write role and read scopes are checked before the upload body', async () => {
  for (const options of [{ authFailure: 'CORP_UNAUTHORIZED' }, { role: 'auditor' }, { role: 'mobile' },
    ...caps.map(capability => ({ capabilities: caps.filter(value => value !== capability) })),
    { capabilities: ['em.engineering.manage', 'em.approvals.decide'] as CorporateCapability[] }]) {
    const f = fixture(options), body = unreadRequest(), result = await f.handle(body.request);
    assert.ok([401, 403].includes(result.status)); assert.equal(body.reads(), 0);
    assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0); assert.deepEqual(f.auth, ['em.projects.manage']);
    assert.match(result.headers.get('cache-control')!, /private, no-store/);
  }
});

test('cross-origin or invalid project uploads stop before authorization or body parsing', async () => {
  for (const [headers, projectId] of [[{ origin: 'https://other.example.test' }, id(2)], [{ origin: '' }, id(2)], [{ host: 'em.example.test,other.test' }, id(2)], [{}, 'not-a-project']] as const) {
    const f = fixture(), body = unreadRequest(headers), result = await f.handle(body.request, projectId);
    assert.ok([400, 403].includes(result.status)); assert.equal(body.reads(), 0); assert.deepEqual(f.auth, []);
    assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
  }
});

test('untrusted attachment metadata, extra form fields and crossed projects cannot reserve or store anything', async () => {
  const bad = [
    { ...input, projeto_id: id(99) }, { ...input, byte_size: 0 }, { ...input, byte_size: MAX_PROJECT_ATTACHMENT_BYTES + 1 },
    { ...input, filename: '../other.pdf' }, { ...input, filename: 'bad\\path.pdf' }, { ...input, filename: 'bad\u0000.pdf' },
    { ...input, expected_project_updated_at: 'yesterday' }, { ...input, data_vencimento: 'not a date' }, { ...input, status: 'approved' },
    { ...input, mime_type: 'text/html' }, { ...input, nome: ' ' }, { ...input, descricao: 'a'.repeat(2001) },
    ...['path', 'arquivo_url', 'bucket', 'actor_id', 'created_by', 'visivel_cliente'].map(key => ({ ...input, [key]: 'injected' })),
  ];
  for (const value of bad) {
    const f = fixture(), result = await f.handle(request(value)); assert.equal(result.status, 400);
    assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
  }
  for (const payload of [request(input, { extra: true }), request(input, { duplicate: true }), request('{bad-json'), request('a'.repeat(8193))]) {
    const f = fixture(), result = await f.handle(payload); assert.equal(result.status, 400); assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
  }
});

test('file name, MIME, byte length, fingerprint and signature are verified before any receipt or storage operation', async () => {
  for (const value of [request(input, { name: 'different.pdf' }), request(input, { mime: 'image/png' }), request(input, { bytes: pdf.subarray(0, pdf.length - 1) }),
    request({ ...input, sha256: 'f'.repeat(64) }), request({ ...input, mime_type: 'image/png' }, { mime: 'image/png' }),
    request({ ...input, mime_type: 'image/jpeg' }, { mime: 'image/jpeg' })]) {
    const f = fixture(), result = await f.handle(value); assert.ok([400, 415].includes(result.status));
    assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
  }
  const invalid = fixture(), media = await invalid.handle(new Request(`${origin}/upload`, { method: 'POST', body: '{}', headers: { host: 'em.example.test', origin, 'content-type': 'application/json' } }));
  assert.equal(media.status, 415); assert.equal(invalid.calls.length, 0);
});

test('both declared and streamed oversized multipart bodies are rejected before a reservation and the stream is cancelled', async () => {
  const maximum = MAX_PROJECT_ATTACHMENT_BYTES + 64 * 1024;
  const f = fixture(), declared = unreadRequest({ 'content-length': String(maximum + 1) });
  assert.equal((await f.handle(declared.request)).status, 413); assert.equal(declared.reads(), 0);
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(maximum + 1)); }, cancel() { cancelled = true; } });
  const streamed = new Request(`${origin}/upload`, { method: 'POST', headers: { host: 'em.example.test', origin, 'content-type': 'multipart/form-data; boundary=test' }, body: stream, duplex: 'half' } as RequestInit);
  assert.equal((await f.handle(streamed)).status, 413); assert.equal(cancelled, true);
  assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
});

test('one verified attachment uses deterministic separate receipts and returns only the final public result', async () => {
  const f = fixture({ role: 'padr_o' }), result = await f.handle(request()); assert.equal(result.status, 200);
  assert.match(result.headers.get('cache-control')!, /private, no-store/); assert.equal(result.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(f.calls.length, 2); assert.equal(f.uploads.length, 1); assert.deepEqual(f.uploads[0], { input, bytes: pdf });
  const reservation = attachmentReservationId(input.submissionId); assert.notEqual(reservation, input.submissionId);
  assert.match(reservation, /^[0-9a-f-]{36}$/); assert.equal(attachmentReservationId(input.submissionId), reservation);
  const { submissionId, ...metadata } = input;
  assert.deepEqual(f.calls[0][2], { submissionId: reservation, upload_id: submissionId, ...metadata });
  assert.equal(f.calls[0][1], 'reserve_project_attachment'); assert.equal(f.calls[1][1], 'finalize_project_attachment');
  assert.deepEqual(f.calls[1][2], { submissionId, projeto_id: input.projeto_id, upload_id: submissionId });
  assert.equal(f.calls[0][3], 'em.projects.manage'); assert.equal(f.calls[1][3], 'em.projects.manage');
  assert.equal(f.calls[0][4], f.calls[1][4]); assert.equal(f.calls[1][4].subject, id(13));
  const body = await result.json(); assert.equal(body.ok, true); assert.equal(body.data.id, submissionId);
  assert.deepEqual(Object.keys(body.data.record).sort(), ['upload_id', 'projeto_id', 'attachment_id', 'nome', 'descricao', 'tipo_arquivo', 'status', 'data_vencimento', 'visivel_cliente', 'updated_at'].sort());
  assert.equal(JSON.stringify(body).includes('private/object'), false); assert.equal(JSON.stringify(body).includes('private.invalid'), false); assert.equal(JSON.stringify(body).includes('actor_auth_user_id'), false);
});

test('invalid reservation identities, paths or fingerprints stop before uploading and finalizing', async () => {
  for (const [changes, nested] of [
    [{ operation: 'finalize_project_attachment' }], [{ id: id(99) }], [{ projeto_id: id(99) }], [{ updated_at: 'invalid' }], [{ idempotent_replay: null }],
    [{ record: null }], [{ record: undefined }], [{}, { upload_id: id(99) }], [{}, { projeto_id: id(99) }],
    [{}, { path: 'https://private.invalid/arbitrary' }], [{}, { path: 'web-dossier/other/file.pdf' }],
    [{}, { sha256: 'a'.repeat(64) }], [{}, { byte_size: input.byte_size + 1 }], [{}, { mime_type: 'text/html' }],
  ] as [Record<string, unknown>, Record<string, unknown>?][]) {
    const f = fixture({ reservePatch: patch(changes, nested) }), result = await f.handle(request());
    assert.equal(result.status, 503); assert.equal(f.calls.length, 1); assert.equal(f.uploads.length, 0);
    const body = await result.json(); assert.equal(body.code, 'UNAVAILABLE'); assert.equal(body.data, undefined);
  }
});

test('publication rejects mismatched final project, document identity or metadata and never returns private records', async () => {
  for (const [changes, nested] of [
    [{ operation: 'reserve_project_attachment' }], [{ id: id(99) }], [{ projeto_id: id(99) }], [{ updated_at: 'invalid' }], [{ idempotent_replay: null }],
    [{ record: null }], [{ record: undefined }],
    ...['upload_id', 'attachment_id', 'projeto_id'].map(key => [{}, { [key]: id(99) }]),
    [{}, { nome: 'Other name' }], [{}, { descricao: 'Other description' }], [{}, { tipo_arquivo: 'text/html' }],
    [{}, { status: 'Vencido' }], [{}, { visivel_cliente: true }], [{}, { updated_at: '2000-01-01T00:00:00Z' }],
    [{}, { data_vencimento: version }],
  ] as [Record<string, unknown>, Record<string, unknown>?][]) {
    const f = fixture({ finalPatch: patch(changes, nested) }), result = await f.handle(request());
    assert.equal(result.status, 503); assert.equal(f.calls.length, 2); assert.equal(f.uploads.length, 1);
    const body = await result.json(); assert.equal(body.ok, false); assert.equal(body.code, 'UNAVAILABLE'); assert.equal(body.data, undefined);
  }
});

test('reservation denial cannot upload; failed storage cannot finalize; final permission or version changes remain explicit', async () => {
  const denied = fixture({ reserveFailure: 'PT409' }); assert.equal((await denied.handle(request())).status, 409); assert.equal(denied.uploads.length, 0); assert.equal(denied.calls.length, 1);
  const failed = fixture({ store: async () => { throw new Error('private/object/key secret detail'); } }), response = await failed.handle(request());
  assert.equal(response.status, 503); assert.equal(failed.calls.length, 1); assert.equal(JSON.stringify(await response.json()).includes('private/object/key'), false);
  for (const code of ['CORP_FORBIDDEN', 'CORP_UNAVAILABLE', 'PT409', 'UNAVAILABLE']) {
    const f = fixture({ finalFailure: code }), result = await f.handle(request()), body = await result.json();
    assert.equal(body.code, code); assert.equal(f.calls.length, 2); assert.equal(f.uploads.length, 1); assert.equal(body.data, undefined);
  }
});

test('retry after an uncertain upload or final response keeps the exact intent, original bytes and both protocol IDs', async () => {
  for (const failureAt of ['upload', 'final'] as const) {
    let attempt = 0;
    const f = fixture({ store: async () => { if (failureAt === 'upload' && attempt++ === 0) throw new Error('Lost upload response'); },
      finalPatch: result => failureAt === 'final' && attempt++ === 0 ? { ok: false, code: 'UNAVAILABLE', error: 'Retry same attempt' } : result });
    const first = await f.handle(request()); assert.equal(first.status, 503);
    const second = await f.handle(request()); assert.equal(second.status, 200);
    const reserved = f.calls.filter(call => call[1] === 'reserve_project_attachment'), finalized = f.calls.filter(call => call[1] === 'finalize_project_attachment');
    assert.deepEqual(reserved[0], reserved[1]); assert.equal(reserved[0][2].submissionId, attachmentReservationId(input.submissionId));
    assert.equal(finalized.at(-1)![2].submissionId, input.submissionId); assert.deepEqual(f.uploads[0], f.uploads[1]);
    if (failureAt === 'final') { assert.deepEqual(finalized[0], finalized[1]); assert.equal((await second.json()).data.idempotent_replay, true); }
  }
});

test('attachment input keeps exact dates and allows only registered media types with closed metadata', () => {
  assert.deepEqual(projectAttachmentSchema.parse(input), input);
  assert.equal(projectAttachmentSchema.parse({ ...input, data_vencimento: version }).data_vencimento, version);
  assert.equal(projectAttachmentSchema.safeParse({ ...input, byte_size: MAX_PROJECT_ATTACHMENT_BYTES }).success, true);
  assert.equal(projectAttachmentSchema.safeParse({ ...input, sha256: input.sha256.toUpperCase() }).success, false);
});
