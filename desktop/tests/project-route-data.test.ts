import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createProjectRouteData } from '../src/server/web/project-route-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
function route() {
  return { project: { id: id(1), numero: 'OS1', nome: 'Motor', status_pcp: null, data_real_de_entrega: null, updated_at: version, closed: false, arquivo_url: 'private' },
    route_version: 'a'.repeat(64), total: 3, complete: true,
    items: [{ id: id(2), celula_id: id(12), celula_nome: 'First', status: 'finalizado', visibilidade: false, indice: -1, updated_at: version },
      { id: id(3), celula_id: id(13), celula_nome: 'Second', status: null, visibilidade: true, indice: 8, updated_at: version },
      { id: id(4), celula_id: null, celula_nome: null, status: 'n_a', visibilidade: false, indice: null, updated_at: version }], private_snapshot: 'private' };
}
function fixture(caps: readonly CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.projects.read']) {
  let current: any = route(), error: any = null; const calls: any[] = [];
  const client = { async rpc(name: string, args: any) { calls.push({ name, args }); return { data: current, error }; } } as unknown as SupabaseClient;
  return { data: createProjectRouteData(client, caps), calls, set(value: any) { current = value; }, fail(value: any) { error = value; } };
}
test('route reader requires planning and project grants before any query', async () => {
  for (const caps of [[], ['em.planning.read', 'em.projects.read'], ['em.portal.read', 'em.planning.read'], ['em.portal.read', 'em.projects.read']] as CorporateCapability[][]) {
    const f = fixture(caps); await assert.rejects(f.data.getProjectRoute(id(1)), /Acesso/); assert.deepEqual(f.calls, []);
  }
});
test('route read is atomic, minimal and preserves closed/hidden/legacy allocations and exact revisions', async () => {
  const f = fixture(); const result = await f.data.getProjectRoute(id(1)); assert.ok(result);
  assert.equal(result.project.updated_at, version); assert.equal(result.items[0].updated_at, version);
  assert.deepEqual(result.items.map(item => item.indice), [-1, 8, null]); assert.equal(result.items[2].celula_id, null);
  assert.equal(result.items[0].status, 'finalizado'); assert.equal(result.items[0].visibilidade, false);
  assert.ok(!JSON.stringify(result).includes('private')); assert.deepEqual(f.calls, [{ name: 'rm_web_project_route_snapshot_v1', args: { p_project_id: id(1) } }]);
  for (const status of ['cancelado', 'finalizando_para_faturar']) { const closed = route(); closed.project.status_pcp = status as any; closed.project.closed = true; f.set(closed); assert.equal((await f.data.getProjectRoute(id(1)))?.project.closed, true); }
});
test('route read rejects crossed, duplicated, unordered, partial and falsely open snapshots', async () => {
  const f = fixture(); assert.equal(await f.data.getProjectRoute('invalid'), null); assert.deepEqual(f.calls, []);
  for (const corrupt of [{ ...route(), project: { ...route().project, id: id(9) } }, { ...route(), total: 4 },
    { ...route(), items: [...route().items, route().items[0]], total: 4 },
    { ...route(), items: [...route().items].reverse() }, { ...route(), project: { ...route().project, closed: true } },
    { ...route(), project: { ...route().project, status_pcp: 'cancelado', closed: false } },
    { ...route(), complete: false }, { ...route(), complete: true, total: 2001 }, { ...route(), complete: false, total: 2001 },
    { ...route(), route_version: null }]) { f.set(corrupt); await assert.rejects(f.data.getProjectRoute(id(1)), /Não foi possível/); }
  f.set({ ...route(), complete: false, total: 2001, items: [] }); const overflow = await f.data.getProjectRoute(id(1));
  assert.ok(overflow); assert.equal(overflow.complete, false); assert.deepEqual(overflow.items, []);
  f.set(null); assert.equal(await f.data.getProjectRoute(id(1)), null);
  f.fail({ message: 'private upstream error' }); await assert.rejects(f.data.getProjectRoute(id(1)), error => error instanceof Error && !error.message.includes('private'));
});
