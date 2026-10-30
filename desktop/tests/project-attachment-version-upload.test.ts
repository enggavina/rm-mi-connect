import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { attachmentVersionReservationId, handleProjectAttachmentVersionUpload } from '../src/server/web/project-attachment-version-upload';
import { attachmentReservationId } from '../src/server/web/project-dossier-upload';
import { MAX_PROJECT_ATTACHMENT_BYTES, projectAttachmentPath, type ProjectAttachmentInput } from '../src/server/web/project-dossier-policy';
import { projectAttachmentVersionSchema, type ProjectAttachmentVersionInput } from '../src/server/web/project-attachment-version-policy';
import type { actionUser, WebActionResult } from '../src/server/web/mutation';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', context = 'a'.repeat(64), origin = 'https://em.example.test';
const pdf = new TextEncoder().encode('%PDF-1.7\nOriginal immutable bytes reused intentionally\n%%EOF');
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const input: ProjectAttachmentVersionInput = { submissionId: id(1), projeto_id: id(2), source_attachment_id: id(3),
  expected_project_updated_at: version, expected_attachment_updated_at: '2026-10-29T12:00:00.000001Z', expected_context_version: context,
  nome: 'Laudo revisado', descricao: 'Conferência do anexo.', filename: 'laudo.pdf', mime_type: 'application/pdf', byte_size: pdf.length,
  sha256: hash(pdf), data_vencimento: null, status: 'No prazo', motivo: 'Arquivo conferido pela equipe', confirm_change: true };
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.documents.read', 'em.projects.manage'];
type Patch = (result: WebActionResult) => WebActionResult;
type Options = { role?: string; capabilities?: CorporateCapability[]; authFailure?: string; reserveFailure?: string; finalFailure?: string;
  reservePatch?: Patch; finalPatch?: Patch; store?: (value: ProjectAttachmentInput, bytes: Uint8Array) => Promise<void> };
