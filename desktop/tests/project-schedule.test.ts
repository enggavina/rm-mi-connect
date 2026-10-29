import assert from 'node:assert/strict';
import test from 'node:test';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createProjectScheduleData } from '../src/server/web/project-schedule-data';
import { allocationRecords, allocationStage, orderedProjectAllocations, scheduleHref, scheduleId, scheduleTab, scheduleView, selectedAllocation } from '../src/server/web/project-schedule-policy';
import type { CorporateCapability } from '../src/server/web/sso-policy';
import type { StageApprovalListItem } from '../src/server/web/stage-approval-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const timestamp = '2026-10-29T15:00:00.123456+00:00';
const project = id(1), cell = id(2), allocation = id(3);
const capabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.photos.read', 'em.approvals.read'];
type Row = Record<string, any>;
class Fixture {
  tables = new Map<string, Row[]>();
  calls: { table: string; columns: string; filters: [string, string, any][]; range?: [number, number] }[] = [];
  stageItems: StageApprovalListItem[] = [];
  rpcCalls: Record<string, any>[] = [];
  from(table: string) { return new Query(this, table); }
  async rpc(name: string, args: Record<string, any>) {
    assert.equal(name, 'rm_web_stage_approvals_v1');
    this.rpcCalls.push(args);
    const rows = this.stageItems.filter(item => item.stage.projeto_id === args.p_project_id && item.stage.celula_origem_id === args.p_cell_id);
    return { error: null, data: { items: rows.slice((args.p_page - 1) * args.p_page_size, args.p_page * args.p_page_size), total: rows.length, page: args.p_page, page_size: args.p_page_size } };
  }
}
class Query {
  columns = ''; filters: [string, string, any][] = []; bounds?: [number, number]; single = false;
  orders: [string, { ascending?: boolean; nullsFirst?: boolean }][] = [];
  constructor(readonly db: Fixture, readonly table: string) {}
  select(columns: string, _options?: unknown) { this.columns = columns; return this; }
  eq(key: string, value: unknown) { this.filters.push(['eq', key, value]); return this; }
  neq(key: string, value: unknown) { this.filters.push(['neq', key, value]); return this; }
  not(key: string, _operator: string, value: unknown) { return this.neq(key, value); }
  in(key: string, values: unknown[]) { this.filters.push(['in', key, values]); return this; }
  or(value: string) { this.filters.push(['or', 'celula_projeto_id', value.split(',')[0].split('.').at(-1)]); return this; }
  order(key: string, options: { ascending?: boolean; nullsFirst?: boolean } = {}) { this.orders.push([key, options]); return this; }
  range(start: number, end: number) { this.bounds = [start, end]; return this; }
  maybeSingle() { this.single = true; return this; }
  async then(resolve: (value: unknown) => unknown) {
    this.db.calls.push({ table: this.table, columns: this.columns, filters: this.filters, range: this.bounds });
    let rows = (this.db.tables.get(this.table) || []).filter(row => this.filters.every(([operation, key, value]) =>
      operation === 'eq' ? row[key] === value : operation === 'neq' ? row[key] !== value : operation === 'in' ? value.includes(row[key]) : row[key] === value || row[key] === null));
    rows = rows.slice().sort((a, b) => {
      for (const [key, options] of this.orders) {
        if (a[key] === b[key]) continue;
        if (a[key] === null) return options.nullsFirst === false ? 1 : -1;
        if (b[key] === null) return options.nullsFirst === false ? -1 : 1;
        const difference = a[key] < b[key] ? -1 : 1;
        return options.ascending === false ? -difference : difference;
      }
      return 0;
    });
    const count = rows.length;
    if (this.bounds) rows = rows.slice(this.bounds[0], this.bounds[1] + 1);
    const result = rows.map(row => Object.fromEntries(this.columns.split(',').map(column => [column, row[column]])));
    return resolve({ error: null, data: this.single ? result[0] || null : result, count });
  }
}
function setup(caps: CorporateCapability[] = capabilities) {
  const db = new Fixture();
  db.tables.set('rm_celulas_projeto', [{ id: allocation, projeto_id: project, celula_id: cell }]);
  return { db, reader: createProjectScheduleData(db as unknown as SupabaseClient, caps) };
}
function stage(n: number, link: string | null = allocation): StageApprovalListItem {
  return {
    stage: { id: id(n), projeto_id: project, celula_projeto_id: link, celula_origem_id: cell, celula_destino_id: null,
      status: null, status_cel_proj: 'finalizado', bloquear_avanco_sem_aprov: true, aprovador_id: null, aprovadores_ids: [],
      aprovadores_retorno_ids: [], aprovado_por_id: null, data_aprovacao: null, created_at: timestamp, updated_at: timestamp },
    allocation: null, project: null, origin: { id: cell, nome: 'Célula' }, destination: null, available_actions: [], action_reason: null,
  };
}

