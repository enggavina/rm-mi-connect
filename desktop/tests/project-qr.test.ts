import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import sharp from 'sharp';
import jsQR from 'jsqr';
import { createProjectQrData } from '../src/server/web/project-qr-data';
import { projectQrValue, type ProjectQrProject } from '../src/server/web/project-qr-policy';
import { renderProjectQrSvg } from '../src/server/web/project-qr-image';
import { handleProjectQrImage } from '../src/server/web/project-qr-route';
import type { getWebUser } from '../src/server/web/auth';
import { CorporateAuthError, type CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00';
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
const project = (): ProjectQrProject => ({ id: id(1), numero: 'OS 014', nome: 'Projeto de teste', descricao_equipamento: 'Motor em recebimento', updated_at: version });
function database(data: unknown = project(), options: { error?: boolean; thrown?: boolean; capabilities?: CorporateCapability[] } = {}) {
  const calls: { table: string; columns: string; key: string; value: unknown }[] = [];
  const client = { from: (table: string) => ({ select: (columns: string) => ({ eq: (key: string, value: unknown) => ({ maybeSingle: async () => {
    calls.push({ table, columns, key, value }); if (options.thrown) throw Error('private network details');
    return { data, error: options.error ? { message: 'private SQL details' } : null };
  } }) }) }) } as unknown as SupabaseClient;
  return { client, calls, ...createProjectQrData(client, options.capabilities ?? caps) };
}
async function decode(svg: string, width = 512, rotation = 0) {
  const raster = await sharp(Buffer.from(svg)).resize(width, width).rotate(rotation).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert.equal(raster.info.channels, 4);
  const result = jsQR(new Uint8ClampedArray(raster.data), raster.info.width, raster.info.height, { inversionAttempts: 'dontInvert' });
  assert.ok(result, 'An independent decoder must read the actual generated SVG raster');
  return { result, raster };
}
function route(options: { data?: unknown; role?: string; capabilities?: CorporateCapability[]; anonymous?: boolean; authError?: Error; queryError?: boolean; renderError?: boolean } = {}) {
  const db = database(Object.hasOwn(options, 'data') ? options.data : project(), { error: options.queryError });
  const authCalls: unknown[] = [], imageCalls: string[] = [];
  const access = { client: db.client, user: { id: id(10) }, profile: { id: id(11), nome: 'Pessoa', perfil: options.role ?? 'administrador' },
    sso: { sessionHash: 'session-private', bindingId: id(12), subject: id(13), capabilities: options.capabilities ?? caps } } as NonNullable<Awaited<ReturnType<typeof getWebUser>>>;
  return { ...db, authCalls, imageCalls, handle: (pathId = id(1), query = '') => handleProjectQrImage(new Request(`https://em.example/api/web/projects/${pathId}/qr${query}`), pathId, {
    getWebUser: async required => { authCalls.push(required); if (options.authError) throw options.authError; return options.anonymous ? null : access; },
    renderQr: async value => { imageCalls.push(value); if (options.renderError) throw Error('private image details'); return renderProjectQrSvg(value); },
  }) };
}

test('QR identity has one canonical raw UUID and never accepts an alias, URL or corrected arbitrary text', async () => {
  assert.equal(projectQrValue(id(1).toUpperCase()), id(1));
  for (const invalid of ['', 'OS 014', 'legacy-bubble-id', ` ${id(1)}`, `${id(1)}\n`, `https://example.invalid/projeto/${id(1)}`,
    `em:projeto:${id(1)}`, `<svg>${id(1)}</svg>`, id(1).replaceAll('-', ''), null, [], {}]) {
    assert.throws(() => projectQrValue(invalid as string));
    await assert.rejects(renderProjectQrSvg(invalid as string));
  }
});

test('actual SVG QR roundtrips through an independent raster decoder at screen and print sizes and rotation', async () => {
  for (const value of [id(1), id(2), 'ffffffff-ffff-ffff-ffff-ffffffffffff']) {
    const svg = await renderProjectQrSvg(value);
    assert.match(svg, /^<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg" width="512" height="512"/);
    assert.doesNotMatch(svg, /<script|<foreignObject|<image|href=|xlink:|<style/i);
    for (const [width, rotation] of [[256, 0], [512, 90], [1024, 0]]) {
      const { result } = await decode(svg, width, rotation);
      assert.equal(result.data, value); assert.equal(result.binaryData.length, 36);
      assert.deepEqual(result.binaryData, Array.from(Buffer.from(value, 'utf8')));
    }
  }
});

test('generated QR keeps a four-module white quiet zone and deterministic black/white content without metadata', async () => {
  const svg = await renderProjectQrSvg(id(1));
  assert.equal(svg, await renderProjectQrSvg(id(1).toUpperCase()));
  assert.notEqual(svg, await renderProjectQrSvg(id(2)));
  const edge = Number(svg.match(/viewBox="0 0 (\d+) \d+"/)?.[1]); assert.ok(Number.isInteger(edge) && edge > 8);
  const { raster } = await decode(svg, edge * 8), stride = raster.info.width * 4;
  // The four modules surrounding the full matrix must be white, not cropped by the renderer.
  for (let y = 0; y < raster.info.height; y++) for (let x = 0; x < raster.info.width; x++) {
    const pos = y * stride + x * 4;
    const rgba = [...raster.data.subarray(pos, pos + 4)];
    assert.ok(rgba[3] === 255 && (rgba.slice(0, 3).every(v => v === 0) || rgba.slice(0, 3).every(v => v === 255)));
    if (x < 32 || y < 32 || x >= raster.info.width - 32 || y >= raster.info.height - 32) assert.deepEqual(rgba, [255, 255, 255, 255]);
  }
});

test('QR metadata is one exact JWT project query with explicit fields and original microsecond version', async () => {
  const value = { ...project(), id: id(1).toUpperCase(), nome: '  Nome preservado  ', descricao_equipamento: '["Motor legado"]' };
  const f = database(value), actual = await f.getProjectQr(id(1).toUpperCase());
  assert.deepEqual(actual, { ...value, id: id(1) }); assert.equal(actual!.updated_at, version);
  assert.deepEqual(f.calls, [{ table: 'rm_projetos', columns: 'id,numero,nome,descricao_equipamento,updated_at', key: 'id', value: id(1) }]);
  const receiving = { ...project(), numero: null, nome: null, descricao_equipamento: null };
  assert.deepEqual(await database(receiving).getProjectQr(id(1)), receiving);
});

test('QR metadata refuses malformed or foreign project bodies and never returns private extra columns', async () => {
  for (const patch of [{ id: id(2) }, { id: 'invalid' }, { numero: 14 }, { updated_at: 'yesterday' }, { updated_at: null },
    { nome: undefined }, { qrcode_url: 'https://private.invalid/old-image' }, { auth_user_id: id(99) }, { arquivo_nota_fiscal_url: 'private' }]) {
    await assert.rejects(database({ ...project(), ...patch }).getProjectQr(id(1)), /Não foi possível consultar/);
  }
});

test('QR metadata enforces current scopes before SQL and distinguishes a missing project from a failed query', async () => {
  for (const capabilities of [[], ['em.projects.manage'], ...caps.map(capability => caps.filter(value => value !== capability))] as CorporateCapability[][]) {
    const f = database(project(), { capabilities }); await assert.rejects(f.getProjectQr(id(1)), /Acesso não autorizado/); assert.equal(f.calls.length, 0);
  }
  const invalid = database(); assert.equal(await invalid.getProjectQr('invalid'), null); assert.equal(invalid.calls.length, 0);
  const missing = database(null); assert.equal(await missing.getProjectQr(id(1)), null); assert.equal(missing.calls.length, 1);
  for (const options of [{ error: true }, { thrown: true }]) await assert.rejects(database(project(), options).getProjectQr(id(1)), error => error instanceof Error && /Não foi possível consultar/.test(error.message) && !/private/.test(error.message));
});

test('QR image endpoint authenticates current identity and read capabilities before querying or rendering', async () => {
  const anonymous = route({ anonymous: true }); assert.equal((await anonymous.handle()).status, 401); assert.equal(anonymous.calls.length, 0);
  for (const role of ['cliente', 'operador', 'unknown']) {
    const f = route({ role }); assert.equal((await f.handle()).status, 403); assert.equal(f.calls.length, 0); assert.equal(f.imageCalls.length, 0);
  }
  for (const capabilities of [[], ['em.projects.manage'], ...caps.map(capability => caps.filter(value => value !== capability))] as CorporateCapability[][]) {
    const f = route({ capabilities }); assert.equal((await f.handle()).status, 403); assert.equal(f.calls.length, 0);
  }
  for (const role of ['administrador', 'padr_o', 'auditor']) {
    const f = route({ role }), response = await f.handle(); assert.equal(response.status, 200); assert.deepEqual(f.authCalls, [caps]); assert.deepEqual(f.imageCalls, [id(1)]);
  }
});

test('QR image endpoint permits only the exact optional download flag and a canonical UUID path', async () => {
  for (const query of ['?download=', '?download=0', '?download=true', '?download=1&download=1', '?file=other.svg', '?download=1&token=private']) {
    const f = route(); assert.equal((await f.handle(id(1), query)).status, 400); assert.equal(f.calls.length, 0); assert.equal(f.imageCalls.length, 0);
  }
  const f = route(); assert.equal((await f.handle('not-a-uuid')).status, 400); assert.equal(f.calls.length, 0);
});

test('QR inline and download responses are private, inert SVGs with a safe filename and identity-only decoded payload', async () => {
  for (const query of ['', '?download=1']) {
    const f = route({ data: { ...project(), numero: 'OS\r\nInjected: header', nome: '<svg><script>private customer</script></svg>', descricao_equipamento: 'https://private.invalid/credential' } });
    const response = await f.handle(id(1).toUpperCase(), query), svg = await response.text();
    assert.equal(response.status, 200); assert.equal((await decode(svg)).result.data, id(1));
    assert.doesNotMatch(svg, /private customer|credential|Injected/);
    assert.equal(response.headers.get('content-type'), 'image/svg+xml; charset=utf-8');
    assert.equal(response.headers.get('cache-control'), 'private, no-store'); assert.equal(response.headers.get('vary'), 'Cookie');
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff'); assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(response.headers.get('content-security-policy'), "default-src 'none'; sandbox");
    assert.equal(response.headers.get('content-disposition'), `${query ? 'attachment' : 'inline'}; filename="em-projeto-${id(1)}.svg"`);
  }
});

test('QR image endpoint keeps absence, authorization and temporary failures distinct without leaking internal errors', async () => {
  for (const [options, status] of [[{ data: null }, 404], [{ queryError: true }, 503], [{ data: { ...project(), id: id(2) } }, 503],
    [{ renderError: true }, 503], [{ authError: new CorporateAuthError('CORP_FORBIDDEN') }, 403],
    [{ authError: new CorporateAuthError('CORP_UNAUTHORIZED') }, 401]] as const) {
    const response = await route(options).handle(); assert.equal(response.status, status);
    assert.equal(response.headers.get('cache-control'), 'private, no-store'); assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
    const body = await response.json(); assert.equal(typeof body.error, 'string'); assert.doesNotMatch(JSON.stringify(body), /private|SQL|network|stack|session/);
  }
});
