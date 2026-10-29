import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createPcpData } from '../src/server/web/pcp-data';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-29T18:03:24.123456+00:00';
function queue() {
  return { cell: { id: id(1), nome: 'Oficina', updated_at: version, bubble_id: 'private' }, queue_version: 'a'.repeat(64), complete: true, total: 1,
    items: [{ id: id(2), projeto_id: id(3), celula_id: id(1), numero_projeto: 'OS1', cliente_nome_export: 'Cliente exportado', tipo_equipamento_nome_export: null,
      status: 'pendente', bloqueada: 'n_o', motivo_bloqueio: null, visibilidade: false, prioridade: null, indice: -1, posicao: null,
      horas_previstas: null, horas_realizadas: '0.00', data_inicio: null, data_limite: null, responsavel_id: null, responsavel_nome: null,
      updated_at: version, project: { arquivo_nota_fiscal_url: 'https://private.invalid' }, bubble_id: 'private', modified_by_id: 'private' }],
    private_metadata: 'private' };
}
function load() {
  return { as_of: version, cells: [{ id: id(1), nome: 'Oficina', open_allocations: 2, visible_allocations: 1, hidden_allocations: 1,
    blocked_allocations: 1, overdue_allocations: 0, estimated_allocations: 0, unestimated_allocations: 2, planned_hours: null, realized_hours: null,
    available_hours: 'private', occupancy_percentage: 'private' }] };
}
function receiving() {
  return { items: [{ id: id(3), numero: 'OS1', nome: 'Motor', cliente_id: null, cliente_nome_exportacao: 'Cliente exportado', cliente_nome: null,
    descricao_equipamento: 'Descrição', chegada_do_equipamento: null, nota_fiscal: 'NF1', tipo_equipamento_id: null, tipo_equipamento_nome: null,
    status_pcp: 'equipamento_em_inspe__o', updated_at: version, allocation_count: 1,
    reasons: ['without_type', 'awaiting_arrival', 'legacy_type_locked'], arquivo_nota_fiscal_url: 'https://private.invalid', auth_user_id: 'private' }],
    total: 1, page: 1, page_size: 25, summary: { without_number: 0, without_type: 4, without_allocation: 3, awaiting_arrival: 2, legacy_type_locked: 3 } };
}
function fixture(capabilities: readonly CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.projects.read']) {
  const calls: { name: string; args?: unknown }[] = []; let currentQueue: any = queue(), currentLoad: any = load(), currentReceiving: any = receiving(), error: any = null;
  let cells: any[] = [];
  const client = {
    async rpc(name: string, args?: any) {
      calls.push({ name, args });
      return { data: name === 'rm_web_cell_queue_snapshot_v1' ? currentQueue : name === 'rm_web_planning_load_v1' ? currentLoad : currentReceiving, error };
    },
    from(table: string) {
      calls.push({ name: table }); const query: any = { select(columns: string) { calls.push({ name: 'select', args: columns }); return query; }, order() { return query; },
        async range(from: number, to: number) { return { data: cells.slice(from, to + 1), error }; } }; return query;
    },
  };
  return { calls, data: createPcpData(client as unknown as SupabaseClient, capabilities), queue(value: any) { currentQueue = value; },
    load(value: any) { currentLoad = value; }, receiving(value: any) { currentReceiving = value; }, error(value: any) { error = value; }, cells(value: any[]) { cells = value; } };
}

test('PCP reads keep planning and project capabilities independent and fail before any unauthorized query', async () => {
  for (const caps of [[], ['em.planning.read'], ['em.portal.read'], ['em.portal.read', 'em.projects.read']] as CorporateCapability[][]) {
    const f = fixture(caps); await assert.rejects(f.data.getCellQueue(id(1)), /Acesso/); await assert.rejects(f.data.getPlanningLoad(), /Acesso/); await assert.rejects(f.data.getPcpChoices(), /Acesso/);
    assert.deepEqual(f.calls, []);
  }
  const planning = fixture(['em.portal.read', 'em.planning.read']); await assert.rejects(planning.data.listReceiving(), /Acesso/); assert.deepEqual(planning.calls, []);
  const projects = fixture(['em.portal.read', 'em.projects.read']); assert.equal((await projects.data.listReceiving()).total, 1);
  assert.deepEqual(projects.calls.map(call => call.name), ['rm_web_receivings_v1']);
});

