import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createWebData } from '../src/server/web/data';
import { workshopReadCapabilities, type WorkshopRead } from '../src/server/web/workshop-read-policy';
import { readWorkshopOperations } from '../src/server/web/workshop-operation-reader';

const project = '06000000-0000-4000-8000-000000000001';
const cell = '06000000-0000-4000-8000-000000000002';
const client = {
  from() { assert.fail('unexpected unscoped relation'); },
  rpc() { assert.fail('unexpected unscoped RPC'); },
} as unknown as SupabaseClient;
const caps = ['em.portal.read', 'em.projects.read', 'em.planning.read'] as const;

test('project and planning lists rely on the scoped projection for rows, selectors and totals', async () => {
  const calls: unknown[] = [];
  const read: WorkshopRead = async (resource, args) => {
    calls.push([resource, args]);
    const projects = resource === 'project_list';
    return {
      rows: [{ id: project }], total: 1, page: 2, pageSize: projects ? 25 : 50,
      cells: [{ id: cell }], statuses: [], ...(projects ? { clients: [] } : { projects: [] }),
    };
  };
  const data = createWebData(client, caps, undefined, read);
  assert.equal((await data.listProjects({ q: ' abc%', cell, page: 2 })).cells[0].id, cell);
  assert.equal((await data.listPlanning({ q: ' xyz_', page: '2' })).total, 1);
  assert.deepEqual(calls, [
    ['project_list', { q: 'abc', status: null, client: null, cell, page: 2, planning: true }],
    ['planning_list', { q: 'xyz', status: null, cell: null, page: 2, project_details: true }],
  ]);
});

test('project not owned by the current workshop stops before related lookups', async () => {
  const calls: unknown[] = [];
  const data = createWebData(client, caps, undefined, async (resource, args) => { calls.push([resource, args]); return null; });
  assert.equal(await data.getProject(project), null);
  assert.equal(await data.getProject('invalid'), null);
  assert.deepEqual(calls, [['project_entry', { id: project, cells: true, documents: false }]]);
});

test('authority outage and divergent project identity fail closed', async () => {
  const outage = new Error('workshop authority unavailable');
  const data = createWebData(client, caps, undefined, async () => { throw outage; });
  for (const read of [() => data.getProject(project), () => data.listProjects(), () => data.listPlanning()]) {
    await assert.rejects(read, error => error === outage);
  }
  const divergent = createWebData(client, caps, undefined, async () => ({ project: { id: cell }, client: null, cells: [] }));
  await assert.rejects(divergent.getProject(project), /Não foi possível/);
});

test('operational permit capabilities reflect requested fields and filters', () => {
  assert.deepEqual(workshopReadCapabilities('project_list', { planning: false, cell: null }), ['em.portal.read', 'em.projects.read']);
  assert.ok(workshopReadCapabilities('project_list', { planning: false, cell }).includes('em.planning.read'));
  assert.ok(workshopReadCapabilities('project_entry', { documents: true }).includes('em.documents.read'));
  assert.ok(workshopReadCapabilities('planning_list', { project_details: true }).includes('em.projects.read'));
  assert.ok(workshopReadCapabilities('gantt_snapshot', { project_id: project }).includes('em.projects.read'));
  assert.ok(!workshopReadCapabilities('gantt_snapshot', { project_id: null, project_details: false }).includes('em.projects.read'));
});

test('production rollout is opt-in and the enabled reader requires an SSO context', async () => {
  const session = { client };
  const previous = process.env.EM_WORKSHOP_OPERATION_READS;
  try {
    delete process.env.EM_WORKSHOP_OPERATION_READS;
    assert.equal(await readWorkshopOperations(session), undefined);
    process.env.EM_WORKSHOP_OPERATION_READS = 'true';
    await assert.rejects(readWorkshopOperations(session), { code: 'WORKSHOP_FORBIDDEN' });
  } finally {
    if (previous === undefined) delete process.env.EM_WORKSHOP_OPERATION_READS;
    else process.env.EM_WORKSHOP_OPERATION_READS = previous;
  }
});