function fixture(options: Options = {}) {
  const auth: string[] = [], calls: any[][] = [], uploads: { input: ProjectAttachmentInput; bytes: Uint8Array }[] = [], capabilities = options.capabilities ?? caps;
  const access = { client: {}, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role ?? 'administrador' },
    sso: { sessionHash: 'current-session', bindingId: id(12), subject: id(13), capabilities } } as Awaited<ReturnType<typeof actionUser>>;
  const dependencies = {
    actionUser: (async (capability: CorporateCapability) => { auth.push(capability); return options.authFailure || !capabilities.includes(capability)
      ? { ok: false as const, code: options.authFailure ?? 'CORP_FORBIDDEN', error: 'Sanitized' } : access; }) as typeof actionUser,
    mutate: async (...args: any[]): Promise<WebActionResult> => {
      calls.push(args); const [client, operation, request] = args; assert.equal(client, (access as any).client);
      const reserve = operation === 'reserve_project_attachment_version', failure = reserve ? options.reserveFailure : options.finalFailure;
      if (failure) return { ok: false, code: failure, error: 'Sanitized' };
      const result: WebActionResult = { ok: true, data: { operation, id: request.upload_id, projeto_id: request.projeto_id,
        updated_at: version, idempotent_replay: calls.filter(call => call[1] === operation).length > 1,
        record: reserve ? { upload_id: request.upload_id, projeto_id: request.projeto_id, source_attachment_id: input.source_attachment_id,
          root_attachment_id: input.source_attachment_id, revision: 2, context_version: input.expected_context_version,
          path: projectAttachmentPath(request.projeto_id, request.upload_id, request.mime_type), sha256: request.sha256,
          byte_size: request.byte_size, mime_type: request.mime_type, private_reservation: 'not public' }
          : { upload_id: request.upload_id, attachment_id: request.upload_id, projeto_id: request.projeto_id,
            source_attachment_id: input.source_attachment_id, root_attachment_id: input.source_attachment_id, revision: 2,
            nome: input.nome, descricao: input.descricao, tipo_arquivo: input.mime_type, status: input.status,
            data_vencimento: input.data_vencimento, visivel_cliente: false, updated_at: version, project_updated_at: version,
            context_version: 'b'.repeat(64), private_path: 'private/object/key', arquivo_url: 'https://private.invalid/object', auth_user_id: id(10) },
      } };
      return (reserve ? options.reservePatch : options.finalPatch)?.(result) ?? result;
    },
    storeAttachment: async (value: ProjectAttachmentInput, bytes: Uint8Array) => { uploads.push({ input: structuredClone(value), bytes: new Uint8Array(bytes) }); await options.store?.(value, bytes); },
  };
  return { auth, calls, uploads, dependencies, handle: (request: Request, projectId = id(2), attachmentId = id(3)) => handleProjectAttachmentVersionUpload(request, projectId, attachmentId, dependencies) };
}
function request(value: unknown = input, options: { bytes?: Uint8Array; name?: string; mime?: string; extra?: boolean; duplicate?: boolean; headers?: Record<string, string> } = {}) {
  const form = new FormData(); form.append('input', typeof value === 'string' ? value : JSON.stringify(value));
  form.append('file', new Blob([new Uint8Array(options.bytes ?? pdf)], { type: options.mime ?? input.mime_type }), options.name ?? input.filename);
  if (options.extra) form.append('actor_id', id(99)); if (options.duplicate) form.append('input', JSON.stringify(input));
  return new Request(`${origin}/upload`, { method: 'POST', body: form, headers: { host: 'em.example.test', origin, ...options.headers } });
}
function unreadRequest(headers: Record<string, string> = {}) {
  let reads = 0; const result = new Request(`${origin}/upload`, { method: 'POST', body: 'must not be parsed', headers: { host: 'em.example.test', origin, 'content-type': 'multipart/form-data; boundary=test', ...headers } });
  Object.defineProperty(result, 'body', { get() { reads++; throw Error('Body read before authorization'); } }); return { request: result, reads: () => reads };
}
const patch = (changes: Record<string, unknown>, nested?: Record<string, unknown>): Patch => result => result.ok
  ? { ok: true, data: { ...result.data, ...changes, ...(nested ? { record: { ...result.data.record, ...nested } } : {}) } } as WebActionResult : result;

test('version upload requires current management, internal writer role and all document scopes before reading bytes', async () => {
  for (const options of [{ authFailure: 'CORP_UNAUTHORIZED' }, { role: 'auditor' }, { role: 'mobile' },
    ...caps.map(capability => ({ capabilities: caps.filter(value => value !== capability) }))]) {
    const f = fixture(options), body = unreadRequest(), response = await f.handle(body.request);
    assert.ok([401, 403].includes(response.status)); assert.equal(body.reads(), 0); assert.deepEqual(f.auth, ['em.projects.manage']);
    assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0); assert.match(response.headers.get('cache-control')!, /private, no-store/);
  }
});

test('cross origin and invalid route contexts are rejected before authorization or upload parsing', async () => {
  for (const [headers, projectId, attachmentId] of [[{ origin: 'https://other.invalid' }, id(2), id(3)], [{ origin: '' }, id(2), id(3)],
    [{ host: 'em.example.test,other.test' }, id(2), id(3)], [{}, 'invalid', id(3)], [{}, id(2), 'invalid']] as const) {
    const f = fixture(), body = unreadRequest(headers), response = await f.handle(body.request, projectId, attachmentId);
    assert.ok([400, 403].includes(response.status)); assert.equal(body.reads(), 0); assert.deepEqual(f.auth, []); assert.equal(f.calls.length, 0);
  }
});

