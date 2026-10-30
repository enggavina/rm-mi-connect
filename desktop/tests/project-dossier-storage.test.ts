import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { storeProjectAttachment } from '../src/server/web/project-dossier-storage';
import { projectAttachmentPath, type ProjectAttachmentInput } from '../src/server/web/project-dossier-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const target = 'https://ellpxfbsrbhblyizvbbk.supabase.co';
const bytes = new TextEncoder().encode('%PDF-1.7\nprivate EM appendix\n%%EOF');
const input: ProjectAttachmentInput = { submissionId: id(1), projeto_id: id(2), expected_project_updated_at: '2026-10-30T16:00:01.123456+00:00',
  nome: 'Placa do equipamento', descricao: null, filename: 'placa.pdf', mime_type: 'application/pdf', byte_size: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex'), data_vencimento: null, status: 'No prazo' };
type Call = { url: URL; method: string; headers: Headers; init: RequestInit };

async function withStorage(reply: (call: Call, index: number) => Response | Promise<Response>, run: (calls: Call[]) => Promise<void>, url = target) {
  const previous = { fetch: globalThis.fetch, url: process.env.SUPABASE_URL, key: process.env.EM_SSO_BRIDGE_SERVICE_ROLE_KEY };
  const calls: Call[] = [];
  process.env.SUPABASE_URL = url; process.env.EM_SSO_BRIDGE_SERVICE_ROLE_KEY = 'unit-test-service-key';
  globalThis.fetch = async (resource, init = {}) => {
    const call = { url: new URL(resource instanceof Request ? resource.url : String(resource)), method: init.method ?? 'GET', headers: new Headers(init.headers), init };
    assert.equal(call.url.origin, target, 'The stub never delegates to a live network');
    calls.push(call); return reply(call, calls.length - 1);
  };
  try { await run(calls); }
  finally {
    globalThis.fetch = previous.fetch;
    if (previous.url === undefined) delete process.env.SUPABASE_URL; else process.env.SUPABASE_URL = previous.url;
    if (previous.key === undefined) delete process.env.EM_SSO_BRIDGE_SERVICE_ROLE_KEY; else process.env.EM_SSO_BRIDGE_SERVICE_ROLE_KEY = previous.key;
  }
}
const uploaded = () => Response.json({ Key: `rm-documentos/${projectAttachmentPath(input.projeto_id, input.submissionId, input.mime_type)}`, Id: id(3) });
const duplicate = (status = 409) => Response.json({ statusCode: String(status), error: 'Duplicate', message: 'The resource already exists' }, { status });

test('the private attachment writer refuses another Supabase target and mismatched bytes before creating a client request', async () => {
  await withStorage(() => { throw new Error('Unexpected request'); }, async calls => {
    await assert.rejects(storeProjectAttachment(input, bytes), /Invalid EM storage target/); assert.equal(calls.length, 0);
  }, 'https://other-project.supabase.co');
  await withStorage(() => { throw new Error('Unexpected request'); }, async calls => {
    for (const invalid of [{ ...input, byte_size: input.byte_size + 1 }, { ...input, sha256: 'a'.repeat(64) }, { ...input, mime_type: 'image/png' as const }]) {
      await assert.rejects(storeProjectAttachment(invalid, bytes), /does not match/);
    }
    assert.equal(calls.length, 0);
  });
});

test('the real storage SDK writes only the server-derived immutable path with no redirect, overwrite or public sharing', async () => {
  await withStorage(() => uploaded(), async calls => {
    await storeProjectAttachment(input, bytes); assert.equal(calls.length, 1);
    const call = calls[0], path = projectAttachmentPath(input.projeto_id, input.submissionId, input.mime_type);
    assert.equal(call.url.pathname, `/storage/v1/object/rm-documentos/${path}`); assert.equal(call.url.search, ''); assert.equal(call.method, 'POST');
    assert.equal(call.headers.get('x-upsert'), 'false'); assert.equal(call.headers.get('content-type'), 'application/pdf');
    assert.deepEqual(JSON.parse(Buffer.from(call.headers.get('x-metadata')!, 'base64').toString('utf8')), { sha256: input.sha256 });
    assert.deepEqual(new Uint8Array(call.init.body as Uint8Array), bytes);
    assert.equal(call.init.redirect, 'error'); assert.equal(call.init.cache, 'no-store'); assert.ok(call.init.signal instanceof AbortSignal);
    assert.equal(call.headers.get('authorization'), 'Bearer unit-test-service-key');
  });
});

test('an ambiguous prior upload is confirmed by downloading and hashing the exact existing object without replacing it', async () => {
  for (const status of [400, 409]) await withStorage((call, index) => index === 0 ? duplicate(status) : new Response(new Uint8Array(bytes), { headers: { 'content-type': input.mime_type } }), async calls => {
    await storeProjectAttachment(input, bytes); assert.equal(calls.length, 2);
    const path = projectAttachmentPath(input.projeto_id, input.submissionId, input.mime_type);
    assert.equal(calls[0].method, 'POST'); assert.equal(calls[0].headers.get('x-upsert'), 'false');
    assert.equal(calls[1].method, 'GET'); assert.equal(calls[1].url.pathname, `/storage/v1/object/rm-documentos/${path}`);
    assert.equal(calls[1].headers.get('authorization'), 'Bearer unit-test-service-key');
    assert.ok(calls.every(call => !['PUT', 'PATCH', 'DELETE'].includes(call.method)));
  });
});

test('an existing object with a different length or fingerprint is not accepted, overwritten or deleted', async () => {
  const changed = new Uint8Array(bytes); changed[changed.length - 1] ^= 1;
  for (const existing of [changed, bytes.subarray(0, bytes.length - 1)]) {
    await withStorage((call, index) => index === 0 ? duplicate() : new Response(new Uint8Array(existing), { headers: { 'content-type': input.mime_type } }), async calls => {
      await assert.rejects(storeProjectAttachment(input, bytes), /Existing attachment differs/);
      assert.equal(calls.length, 2); assert.deepEqual(calls.map(call => call.method), ['POST', 'GET']);
    });
  }
});

test('non-duplicate storage rejection and inaccessible prior objects fail without finalizing or cleanup side effects', async () => {
  await withStorage(() => Response.json({ statusCode: '403', error: 'Forbidden', message: 'Access denied' }, { status: 403 }), async calls => {
    await assert.rejects(storeProjectAttachment(input, bytes), /could not be confirmed/); assert.equal(calls.length, 1);
  });
  await withStorage((call, index) => index === 0 ? duplicate() : Response.json({ statusCode: '404', error: 'Not found', message: 'Object not found' }, { status: 404 }), async calls => {
    await assert.rejects(storeProjectAttachment(input, bytes), /Existing attachment differs/); assert.deepEqual(calls.map(call => call.method), ['POST', 'GET']);
  });
});
