// Run from the repository root: node desktop/node_modules/tsx/dist/cli.mjs --test tests/project-qr-contract.test.ts
// Decoder packages belong to desktop; this cross-app contract deliberately stays outside either deployment context.
import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from '../desktop/node_modules/sharp';
import jsQR from '../desktop/node_modules/jsqr';
import { renderProjectQrSvg } from '../desktop/src/server/web/project-qr-image';
import { parseProjectQr, projectQrContextCurrent, readProjectQr, type ProjectQrContext, type ProjectQrReader } from '../mobile/src/domain/project-qr';
import type { CatalogFilter, Operator, Row } from '../mobile/src/core/types';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const now = Date.parse('2026-10-30T12:00:00Z');
const operator: Operator = { operador_id: 'operator-a', matricula: '42', nome: 'Operador', perfil: 'mobile', perfil_assinante: [],
  celulas_vinculadas: [{ celula_id: 'cell-a', nome: 'Mecânica' }], cell_access_policy_version: 2,
  authenticated_at: '2026-10-30T10:00:00Z', token_expires_at: '2026-10-31T10:00:00Z' };
function fixture() {
  const context: ProjectQrContext = { ready: true, syncing: false, sessionUserId: 'tablet-owner', operator, cellId: 'cell-a', focused: true, catalogRevision: 7 };
  const catalog: Record<string, Row[]> = {
    rm_celulas: [{ id: 'cell-a' }, { id: 'cell-b' }],
    rm_projetos: [{ id: id(1), numero: '1001', status_pcp: 'em_execucao' }, { id: id(2), numero: '1002', status_pcp: 'em_execucao' }],
    rm_celulas_projeto: [{ id: 'allocation-a', projeto_id: id(1), celula_id: 'cell-a', visibilidade: true, retirada: false },
      { id: 'allocation-b', projeto_id: id(2), celula_id: 'cell-b', visibilidade: true, retirada: false }],
  };
  const calls: { table: string; filter?: CatalogFilter }[] = [];
  const reader: ProjectQrReader = { context: () => context, now: () => now,
    list: async (table, filter) => { calls.push({ table, filter }); return catalog[table]; } };
  return { context, catalog, calls, reader };
}
async function decodeLabel(projectId: string, width: number, rotation = 0) {
  const svg = await renderProjectQrSvg(projectId);
  const raster = await sharp(Buffer.from(svg)).resize(width, width).rotate(rotation).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const decoded = jsQR(new Uint8ClampedArray(raster.data), raster.info.width, raster.info.height, { inversionAttempts: 'dontInvert' });
  assert.ok(decoded, 'The independent decoder must read the generated SVG before mobile resolution');
  return decoded.data;
}

test('real web SVG decodes into the mobile current-cell journey without writes or synchronization', async () => {
  for (const [width, rotation] of [[256, 0], [512, 90], [1024, 0]]) {
    const value = await decodeLabel(id(1).toUpperCase(), width, rotation);
    assert.equal(value, id(1)); assert.equal(parseProjectQr(value), id(1));
    const f = fixture();
    const work = Object.freeze({ online: false, pendingMutations: 2,
      receiving: Object.freeze({ projeto_id: id(2), qr: 'legacy', eventualidades: 'Preservar' }),
      queue: Object.freeze([{ actor_id: 'other-actor', params_json: '{"original":true}' }]) });
    const before = JSON.stringify(work); let writes = 0;
    Object.assign(f.reader, { work, sync: () => { writes++; }, saveLocal: () => { writes++; }, enqueue: () => { writes++; } });
    const result = await readProjectQr(value, f.reader);
    assert.equal(result.ok, true);
    if (!result.ok) throw new Error(result.reason);
    assert.deepEqual(result.params, { celula: 'cell-a', projeto: id(1) });
    assert.equal(projectQrContextCurrent(result.contextKey, f.context, now), true);
    assert.deepEqual(f.calls.map(call => call.table).sort(), ['rm_celulas', 'rm_celulas_projeto', 'rm_projetos']);
    assert.deepEqual(f.calls.find(call => call.table === 'rm_celulas_projeto')?.filter, { field: 'celula_id', value: 'cell-a' });
    assert.equal(writes, 0); assert.equal(JSON.stringify(work), before);
  }
});

test('a genuine decoded label grants no access to another cell, an unavailable project or an ungranted cell', async () => {
  for (const projectId of [id(2), id(3)]) {
    const value = await decodeLabel(projectId, 512), f = fixture();
    assert.equal(parseProjectQr(value), projectId);
    const result = await readProjectQr(value, f.reader);
    assert.equal(result.ok, false);
    if (result.ok) throw new Error('An inaccessible label opened a project');
    assert.doesNotMatch(result.reason, /1001|1002|abcdefab|cell-b/);
    assert.equal(f.context.cellId, 'cell-a');
  }
  const f = fixture(); f.context.cellId = 'cell-b';
  assert.equal((await readProjectQr(await decodeLabel(id(2), 512), f.reader)).ok, false);
  assert.equal(f.calls.length, 0, 'An ungranted cell must fail before even consulting the catalog');
});
