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
  assert.deepEqual(calls, [['project_detail', {
    id: project, planning: true, forms: false, photos: false, history: false, documents: false, equipment: true, dossier: true,
    edit: false, photo_page: 1, selected_only: false, selected_first: false,
  }]]);
});

test('planning uses the corporate workshop reader even before the general rollout', async () => {
  const planningCaps = ['em.portal.read', 'em.planning.read'] as const;
  const data = createWebData(client, planningCaps, async (resource, args) => {
    assert.equal(resource, 'planning_list');
    assert.deepEqual(args, { q: 'OS', status: 'pendente', cell, page: 2, project_details: false });
    return { rows: [], total: 0, page: 2, pageSize: 50, projects: [], cells: [], statuses: [] };
  });
  assert.deepEqual(await data.listPlanning({ q: 'OS', status: 'pendente', cell, page: 2 }), {
    rows: [], total: 0, page: 2, pageSize: 50, projects: [], cells: [], statuses: [],
  });

  const outage = new Error('workshop authority unavailable');
  const unavailable = createWebData(client, planningCaps, async () => { throw outage; });
  await assert.rejects(unavailable.listPlanning(), error => error === outage);
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
  assert.deepEqual(workshopReadCapabilities('project_detail', { forms: true, photos: true, edit: true }),
    ['em.portal.read', 'em.projects.read', 'em.forms.read', 'em.photos.read', 'em.projects.manage']);
  assert.ok(workshopReadCapabilities('planning_list', { project_details: true }).includes('em.projects.read'));
  assert.ok(workshopReadCapabilities('gantt_snapshot', { project_id: project }).includes('em.projects.read'));
  assert.ok(!workshopReadCapabilities('gantt_snapshot', { project_id: null, project_details: false }).includes('em.projects.read'));
  assert.deepEqual(workshopReadCapabilities('form_record_project'), ['em.portal.read', 'em.forms.read']);
  assert.deepEqual(workshopReadCapabilities('form_record_detail', { projects: true, documents: true }),
    ['em.portal.read', 'em.forms.read', 'em.projects.read', 'em.documents.read']);
  assert.ok(workshopReadCapabilities('form_record_list', { project_details: true }).includes('em.projects.read'));
});

test('form record denies direct foreign IDs and propagates context failures before reading responses', async () => {
  const formCaps = ['em.portal.read', 'em.forms.read'] as const;
  const calls: unknown[] = [];
  const notOwned = createWebData(client, formCaps, undefined, async (resource, args) => { calls.push([resource, args]); return null; });
  assert.equal(await notOwned.getRecord(project), null);
  assert.equal(await notOwned.getRecord('invalid'), null);
  assert.deepEqual(calls, [['form_record_detail', { id: project, projects: false, documents: false, photos: false }]]);
  const outage = new Error('workshop authority unavailable');
  const unavailable = createWebData(client, formCaps, undefined, async () => { throw outage; });
  await assert.rejects(unavailable.getRecord(project), error => error === outage);
  const invalid = createWebData(client, formCaps, undefined, async () => ({ project_id: project, form_id: cell }));
  await assert.rejects(invalid.getRecord(project), /Não foi possível/);
});

test('project detail and gallery need only one workshop snapshot, retaining filtered pagination and safe media', async () => {
  const shape = {
    project: { id: project }, client: null, equipment: null, hasAllocations: true, cells: [{ id: cell }],
    allocations: [{ id: cell, celula_id: cell, projeto_id: project }], complete: true, forms: [], records: [], stages: [],
    comments: [], documents: [], attachments: [], users: [], photos: [{ id: cell, projeto_id: project, selecao_relatorio: true }],
    photoTotal: 25, photoPage: 2, photoPageSize: 24,
  };
  const photoCaps = [...caps, 'em.photos.read'] as const;
  const data = createWebData(client, photoCaps, undefined, async (resource, args) => {
    assert.equal(resource, 'project_detail');
    assert.equal(args.photo_page, 2);
    assert.equal(args.selected_only, true);
    assert.equal(args.selected_first, true);
    return shape;
  });
  const view = await data.getProject(project, { photoPage: '2', selection: 'selected', photoOrder: 'selected' });
  assert.equal(view?.photoTotal, 25);
  assert.match(view?.photos[0].foto_url, /^\/api\/web\/media\//);
  const crossed = createWebData(client, photoCaps, undefined, async () => ({
    ...shape, records: [{ id: cell, projeto_id: cell }],
  }));
  await assert.rejects(crossed.getProject(project, { photoPage: '2' }), /Não foi possível/);
});

test('authorised record returns reviewed answers in one snapshot and fails on another record or model', async () => {
  const formCaps = ['em.portal.read', 'em.forms.read'] as const;
  const answer = { id: cell, registro_formulario_id: cell, questao_id: cell, resposta: 'https://fixture.invalid/private.png' };
  const shape = { record: { id: cell, projeto_id: project, form_id: project }, project: null, form: { id: project },
    answers: [answer], questions: [{ id: cell, form_id: project, tipo: 'foto' }], items: [], users: [], complete: true };
  const data = createWebData(client, formCaps, undefined, async (resource, args) => {
    assert.equal(resource, 'form_record_detail');
    assert.deepEqual(args, { id: cell, projects: false, documents: false, photos: false });
    return shape;
  });
  const view = await data.getRecord(cell);
  assert.equal(view?.answers[0].media_restricted, true);
  assert.equal(view?.answers[0].resposta, null);
  const crossed = createWebData(client, formCaps, undefined, async () => ({
    ...shape, answers: [{ ...answer, registro_formulario_id: project }],
  }));
  await assert.rejects(crossed.getRecord(cell), /Não foi possível/);
});

test('overview uses only the requested workshop indicators and refuses injected rows for an unavailable module', async () => {
  const formsOnly = ['em.portal.read', 'em.forms.read'] as const;
  const counts = { projects: null, activeProjects: null, awaitingReview: 1, overdueCells: null, documents: null };
  const result = { counts, recentProjects: [], recentRecords: [{ id: project, codigo: 4 }], overdue: [] };
  const data = createWebData(client, formsOnly, undefined, async (resource, args) => {
    assert.equal(resource, 'overview');
    assert.deepEqual(args, { projects: false, forms: true, planning: false, documents: false });
    return result;
  });
  assert.equal((await data.getOverview()).tasks[0].title, 'Consultar formulário 4');
  assert.deepEqual(workshopReadCapabilities('overview', { forms: true }), ['em.portal.read', 'em.forms.read']);
  const invalid = createWebData(client, formsOnly, undefined, async () => ({ ...result, recentProjects: [{ id: cell }] }));
  await assert.rejects(invalid.getOverview(), /Não foi possível/);
});

test('the portal uses the workshop reader whenever the request has an SSO context', async () => {
  assert.equal(await readWorkshopOperations({ client }), undefined);
  const read = await readWorkshopOperations({ client,
    sso: { sessionHash: 'a'.repeat(64), bindingId: project, subject: cell, capabilities: [...caps] } });
  assert.equal(typeof read, 'function');
});
