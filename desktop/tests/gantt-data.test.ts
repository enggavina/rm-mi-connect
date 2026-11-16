import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import { createGanttData } from '../src/server/web/gantt-data';
import type { GanttFilters } from '../src/server/web/gantt-policy';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-11-16T18:03:24.123456+00:00';
const filters: GanttFilters = { project_id: null, cell_id: null, include_closed: false };
const caps: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.planning.manage', 'em.projects.read'];
function snapshot() {
  return { as_of: version, filters: { ...filters }, total: 2, complete: true,
    projects: [{ id: id(1), numero: 'OS atual', nome: 'Nome atual', updated_at: version, plan_version: 'a'.repeat(64), closed: false,
      planned_start: version, planned_end: version, contract_date: version, renegotiated_date: null, arquivo_url: 'private' }],
    cells: [{ id: id(2), nome: 'Oficina', private_field: 'private' }],
    items: [3, 4].map(n => ({ id: id(n), projeto_id: id(1), celula_id: id(2), numero_projeto: 'OS exportada', cliente_nome_export: 'Cliente exportado',
      celula_nome: 'Oficina', status: 'pendente', bloqueada: 'n_o', motivo_bloqueio: null, visibilidade: n === 3,
      prioridade: null, indice: n, posicao: n, responsavel_nome: null, data_inicio: version, data_limite: version,
      updated_at: version, can_edit: true, auth_user_id: 'private', form_answers: 'private' })),
    links: [{ projeto_id: id(1), predecessor_id: id(3), successor_id: id(4), lag_days: 0, private_field: 'private' }],
    baseline: null as any, private_snapshot: 'private',
  };
}
function fixture(capabilities: CorporateCapability[] | undefined = caps) {
  const calls: any[] = []; let value: any = snapshot(), error: any = null;
  let choices: any = [{ id: id(1), numero: 'OS', nome: 'Motor', email: 'private' }], count: number | null = 1;
  const client = {
    async rpc(name: string, args: any) { calls.push({ name, args }); return { data: value, error }; },
    from(table: string) {
      calls.push({ table }); const query: any = {
        select(columns: string, options: unknown) { calls.push({ columns, options }); return query; },
        or(term: string) { calls.push({ term }); return query; },
        order(field: string) { calls.push({ order: field }); return query; },
        async range(start: number, end: number) { calls.push({ start, end }); return { data: choices, count, error }; },
      }; return query;
    },
  } as unknown as SupabaseClient;
  return { calls, data: createGanttData(client, capabilities), set(next: any) { value = next; }, fail(next: any) { error = next; },
    choices(next: any, total: number | null) { choices = next; count = total; } };
}

test('Gantt rejects missing domain grants and project access before issuing any query', async () => {
  for (const permissions of [[], ['em.portal.read'], ['em.planning.read'], ['em.projects.read']] as CorporateCapability[][]) {
    const f = fixture(permissions); await assert.rejects(f.data.getGanttSnapshot(filters), /Acesso/); assert.deepEqual(f.calls, []);
  }
  const f = fixture(['em.portal.read', 'em.planning.read']);
  await assert.rejects(f.data.getGanttSnapshot({ ...filters, project_id: id(1), include_closed: true }), /Acesso/);
  await assert.rejects(f.data.listGanttProjects(), /Acesso/); assert.deepEqual(f.calls, []);
});

test('Gantt uses one complete RPC snapshot without fetching every project or silently returning one page', async () => {
  const f = fixture(); const value = await f.data.getGanttSnapshot(filters);
  assert.deepEqual(f.calls, [{ name: 'rm_web_gantt_snapshot_v1', args: { p_filters: filters } }]);
  assert.equal(value.items.length, 2); assert.equal(value.items[0].updated_at, version);
  assert.equal(value.projects[0].updated_at, version); assert.equal(value.projects[0].plan_version, 'a'.repeat(64));
  assert.equal(value.items[1].visibilidade, false); assert.equal(value.links[0].lag_days, 0);
  assert.ok(!/private|auth_user|form_answers|arquivo_url/.test(JSON.stringify(value)));
});