test('version metadata is strict and cannot change source context, authorship, paths or unconfirmed intent', async () => {
  const bad = [{ ...input, projeto_id: id(99) }, { ...input, source_attachment_id: id(99) }, { ...input, confirm_change: false },
    { ...input, motivo: '' }, { ...input, motivo: '\n\t' }, { ...input, motivo: 'x'.repeat(2001) }, { ...input, motivo: String.fromCharCode(0) },
    { ...input, expected_context_version: 'b'.repeat(63) }, { ...input, expected_context_version: 'A'.repeat(64) },
    { ...input, expected_attachment_updated_at: 'today' }, { ...input, expected_project_updated_at: 'today' },
    { ...input, data_vencimento: 'invalid' }, { ...input, status: 'approved' }, { ...input, byte_size: 0 },
    { ...input, filename: '../laudo.pdf' }, { ...input, filename: 'bad\\path.pdf' }, { ...input, filename: 'bad\n.pdf' },
    { ...input, nome: '' }, { ...input, descricao: 'x'.repeat(2001) },
    ...['path', 'bucket', 'arquivo_url', 'actor_id', 'created_by', 'visivel_cliente', 'root_attachment_id', 'revision'].map(key => ({ ...input, [key]: id(99) }))];
  for (const value of bad) { const f = fixture(), response = await f.handle(request(value)); assert.equal(response.status, 400); assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0); }
  for (const value of [request(input, { extra: true }), request(input, { duplicate: true }), request('{invalid-json'), request('x'.repeat(12_289))]) {
    const f = fixture(); assert.equal((await f.handle(value)).status, 400); assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
  }
});

test('extension, MIME, file name, actual bytes, signature and fingerprint are checked before reserving', async () => {
  const wrongSignature = new TextEncoder().encode('not a PDF');
  for (const value of [request(input, { name: 'other.pdf' }), request(input, { mime: 'image/png' }), request(input, { bytes: pdf.subarray(1) }),
    request({ ...input, sha256: 'f'.repeat(64) }), request({ ...input, filename: 'laudo.html' }, { name: 'laudo.html' }),
    request({ ...input, byte_size: wrongSignature.length, sha256: hash(wrongSignature) }, { bytes: wrongSignature }),
    request({ ...input, mime_type: 'image/png', filename: 'laudo.png' }, { mime: 'image/png', name: 'laudo.png' }),
    request({ ...input, mime_type: 'image/jpeg', filename: 'laudo.jpg' }, { mime: 'image/jpeg', name: 'laudo.jpg' })]) {
    const f = fixture(), response = await f.handle(value); assert.ok([400, 415].includes(response.status)); assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
  }
  const f = fixture(); assert.equal((await f.handle(new Request(`${origin}/upload`, { method: 'POST', body: '{}', headers: { host: 'em.example.test', origin, 'content-type': 'application/json' } }))).status, 415);
  for (const [mime, filename, bytes] of [
    ['image/png', 'placa.PNG', new Uint8Array(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB0UAAAAASUVORK5CYII=', 'base64'))],
    ['image/jpeg', 'placa.JPEG', new Uint8Array([255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 255, 217])],
  ] as const) {
    const supported = { ...input, mime_type: mime, filename, byte_size: bytes.length, sha256: hash(bytes) };
    const accepted = fixture({ finalPatch: patch({}, { tipo_arquivo: mime }) });
    assert.equal((await accepted.handle(request(supported, { bytes, mime, name: filename }))).status, 200);
    assert.equal(accepted.calls.length, 2); assert.deepEqual(accepted.uploads[0], { input: supported, bytes });
    assert.equal(accepted.calls[0][2].mime_type, mime);
  }
});

test('declared and streamed oversized version bodies cannot create a reservation and streaming is cancelled', async () => {
  const maximum = MAX_PROJECT_ATTACHMENT_BYTES + 64 * 1024, f = fixture(), body = unreadRequest({ 'content-length': String(maximum + 1) });
  assert.equal((await f.handle(body.request)).status, 413); assert.equal(body.reads(), 0);
  let cancelled = false; const stream = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(maximum + 1)); }, cancel() { cancelled = true; } });
  const response = await f.handle(new Request(`${origin}/upload`, { method: 'POST', headers: { host: 'em.example.test', origin, 'content-type': 'multipart/form-data; boundary=test' }, body: stream, duplex: 'half' } as RequestInit));
  assert.equal(response.status, 413); assert.equal(cancelled, true); assert.equal(f.calls.length, 0); assert.equal(f.uploads.length, 0);
});