test('cell queue returns a complete atomic export-only snapshot with exact versions and legacy positions', async () => {
  const f = fixture(['em.portal.read', 'em.planning.read']); const result = await f.data.getCellQueue(id(1)); assert.ok(result);
  assert.equal(result.queue_version, 'a'.repeat(64)); assert.equal(result.cell.updated_at, version); assert.equal(result.items[0].updated_at, version);
  assert.equal(result.items[0].posicao, null); assert.equal(result.items[0].indice, -1); assert.equal(result.items[0].visibilidade, false);
  assert.equal(result.items[0].horas_previstas, null); assert.equal(result.items[0].horas_realizadas, '0.00');
  assert.ok(!/private|bubble_id|project"|modified_by/.test(JSON.stringify(result)));
  assert.deepEqual(f.calls, [{ name: 'rm_web_cell_queue_snapshot_v1', args: { p_cell_id: id(1) } }]);
});

test('queue cannot silently accept partial, duplicated, crossed or concluded allocation snapshots', async () => {
  const f = fixture(); assert.equal(await f.data.getCellQueue('invalid'), null); assert.deepEqual(f.calls, []);
  for (const corrupt of [
    { ...queue(), cell: { ...queue().cell, id: id(9) } }, { ...queue(), total: 2 },
    { ...queue(), items: [queue().items[0], queue().items[0]], total: 2 },
    { ...queue(), items: [{ ...queue().items[0], celula_id: id(9) }] },
    { ...queue(), items: [{ ...queue().items[0], status: 'finalizado' }] },
    { ...queue(), complete: false, total: 2001 }, { ...queue(), complete: false, items: [] },
    { ...queue(), queue_version: null },
  ]) { f.queue(corrupt); await assert.rejects(f.data.getCellQueue(id(1)), /Não foi possível/); }
  f.queue({ ...queue(), items: [], total: 2001, complete: false });
  const overflow = await f.data.getCellQueue(id(1)); assert.ok(overflow); assert.equal(overflow.complete, false); assert.deepEqual(overflow.items, []);
  f.queue(null); assert.equal(await f.data.getCellQueue(id(1)), null);
});

test('load preserves unknown and real zero estimates without fabricating capacity or summing partial pages', async () => {
  const f = fixture(); const unknown = await f.data.getPlanningLoad(); assert.equal(unknown.cells[0].planned_hours, null);
  assert.ok(!/private|capacity|occupancy|available/.test(JSON.stringify(unknown)));
  const known = load(); Object.assign(known.cells[0], { estimated_allocations: 1, unestimated_allocations: 1, planned_hours: '0.00' });
  f.load(known); assert.equal((await f.data.getPlanningLoad()).cells[0].planned_hours, '0.00');
  Object.assign(known.cells[0], { planned_hours: '123456789.01' }); f.load(known);
  assert.equal((await f.data.getPlanningLoad()).cells[0].planned_hours, '123456789.01');
  assert.ok(f.calls.every(call => call.name === 'rm_web_planning_load_v1'));
  for (const corrupt of [
    { ...load(), cells: [...load().cells, ...load().cells] },
    { ...load(), cells: [{ ...load().cells[0], visible_allocations: 3 }] },
    { ...load(), cells: [{ ...load().cells[0], planned_hours: '0.00' }] },
    { ...load(), cells: [{ ...load().cells[0], estimated_allocations: 1, unestimated_allocations: 1 }] },
  ]) { f.load(corrupt); await assert.rejects(f.data.getPlanningLoad(), /Não foi possível/); }
});

test('receiving triage uses exact reasons, real server totals and a global overlapping summary without media URLs', async () => {
  const f = fixture(); const raw = receiving(); raw.page = 2; f.receiving(raw);
  const result = await f.data.listReceiving({ reason: 'legacy_type_locked', q: ' %OS1,_(Motor) ', page: '2' });
  assert.equal(result.page, 2); assert.equal(result.total, 1); assert.equal(result.summary.without_type, 4);
  assert.equal(result.items[0].allocation_count, 1); assert.ok(result.items[0].reasons.includes('awaiting_arrival'));
  assert.ok(!/private|arquivo_nota|auth_user/.test(JSON.stringify(result)));
  assert.deepEqual(f.calls, [{ name: 'rm_web_receivings_v1', args: { p_reason: 'legacy_type_locked', p_search: 'OS1 Motor', p_page: 2, p_page_size: 25 } }]);
  const before = f.calls.length; await assert.rejects(f.data.listReceiving({ reason: 'unknown' as any }), /Não foi possível/); assert.equal(f.calls.length, before);
});

test('receiving cannot relabel arrived, classified or allocated projects, broaden a reason filter, or show closed projects', async () => {
  const f = fixture();
  for (const corrupt of [
    { ...receiving(), items: [{ ...receiving().items[0], reasons: ['without_allocation'] }] },
    { ...receiving(), items: [{ ...receiving().items[0], chegada_do_equipamento: version }] },
    { ...receiving(), items: [{ ...receiving().items[0], tipo_equipamento_id: id(10) }] },
    { ...receiving(), items: [{ ...receiving().items[0], allocation_count: 0 }] },
    { ...receiving(), items: [{ ...receiving().items[0], status_pcp: 'cancelado' }] },
    { ...receiving(), items: [...receiving().items, ...receiving().items], total: 2 },
  ]) { f.receiving(corrupt); await assert.rejects(f.data.listReceiving(), /Não foi possível/); }
  f.receiving(receiving()); await assert.rejects(f.data.listReceiving({ reason: 'without_number' }), /Não foi possível/);
});

test('PCP reference choices are minimal and complete past one server page, and upstream errors stay sanitized', async () => {
  const f = fixture(); f.cells(Array.from({ length: 501 }, (_, n) => ({ id: id(1000 + n), nome: `Cell ${n}`, email: 'private' })));
  const choices = await f.data.getPcpChoices(); assert.equal(choices.cells.length, 501); assert.ok(!JSON.stringify(choices).includes('private'));
  assert.deepEqual(f.calls.filter(call => call.name === 'select').map(call => call.args), ['id,nome', 'id,nome']);
  f.error({ message: 'private upstream detail' });
  for (const operation of [() => f.data.getCellQueue(id(1)), () => f.data.getPlanningLoad(), () => f.data.listReceiving(), () => f.data.getPcpChoices()]) {
    await assert.rejects(operation(), error => error instanceof Error && !error.message.includes('private'));
  }
});
