import test from 'node:test';
import assert from 'node:assert/strict';
import type { CatalogFilter, Operator, Row } from '../src/core/types';
import { parseProjectQr, projectQrContextCurrent, projectQrContextKey, readProjectQr, resolveProjectQr, type ProjectQrContext, type ProjectQrReader } from '../src/domain/project-qr';

const id = '12345678-1234-4abc-8def-123456789abc';
const other = '22345678-1234-4abc-8def-123456789abc';
const now = Date.parse('2026-10-30T12:00:00Z');
const operator: Operator = { operador_id: 'operator-a', matricula: '42', nome: 'Operador', perfil: 'mobile', perfil_assinante: [],
  celulas_vinculadas: [{ celula_id: 'cell-a', nome: 'Mecânica' }], cell_access_policy_version: 2,
  authenticated_at: '2026-10-30T10:00:00Z', token_expires_at: '2026-10-31T10:00:00Z' };
const cells: Row[] = [{ id: 'cell-a' }, { id: 'cell-b' }];
const project: Row = { id, numero: '1001', status_pcp: 'em_execucao' };
const allocation: Row = { id: 'allocation-a', projeto_id: id, celula_id: 'cell-a', visibilidade: true, retirada: false };
const context = (): ProjectQrContext => ({ ready: true, syncing: false, sessionUserId: 'tablet-owner', operator, cellId: 'cell-a', focused: true, catalogRevision: 7 });

function fixture() {
  let current = context();
  const calls: { table: string; filter?: CatalogFilter }[] = [];
  const catalog: Record<string, Row[]> = { rm_celulas: cells, rm_projetos: [project], rm_celulas_projeto: [allocation] };
  const reader: ProjectQrReader = {
    context: () => current, now: () => now,
    list: async (table, filter) => { calls.push({ table, filter }); return catalog[table]; },
  };
  return { reader, calls, catalog, change: (patch: Partial<ProjectQrContext>) => { current = { ...current, ...patch }; } };
}

test('accepts only the exact lowercase UUID encoded by the EM label', () => {
  assert.equal(parseProjectQr(id), id);
  for (const value of [null, undefined, 1001, '', '1001', '1660000000000x000000000000000000', id.toUpperCase(), ` ${id}`, `${id}\n`, `{${id}}`, `urn:uuid:${id}`, `https://example.com/projeto/${id}`, `https://example.com/?projeto=${id}`, '1234567812344abc8def123456789abc']) {
    assert.equal(parseProjectQr(value), null, String(value));
  }
});

test('decoded payload opens only the current cell using cached data, even offline and with pending work', async () => {
  const f = fixture();
  const work = Object.freeze({ online: false, pendingMutations: 2, receiving: Object.freeze({ projeto_id: other, qr: 'legacy', eventualidades: 'Preservar' }), queue: Object.freeze([{ actor_id: 'other-actor', params_json: '{"original":true}' }]) });
  const before = JSON.stringify(work);
  let unexpected = 0;
  Object.assign(f.reader, { sync: () => { unexpected++; }, saveLocal: () => { unexpected++; }, enqueue: () => { unexpected++; }, work });
  const result = await readProjectQr(id, f.reader);
  if (!result.ok) throw new Error(result.reason);
  assert.deepEqual(result.params, { celula: 'cell-a', projeto: id });
  assert.equal(projectQrContextCurrent(result.contextKey, f.reader.context(), now), true);
  assert.deepEqual(f.calls.map(call => call.table).sort(), ['rm_celulas', 'rm_celulas_projeto', 'rm_projetos']);
  assert.deepEqual(f.calls.find(call => call.table === 'rm_celulas_projeto')?.filter, { field: 'celula_id', value: 'cell-a' });
  assert.equal(unexpected, 0);
  assert.equal(JSON.stringify(work), before);
});

test('rejects legacy numbers and URLs before reading any catalog or attempting navigation', async () => {
  const f = fixture();
  for (const value of ['1001', `https://rm.miconnect.app.br/version-live/projeto_mobile/${id}`, id.toUpperCase()]) assert.equal((await readProjectQr(value, f.reader)).ok, false);
  assert.equal(f.calls.length, 0);
});

test('unknown, other-cell, hidden, withdrawn and closed projects have the same safe failure without metadata', async () => {
  const failures: string[] = [];
  for (const change of [
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_projetos = []; },
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_celulas_projeto = [{ ...allocation, celula_id: 'cell-b' }]; },
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_celulas_projeto = [{ ...allocation, visibilidade: false }]; },
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_celulas_projeto = [{ ...allocation, retirada: true }]; },
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_projetos = [{ ...project, data_real_de_entrega: '2026-10-29' }]; },
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_projetos = [{ ...project, status_pcp: 'cancelado' }]; },
    (f: ReturnType<typeof fixture>) => { f.catalog.rm_projetos = [{ ...project, status_pcp: 'finalizando_para_faturar' }]; },
  ]) {
    const f = fixture(); change(f); const result = await readProjectQr(id, f.reader);
    assert.equal(result.ok, false);
    if (result.ok) throw new Error('Unavailable project opened');
    failures.push(result.reason);
    assert.equal(result.reason.includes(id) || result.reason.includes('1001') || result.reason.includes('cell-b'), false);
  }
  assert.equal(new Set(failures).size, 1);
});