test('an explicit new version may retain identical bytes while using new immutable storage and two deterministic receipts', async () => {
  const f = fixture({ role: 'padr_o' }), response = await f.handle(request({ ...input, submissionId: id(1).toUpperCase(), projeto_id: id(2).toUpperCase(), source_attachment_id: id(3).toUpperCase() }), id(2).toUpperCase(), id(3).toUpperCase()); assert.equal(response.status, 200);
  const reserveId = attachmentVersionReservationId(input.submissionId); assert.notEqual(reserveId, input.submissionId); assert.notEqual(reserveId, attachmentReservationId(input.submissionId));
  assert.equal(attachmentVersionReservationId(input.submissionId), reserveId); assert.deepEqual(f.uploads, [{ input, bytes: pdf }]);
  const { submissionId, ...metadata } = input; assert.deepEqual(f.calls[0][2], { submissionId: reserveId, upload_id: submissionId, ...metadata });
  assert.equal(f.calls[0][1], 'reserve_project_attachment_version'); assert.equal(f.calls[1][1], 'finalize_project_attachment_version');
  assert.deepEqual(f.calls[1][2], { submissionId, projeto_id: input.projeto_id, upload_id: submissionId });
  assert.equal(f.calls[0][3], 'em.projects.manage'); assert.equal(f.calls[1][3], 'em.projects.manage'); assert.equal(f.calls[0][4], f.calls[1][4]);
  const body = await response.json(); assert.equal(body.ok, true); assert.equal(body.data.id, submissionId); assert.equal(body.data.record.revision, 2);
  for (const forbidden of ['private/object', 'private.invalid', 'auth_user_id', 'private_reservation', 'arquivo_url', 'path']) assert.ok(!JSON.stringify(body).includes(forbidden));
  assert.equal(body.data.record.source_attachment_id, input.source_attachment_id); assert.equal(body.data.record.root_attachment_id, input.source_attachment_id);
});

test('reservation context and immutable target must match before any bytes are stored', async () => {
  for (const [changes, nested] of [[{ operation: 'finalize_project_attachment_version' }], [{ id: id(99) }], [{ projeto_id: id(99) }],
    [{ updated_at: 'invalid' }], [{ idempotent_replay: null }], [{ record: null }],
    ...['upload_id', 'projeto_id', 'source_attachment_id'].map(key => [{}, { [key]: id(99) }]),
    [{}, { path: 'web-dossier/other/file.pdf' }], [{}, { context_version: 'b'.repeat(64) }], [{}, { root_attachment_id: 'invalid' }],
    [{}, { revision: 1 }], [{}, { mime_type: 'image/png' }], [{}, { byte_size: 999 }], [{}, { sha256: 'f'.repeat(64) }],
  ] as [Record<string, unknown>, Record<string, unknown>?][]) {
    const f = fixture({ reservePatch: patch(changes, nested) }), response = await f.handle(request()); assert.equal(response.status, 503); assert.equal(f.calls.length, 1); assert.equal(f.uploads.length, 0);
  }
});

test('final confirmation validates the exact new row, source, root, revision and selected metadata', async () => {
  for (const [changes, nested] of [[{ operation: 'reserve_project_attachment_version' }], [{ id: id(99) }], [{ projeto_id: id(99) }],
    [{ updated_at: 'invalid' }], [{ idempotent_replay: null }], [{ record: null }],
    ...['upload_id', 'projeto_id', 'attachment_id', 'source_attachment_id', 'root_attachment_id'].map(key => [{}, { [key]: id(99) }]),
    [{}, { revision: 3 }], [{}, { nome: 'Different' }], [{}, { descricao: 'Different' }], [{}, { tipo_arquivo: 'image/png' }],
    [{}, { status: 'Vencido' }], [{}, { visivel_cliente: true }], [{}, { updated_at: '2000-01-01T00:00:00Z' }],
    [{}, { data_vencimento: version }], [{}, { project_updated_at: 'invalid' }], [{}, { context_version: 'invalid' }],
  ] as [Record<string, unknown>, Record<string, unknown>?][]) {
    const f = fixture({ finalPatch: patch(changes, nested) }), response = await f.handle(request()); assert.equal(response.status, 503); assert.equal(f.calls.length, 2); assert.equal(f.uploads.length, 1);
    const body = await response.json(); assert.equal(body.ok, false); assert.equal(body.data, undefined);
  }
});