test('planning-only Gantt preserves operational export labels without exposing project detail or editing controls', async () => {
  const f = fixture(['em.portal.read', 'em.planning.read']); const value = await f.data.getGanttSnapshot(filters);
  assert.equal(value.projects[0].numero, 'OS exportada'); assert.equal(value.projects[0].nome, null);
  assert.equal(value.projects[0].contract_date, null); assert.equal(value.projects[0].planned_start, null); assert.equal(value.projects[0].planned_end, null);
  assert.ok(value.items.every(item => item.can_edit === false));
  const readOnly = await fixture(caps.filter(cap => cap !== 'em.planning.manage')).data.getGanttSnapshot(filters);
  assert.ok(readOnly.items.every(item => !item.can_edit)); assert.equal(readOnly.projects[0].nome, 'Nome atual');
});

test('Gantt rejects crossed scopes, inconsistent membership and counterfeit editable closed work', async () => {
  const f = fixture();
  for (const bad of [
    { ...snapshot(), filters: { ...filters, include_closed: true } },
    { ...snapshot(), total: 3 }, { ...snapshot(), items: [snapshot().items[0], snapshot().items[0]] },
    { ...snapshot(), projects: [] }, { ...snapshot(), cells: [] },
    { ...snapshot(), projects: [...snapshot().projects, snapshot().projects[0]] },
    { ...snapshot(), projects: [...snapshot().projects, { ...snapshot().projects[0], id: id(98) }] },
    { ...snapshot(), cells: [...snapshot().cells, { ...snapshot().cells[0], id: id(98) }] },
    { ...snapshot(), items: [{ ...snapshot().items[0], projeto_id: id(99) }, snapshot().items[1]] },
    { ...snapshot(), items: [{ ...snapshot().items[0], celula_id: id(99) }, snapshot().items[1]] },
    { ...snapshot(), projects: [{ ...snapshot().projects[0], closed: true }] },
    { ...snapshot(), items: [{ ...snapshot().items[0], status: 'finalizado' }, snapshot().items[1]] },
    { ...snapshot(), projects: [{ ...snapshot().projects[0], plan_version: 'invalid' }] },
  ]) { f.set(bad); await assert.rejects(f.data.getGanttSnapshot(filters), /Não foi possível/); }
  const project = { ...snapshot(), filters: { ...filters, project_id: id(99), include_closed: true } }; f.set(project);
  await assert.rejects(f.data.getGanttSnapshot(project.filters), /Não foi possível/);
  const cell = { ...snapshot(), filters: { ...filters, cell_id: id(99) } }; f.set(cell);
  await assert.rejects(f.data.getGanttSnapshot(cell.filters), /Não foi possível/);
});

test('Gantt links must connect unique members of the same returned project', async () => {
  const f = fixture();
  for (const patch of [{ predecessor_id: id(99) }, { successor_id: id(99) }, { successor_id: id(3) }, { projeto_id: id(99) }, { lag_days: -1 }, { lag_days: 1.5 }, { lag_days: 3651 }]) {
    f.set({ ...snapshot(), links: [{ ...snapshot().links[0], ...patch }] });
    await assert.rejects(f.data.getGanttSnapshot(filters), /Não foi possível/);
  }
  f.set({ ...snapshot(), links: [...snapshot().links, ...snapshot().links] }); await assert.rejects(f.data.getGanttSnapshot(filters), /Não foi possível/);
});