test('cell is never auto-selected from another allocation, including for an administrator', async () => {
  const f = fixture(); f.catalog.rm_celulas_projeto = [{ ...allocation, celula_id: 'cell-b' }];
  f.change({ operator: { ...operator, perfil: 'administrador', celulas_vinculadas: [] } });
  assert.equal((await readProjectQr(id, f.reader)).ok, false);
  f.change({ cellId: 'cell-b' });
  assert.equal((await readProjectQr(id, f.reader)).ok, true);
  f.change({ cellId: undefined });
  assert.equal((await readProjectQr(id, f.reader)).ok, false);
});

test('missing device session, operator, current grant/policy and expired identity fail before catalog reads', async () => {
  const patches: Partial<ProjectQrContext>[] = [
    { sessionUserId: null }, { operator: null }, { ready: false }, { focused: false }, { syncing: true }, { catalogRevision: -1 },
    { operator: { ...operator, celulas_vinculadas: [] } }, { operator: { ...operator, cell_access_policy_version: 1 } },
    { operator: { ...operator, token_expires_at: '2026-10-30T12:00:00Z' } },
    { operator: { ...operator, authenticated_at: '2026-10-29T12:00:00Z' } },
    { operator: { ...operator, token_expires_at: undefined } }, { operator: { ...operator, authenticated_at: 'invalid' } },
  ];
  for (const patch of patches) {
    const f = fixture(); f.change(patch);
    assert.equal((await readProjectQr(id, f.reader)).ok, false, JSON.stringify(patch));
    assert.equal(f.calls.length, 0);
  }
});

test('duplicate live allocations fail closed while historical withdrawn allocations do not create ambiguity', () => {
  assert.equal(resolveProjectQr(id, operator, 'cell-a', cells, [project], [allocation, { ...allocation, id: 'second' }]).ok, false);
  assert.equal(resolveProjectQr(id, operator, 'cell-a', cells, [project], [allocation, { ...allocation, id: 'retired', retirada: true }]).ok, true);
  assert.equal(resolveProjectQr(id, operator, 'cell-a', cells, [project], [allocation, { ...allocation, id: 'other-cell', celula_id: 'cell-b' }]).ok, true);
  assert.equal(resolveProjectQr(id, operator, 'cell-a', [...cells, cells[0]], [project], [allocation]).ok, false);
  assert.equal(resolveProjectQr(id, operator, 'cell-a', cells, [project, project], [allocation]).ok, false);
});

test('execution block keeps consultation through the same normal project journey', () => {
  const result = resolveProjectQr(id, operator, 'cell-a', cells, [project], [{ ...allocation, bloqueada: 'sim' }]);
  assert.deepEqual(result, { ok: true, params: { celula: 'cell-a', projeto: id } });
});

test('read failures return a recoverable message without raw database errors or a navigation target', async () => {
  const f = fixture(); f.reader.list = async () => { throw new Error('SECRET DB ROW / forbidden project'); };
  const result = await readProjectQr(id, f.reader);
  assert.equal(result.ok, false);
  assert.equal('params' in result, false);
  assert.match(result.ok ? '' : result.reason, /Tente novamente/);
  assert.equal(JSON.stringify(result).includes('SECRET'), false);
  f.reader.context = () => { throw new Error('broken local context'); };
  assert.equal((await readProjectQr(id, f.reader)).ok, false);
});

test('operator, owner, selected cell, permissions, focus, catalog and sync changes invalidate in-flight reads', async () => {
  const changes: Partial<ProjectQrContext>[] = [
    { operator: { ...operator, operador_id: 'operator-b' } }, { sessionUserId: 'another-owner' }, { cellId: 'cell-b' },
    { operator: { ...operator, celulas_vinculadas: [] } }, { operator: { ...operator, perfil: 'administrador' } },
    { focused: false }, { catalogRevision: 8 }, { syncing: true }, { ready: false },
  ];
  for (const patch of changes) {
    const f = fixture(); const original = f.reader.list;
    let release!: () => void; const wait = new Promise<void>(resolve => { release = resolve; });
    f.reader.list = async (table, filter) => { await wait; return original(table, filter); };
    const pending = readProjectQr(id, f.reader); f.change(patch); release();
    const result = await pending;
    assert.equal(result.ok, false, JSON.stringify(patch));
    assert.equal('params' in result, false);
  }
});

test('the final navigation guard also rejects changes after the async read returns', async () => {
  const f = fixture(); const result = await readProjectQr(id, f.reader);
  if (!result.ok) throw new Error(result.reason);
  const key = result.contextKey;
  assert.equal(projectQrContextCurrent(key, { ...f.reader.context(), operator: { ...operator, celulas_vinculadas: [] } }, now), false);
  assert.equal(projectQrContextCurrent(key, f.reader.context(), Date.parse(operator.token_expires_at!)), false);
  assert.equal(projectQrContextKey({ ...context(), operator: { ...operator, celulas_vinculadas: [...operator.celulas_vinculadas] } }), key);
});

test('frozen source catalogs remain unchanged after successful and failed resolutions', async () => {
  const f = fixture();
  for (const table of Object.keys(f.catalog)) f.catalog[table] = Object.freeze(f.catalog[table].map(row => Object.freeze({ ...row }))) as unknown as Row[];
  const before = JSON.stringify(f.catalog);
  assert.equal((await readProjectQr(id, f.reader)).ok, true);
  assert.equal((await readProjectQr(other, f.reader)).ok, false);
  assert.equal(JSON.stringify(f.catalog), before);
});