test('reservation refusal cannot upload and storage failure cannot finalize or leak sensitive details', async () => {
  const denied = fixture({ reserveFailure: 'PT409' }); assert.equal((await denied.handle(request())).status, 409); assert.equal(denied.calls.length, 1); assert.equal(denied.uploads.length, 0);
  const failed = fixture({ store: async () => { throw Error('private/object/key credentials'); } }), response = await failed.handle(request());
  assert.equal(response.status, 503); assert.equal(failed.calls.length, 1); assert.equal(failed.uploads.length, 1); assert.ok(!JSON.stringify(await response.json()).includes('private/object'));
  for (const code of ['CORP_FORBIDDEN', 'CORP_UNAVAILABLE', 'PT409', '23505', 'UNAVAILABLE']) {
    const f = fixture({ finalFailure: code }), response = await f.handle(request()); assert.equal((await response.json()).code, code); assert.equal(f.uploads.length, 1); assert.equal(f.calls.length, 2);
  }
});

test('uncertain storage or committed final response replays the same frozen file, source and protocol pair', async () => {
  for (const failAt of ['storage', 'final'] as const) {
    let attempt = 0, commits = 0; const committed = new Map<string, WebActionResult>();
    const f = fixture({ store: async () => { if (failAt === 'storage' && attempt++ === 0) throw Error('Lost upload response'); },
      finalPatch: result => {
        const previous = committed.get(input.submissionId); if (previous && previous.ok) return { ok: true, data: { ...previous.data, idempotent_replay: true } };
        commits++; committed.set(input.submissionId, result);
        return failAt === 'final' && attempt++ === 0 ? { ok: false, code: 'UNAVAILABLE', error: 'Lost committed reply' } : result;
      } });
    assert.equal((await f.handle(request())).status, 503); const second = await f.handle(request()); assert.equal(second.status, 200);
    const reservations = f.calls.filter(call => call[1] === 'reserve_project_attachment_version'), finals = f.calls.filter(call => call[1] === 'finalize_project_attachment_version');
    assert.deepEqual(reservations[0], reservations[1]); assert.deepEqual(f.uploads[0], f.uploads[1]); assert.equal(finals.at(-1)![2].submissionId, input.submissionId); assert.equal(commits, 1);
    if (failAt === 'final') { assert.deepEqual(finals[0], finals[1]); assert.equal((await second.json()).data.idempotent_replay, true); }
  }
});

test('version input normalizes valid UUID case while retaining precise source/project versions and closed metadata', () => {
  const parsed = projectAttachmentVersionSchema.parse({ ...input, submissionId: id(1).toUpperCase(), projeto_id: id(2).toUpperCase(), source_attachment_id: id(3).toUpperCase(), motivo: '  Conferido  ' });
  assert.equal(parsed.submissionId, input.submissionId); assert.equal(parsed.projeto_id, input.projeto_id); assert.equal(parsed.source_attachment_id, input.source_attachment_id);
  assert.equal(parsed.motivo, 'Conferido'); assert.equal(parsed.expected_attachment_updated_at, input.expected_attachment_updated_at); assert.equal(parsed.expected_project_updated_at, version);
  assert.ok(projectAttachmentVersionSchema.safeParse({ ...input, byte_size: MAX_PROJECT_ATTACHMENT_BYTES }).success);
});
