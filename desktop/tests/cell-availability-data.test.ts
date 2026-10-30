import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createCellAvailabilityData } from '../src/server/web/cell-availability-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T14:02:10.123456+00:00';
const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read'];
function snapshot() {
  return { project: { id: id(1), numero: 'OS1', status_pcp: null as string | null, data_real_de_entrega: null as string | null, updated_at: version, closed: false, arquivo_url: 'private-file' },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(3), celula_nome: 'Peritagem', status: 'pendente' as string | null,
      visibilidade: true, retirada: false, indice: 1.25, posicao: null, prioridade: 'alta', updated_at: version, forms_ids: ['private-child'], auth_user_id: 'private-auth' },
    can_set_visibility: true, can_retire: true, can_restore: false, visibility_reason: null, retire_reason: null, restore_reason: null, in_queue: true,
    context_version: 'a'.repeat(64), private_data: 'private', children: [{ id: 'private-child' }] };
}
function fixture(caps: readonly CorporateCapability[] = capabilities) {
  let current: unknown = snapshot(), error: unknown = null, thrown = false; const calls: { name: string; args: unknown }[] = [];
  const client = { async rpc(name: string, args: unknown) { calls.push({ name, args }); if (thrown) throw new Error('private-upstream'); return { data: current, error }; } } as unknown as SupabaseClient;
  return { reader: createCellAvailabilityData(client, caps), calls, set(value: unknown) { current = value; }, fail() { error = { message: 'private-upstream' }; }, throw() { thrown = true; } };
}

test('availability reads require only the independent project/planning read grants before any query', async () => {
  for (const missing of capabilities) {
    const f = fixture(capabilities.filter(capability => capability !== missing));
    await assert.rejects(f.reader.getCellAvailability(id(1), id(2)), /Acesso/); assert.deepEqual(f.calls, []);
  }
  const f = fixture(); assert.equal(await f.reader.getCellAvailability('invalid', id(2)), null); assert.deepEqual(f.calls, []);
  assert.ok(await f.reader.getCellAvailability(id(1), id(2)));
});

test('one availability snapshot preserves exact revisions and historical positions without transporting child or identity data', async () => {
  const f = fixture(), result = await f.reader.getCellAvailability(id(1), id(2)); assert.ok(result);
  assert.equal(result.project.updated_at, version); assert.equal(result.allocation.updated_at, version); assert.equal(result.allocation.indice, 1.25); assert.equal(result.allocation.posicao, null);
  assert.equal(result.in_queue, true); assert.ok(!JSON.stringify(result).includes('private')); assert.ok(!('forms_ids' in result.allocation));
  assert.deepEqual(f.calls, [{ name: 'rm_web_cell_availability_snapshot_v1', args: { p_project_id: id(1), p_allocation_id: id(2) } }]);
  const hidden = snapshot(); hidden.allocation.visibilidade = false; f.set(hidden);
  assert.equal((await f.reader.getCellAvailability(id(1), id(2)))?.in_queue, true, 'Hidden active work remains in the planning queue.');
  f.set({ ...snapshot(), allocation: { ...snapshot().allocation, retirada: true, visibilidade: false }, can_set_visibility: false, can_retire: false, can_restore: true, in_queue: false });
  assert.equal((await f.reader.getCellAvailability(id(1), id(2)))?.can_restore, true);
});

test('crossed context, visible retired allocations, impossible permissions and incorrect queue membership fail closed', async () => {
  const f = fixture();
  const cases: unknown[] = [
    { ...snapshot(), project: { ...snapshot().project, id: id(99) } }, { ...snapshot(), allocation: { ...snapshot().allocation, id: id(99) } },
    { ...snapshot(), allocation: { ...snapshot().allocation, projeto_id: id(99) } }, { ...snapshot(), context_version: 'invalid' },
    { ...snapshot(), allocation: { ...snapshot().allocation, retirada: true } }, { ...snapshot(), can_restore: true }, { ...snapshot(), in_queue: false },
    { ...snapshot(), allocation: { ...snapshot().allocation, status: 'finalizado' } },
    { ...snapshot(), project: { ...snapshot().project, status_pcp: 'cancelado', closed: true }, in_queue: false },
    { ...snapshot(), project: { ...snapshot().project, closed: true } },
  ];
  for (const value of cases) { f.set(value); await assert.rejects(f.reader.getCellAvailability(id(1), id(2)), /Não foi possível/); }
  f.set({ ...snapshot(), allocation: { ...snapshot().allocation, status: 'finalizado' }, can_retire: false, in_queue: false });
  assert.equal((await f.reader.getCellAvailability(id(1), id(2)))?.can_set_visibility, true, 'Visibility eligibility is authoritative even for completed work awaiting approvals.');
});

test('not-found and unavailable availability responses never expose upstream error contents', async () => {
  const f = fixture(); f.set(null); assert.equal(await f.reader.getCellAvailability(id(1), id(2)), null);
  f.fail(); await assert.rejects(f.reader.getCellAvailability(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
  const throws = fixture(); throws.throw(); await assert.rejects(throws.reader.getCellAvailability(id(1), id(2)), error => error instanceof Error && !error.message.includes('private'));
});
