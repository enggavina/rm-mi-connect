import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createWorkshopData } from '../src/server/web/workshop-data';
import { snapshotSchema } from '../src/components/workshop/domain/schema';

const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read'];
const id = '00000000-0000-4000-8000-000000000001';
const at = '2026-11-16T18:03:24.123456+00:00';
function snapshot() {
  return { as_of: at, project_count: 1, allocation_count: 0, cell_count: 0,
    projects: [{ id, numero: 'OFICINA-001', nome: 'Equipamento real do teste local', descricao_equipamento: 'Motor do cadastro', status_pcp: 'executando',
      chegada_do_equipamento: '2026-11-10T15:00:00Z', data_real_de_entrega: null, data_prevista_final: null, data_contratual: at, data_renegociada: null,
      cliente_nome: 'Cliente do cadastro', gestor_nome: null, equipamento_tipo: null, equipamento_descricao: null, fabricante: null, modelo: null,
      potencia: null, rotacao: null, numero_serie: null, equipment_binding: false }], allocations: [], cells: [] };
}
function fixture(caps: readonly CorporateCapability[] | undefined = capabilities) {
  const calls: { name: string; args: unknown }[] = [];
  let data: unknown = snapshot(), error: unknown = null, network: Error | null = null;
  const client = { async rpc(name: string, args?: unknown) {
    calls.push({ name, args }); if (network) throw network; return { data, error };
  } } as unknown as SupabaseClient;
  return { reader: createWorkshopData(client, caps), calls, setData: (value: unknown) => { data = value; },
    setError: (value: unknown) => { error = value; }, setNetwork: (value: Error) => { network = value; } };
}

test('workshop consultation independently requires portal, project and planning read capabilities before any RPC', async () => {
  for (const missing of capabilities) {
    const f = fixture(capabilities.filter(capability => capability !== missing));
    await assert.rejects(f.reader.getWorkshopSnapshot(), /não autorizado/); assert.deepEqual(f.calls, []);
  }
  const f = fixture([]); await assert.rejects(f.reader.getWorkshopSnapshot(), /não autorizado/); assert.deepEqual(f.calls, []);
});

test('workshop reader performs one authenticated projection and returns only validated Supabase data', async () => {
  const f = fixture(), input = snapshot() as any; input.secret = 'private marker'; input.projects[0].email = 'private marker'; f.setData(input);
  const output = await f.reader.getWorkshopSnapshot();
  assert.deepEqual(f.calls, [{ name: 'rm_web_workshop_snapshot_v1', args: undefined }]);
  assert.equal(output.source, 'supabase'); assert.equal(output.referenceAt, at); assert.equal(output.orders.length, 1);
  assert.equal(output.orders[0].code, 'OFICINA-001'); assert.equal(output.orders[0].client, 'Cliente do cadastro');
  assert.equal(output.orders[0].sourceUrl, `/projetos/${id}`); assert.deepEqual(output.resources, []);
  assert.equal(JSON.stringify(output).includes('private marker'), false);
});

test('the authenticated BFF includes a new receipt with null OS alongside existing numbered projects', async () => {
  const f = fixture(), input = snapshot();
  input.projects.push({ ...input.projects[0], id: '00000000-0000-4000-8000-000000000002', numero: null as any });
  input.project_count++; f.setData(input);
  const output = await f.reader.getWorkshopSnapshot();
  assert.equal(output.orders.length, 2); assert.equal(output.orders[0].code, 'OFICINA-001');
  assert.equal(output.orders[1].code, 'Recebimento sem OS');
  assert.equal(output.orders[1].sourceUrl, '/projetos/00000000-0000-4000-8000-000000000002');
  assert.equal(output.referenceAt, at); assert.equal(f.calls.length, 1);
});

test('ordinary RPC failure never exposes transport details or substitutes an example workshop', async () => {
  const f = fixture(); f.setError({ code: '42501', message: 'private diagnostic', details: 'private token', hint: 'private url' });
  await assert.rejects(f.reader.getWorkshopSnapshot(), error => error instanceof Error
    && error.message === 'Não foi possível consultar os dados da oficina.' && !error.message.includes('private'));
  assert.equal(f.calls.length, 1);
});

test('oversized projection is identified as a complete-read limit instead of a partial result', async () => {
  const f = fixture(); f.setError({ code: 'PT413', message: 'private allocation detail' });
  await assert.rejects(f.reader.getWorkshopSnapshot(), error => error instanceof Error
    && error.message === 'O conjunto da oficina excedeu o limite de leitura completa.');
});

test('network rejection is sanitized and never returns the previous successful result', async () => {
  const f = fixture(); const prior = await f.reader.getWorkshopSnapshot(); assert.equal(prior.orders.length, 1);
  f.setNetwork(new Error('private token and https://private.invalid/transport'));
  await assert.rejects(f.reader.getWorkshopSnapshot(), error => error instanceof Error
    && error.message === 'Não foi possível consultar os dados da oficina.');
  assert.equal(f.calls.length, 2);
});

test('malformed, partial and mismatched cohort payloads fail closed', async () => {
  const partial = snapshot(); partial.project_count = 2;
  const ended = snapshot(); ended.projects[0].status_pcp = 'cancelado';
  for (const data of [null, [], { orders: [] }, partial, ended]) {
    const f = fixture(); f.setData(data); await assert.rejects(f.reader.getWorkshopSnapshot(), /dados completos/);
  }
});

test('empty authorized cohort is explicit Supabase data with complete metadata', async () => {
  const f = fixture(); f.setData({ as_of: at, project_count: 0, allocation_count: 0, cell_count: 0, projects: [], allocations: [], cells: [] });
  const output = await f.reader.getWorkshopSnapshot(); assert.equal(output.source, 'supabase'); assert.equal(output.fetchedAt, at);
  assert.deepEqual(output.orders, []); assert.deepEqual(output.resources, []); assert.deepEqual(output.cells, []);
});

test('scoped workshop data retains the server-authorized layout through browser validation', async () => {
  const client = { rpc() { assert.fail('unexpected legacy workshop reader'); } } as unknown as SupabaseClient;
  for (const layout of ['bma', 'management'] as const) {
    const reader = createWorkshopData(client, capabilities, async (resource, args) => {
      assert.equal(resource, 'workshop_twin');
      assert.deepEqual(args, {});
      return { ...snapshot(), layout };
    });
    assert.equal(snapshotSchema.parse(await reader.getWorkshopSnapshot()).layout, layout);
  }
  const reader = createWorkshopData(client, capabilities, async () => snapshot());
  await assert.rejects(reader.getWorkshopSnapshot(), /planta autorizada/);
});