test('schedule preserves Gantt access and old filters while project selection uses independent IDs', () => {
  assert.equal(scheduleView({}, true), 'project');
  assert.equal(scheduleView({}, false), 'gantt');
  assert.equal(scheduleView({ start: '2026-10-29' }, true), 'gantt');
  assert.equal(scheduleView({ cell, status: 'pendente' }, true), 'gantt');
  assert.equal(scheduleView({ project, view: 'project', start: '2026-10-29' }, true), 'project');
  assert.equal(scheduleView({ project, view: 'gantt' }, true), 'gantt');
  const changed = new URL(scheduleHref(id(9)), 'https://em.test');
  assert.equal(changed.searchParams.get('project'), id(9));
  assert.equal(changed.searchParams.has('allocation'), false);
  assert.equal(scheduleHref('invalid', allocation), '/cronograma?view=project');
  const upper = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
  assert.equal(scheduleId(upper), upper.toLowerCase());
  assert.ok(scheduleHref(upper).includes(upper.toLowerCase()));
  assert.equal(scheduleTab('etapas', ['fotos', 'formularios']), 'fotos');
  assert.equal(scheduleTab('fotos', []), undefined);
});

test('project route ordering is independent from queue position and rejects allocations from another project', () => {
  const rows = [
    { id: id(12), projeto_id: project, indice: 2, posicao: 1 },
    { id: id(11), projeto_id: project, indice: 1, posicao: 99 },
    { id: id(10), projeto_id: project, indice: 1, posicao: 100 },
    { id: id(13), projeto_id: project, indice: null, posicao: 0 },
    { id: id(14), projeto_id: id(8), indice: 0, posicao: 0 },
  ];
  assert.deepEqual(orderedProjectAllocations(rows, project).map(row => row.id), [id(10), id(11), id(12), id(13)]);
  assert.equal(rows[0].id, id(12));
  assert.equal(selectedAllocation(rows, project, id(14)), undefined);
  assert.equal(selectedAllocation(rows, project, id(11))?.id, id(11));
  const current = { id: allocation, projeto_id: project, celula_id: cell };
  assert.deepEqual(allocationRecords([{ id: id(1), projeto_id: project, celula_id: cell }, { id: id(2), projeto_id: id(8), celula_id: cell }, { id: id(3), projeto_id: project, celula_id: id(8) }], current).map(row => row.id), [id(1)]);
  assert.equal(allocationStage(stage(1), current), true);
  assert.equal(allocationStage(stage(2, null), current), true);
  assert.equal(allocationStage(stage(3, id(8)), current), false);
});

test('changing project cannot reuse a stale allocation or query its stages', async () => {
  const { db, reader } = setup();
  assert.equal(await reader.stages(id(8), allocation), null);
  assert.equal(db.rpcCalls.length, 0);
  const before = db.calls.length;
  assert.equal(await reader.stages('invalid', allocation), null);
  assert.equal(db.calls.length, before);
});

test('reader refuses missing capabilities before operational queries', async () => {
  const { db, reader } = setup(['em.portal.read', 'em.projects.read', 'em.planning.read']);
  await assert.rejects(reader.stages(project, allocation), /Acesso/);
  assert.equal(db.calls.length, 0);
  assert.equal(db.rpcCalls.length, 0);
  const missingProject = setup(['em.portal.read', 'em.planning.read', 'em.approvals.read']);
  await assert.rejects(missingProject.reader.stages(project, allocation), /Acesso/);
  assert.equal(missingProject.db.calls.length, 0);
});

test('stages paginate only the current allocation and legacy null links using the existing RPC', async () => {
  const { db, reader } = setup();
  db.stageItems = [...Array.from({ length: 30 }, (_, i) => stage(100 + i)), stage(200, null), stage(201, id(9))];
  const first = await reader.stages(project, allocation);
  const second = await reader.stages(project, allocation, 2);
  assert.equal(first?.total, 31);
  assert.equal(first?.items.length, 25);
  assert.equal(second?.items.length, 6);
  assert.ok(second?.items.some(item => item.stage.celula_projeto_id === null));
  assert.ok(![...first!.items, ...second!.items].some(item => item.stage.celula_projeto_id === id(9)));
  assert.ok(db.rpcCalls.every(call => call.p_project_id === project && call.p_cell_id === cell && call.p_state === 'all'));
});