test('Gantt explicitly supports empty contexts and refuses a truncated oversized timeline', async () => {
  const f = fixture();
  f.set({ ...snapshot(), total: 2001, complete: false, items: [], projects: [], cells: [], links: [] });
  const overflow = await f.data.getGanttSnapshot(filters); assert.equal(overflow.complete, false); assert.equal(overflow.total, 2001); assert.deepEqual(overflow.items, []);
  for (const bad of [
    { ...snapshot(), total: 2001, complete: true },
    { ...snapshot(), total: 2001, complete: false },
    { ...snapshot(), total: 2000, complete: false, items: [], projects: [], cells: [], links: [] },
  ]) { f.set(bad); await assert.rejects(f.data.getGanttSnapshot(filters), /Não foi possível/); }
  const empty = { ...snapshot(), total: 0, items: [], links: [], projects: [], cells: [] }; f.set(empty);
  assert.equal((await f.data.getGanttSnapshot(filters)).total, 0);
  const projectFilters = { ...filters, project_id: id(1), include_closed: true };
  f.set({ ...empty, filters: projectFilters, projects: snapshot().projects });
  assert.equal((await f.data.getGanttSnapshot(projectFilters)).projects[0].id, id(1));
});

test('closed project history and baseline are read-only and only exposed in project context', async () => {
  const f = fixture(); const projectFilters = { ...filters, project_id: id(1), include_closed: true };
  const baseline = { id: id(20), label: 'Planejamento aprovado', created_at: version,
    items: [{ allocation_id: id(99), data_inicio: version, data_limite: version, private_info: 'private' }], private_info: 'private' };
  const value = { ...snapshot(), filters: projectFilters, projects: [{ ...snapshot().projects[0], closed: true }],
    items: snapshot().items.map(item => ({ ...item, can_edit: false, status: 'finalizado' })), baseline };
  f.set(value); const result = await f.data.getGanttSnapshot(projectFilters);
  assert.equal(result.baseline?.items[0].allocation_id, id(99)); // Baselines preserve stages removed since capture.
  assert.ok(!JSON.stringify(result).includes('private'));
  f.set({ ...snapshot(), baseline }); await assert.rejects(f.data.getGanttSnapshot(filters), /Não foi possível/);
  f.set({ ...value, baseline: { ...baseline, items: [...baseline.items, ...baseline.items] } });
  await assert.rejects(f.data.getGanttSnapshot(projectFilters), /Não foi possível/);
});

test('Gantt project selector queries only an explicit minimal page with sanitized search and real total', async () => {
  const f = fixture(); f.choices([{ id: id(1), numero: 'OS', nome: 'Motor', email: 'private' }], 70);
  const result = await f.data.listGanttProjects(' %OS,_(Motor) ', '2');
  assert.deepEqual(result, { items: [{ id: id(1), numero: 'OS', nome: 'Motor' }], total: 70, page: 2, page_size: 25 });
  assert.ok(f.calls.some(call => call.columns === 'id,numero,nome'));
  assert.ok(f.calls.some(call => call.term === 'numero.ilike.%OS Motor%,nome.ilike.%OS Motor%'));
  assert.ok(f.calls.some(call => call.start === 25 && call.end === 49));
  f.choices([], null); await assert.rejects(f.data.listGanttProjects(), /Não foi possível/);
});

test('invalid scope and unavailable upstream do not leak private failure details', async () => {
  const f = fixture();
  for (const input of [{ ...filters, project_id: id(1), cell_id: id(2) }, { ...filters, project_id: 'invalid' }, { ...filters, include_closed: 'true' }, { ...filters, actor_id: id(5) }]) {
    await assert.rejects(f.data.getGanttSnapshot(input as any), /Não foi possível/);
  }
  assert.deepEqual(f.calls, []);
  f.fail({ message: 'private backend details' });
  await assert.rejects(f.data.getGanttSnapshot(filters), error => error instanceof Error && !error.message.includes('private'));
  f.fail({ code: 'PT413', message: 'private oversized payload' });
  await assert.rejects(f.data.getGanttSnapshot(filters), /Selecione um projeto ou uma célula/);
});
