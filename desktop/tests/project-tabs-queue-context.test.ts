import test from 'node:test';
import assert from 'node:assert/strict';
import { projectTabs, selectedProjectTab } from '../src/components/web/project-tabs';
import { queueAllocationHref, queueAllocationMatches } from '../src/components/web/queue-allocation-model';
import { projectRouteMatchesContext } from '../src/components/web/project-route-model';
import type { PcpQueueItem } from '../src/server/web/pcp-data';
import type { ProjectRouteSnapshot } from '../src/server/web/project-route-data';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-11-05T12:01:02.123456+00:00';

test('project comments and technical history use distinct areas while old filtered bookmarks retain their subject', () => {
  const tabs = projectTabs.map(tab => tab.id);
  assert.equal(selectedProjectTab({ tab: 'historico' }, tabs), 'historico');
  assert.equal(selectedProjectTab({ tab: 'comentarios' }, tabs), 'comentarios');
  assert.equal(selectedProjectTab({ tab: 'historico', comment_q: 'motor' }, tabs), 'comentarios');
  assert.equal(selectedProjectTab({ tab: 'comentarios' }, ['informacoes']), 'informacoes');
  assert.equal(selectedProjectTab({ tab: ['roteiro', 'historico'] }, tabs), 'informacoes');
  assert.equal(selectedProjectTab({ tab: 'roteiro' }, tabs), 'roteiro');
});

test('queue edit context binds the allocation UUID, project, cell and exact revision', () => {
  const item = { id: id(2), projeto_id: id(1), celula_id: id(3), updated_at: version } as PcpQueueItem;
  const allocation = { ...item, retirada: false, status: 'pendente' };
  assert.equal(queueAllocationMatches(item, allocation), true);
  for (const patch of [{ id: id(4) }, { projeto_id: id(4) }, { celula_id: id(4) }, { updated_at: version.replace('123456', '123457') }, { retirada: true }, { status: 'finalizado' }, { status: 'n_a' }]) {
    assert.equal(queueAllocationMatches(item, { ...allocation, ...patch }), false);
  }
  assert.equal(queueAllocationMatches(item, undefined), false);
  const href = new URL(queueAllocationHref(id(3), id(2)), 'https://em.local');
  assert.equal(href.pathname, '/planejamento/fila'); assert.equal(href.searchParams.get('cell'), id(3)); assert.equal(href.searchParams.get('allocation'), id(2));
  assert.equal(new URL(queueAllocationHref(id(3)), 'https://em.local').searchParams.has('allocation'), false);
});

test('route detail rejects partial, changed and crossed contexts without hiding preserved retired allocations', () => {
  const project = { id: id(1), updated_at: version };
  const allocation = { id: id(2), projeto_id: id(1), celula_id: id(3), updated_at: version, retirada: false };
  const snapshot = { project, complete: true, items: [{ id: allocation.id, celula_id: allocation.celula_id, updated_at: version }] } as ProjectRouteSnapshot;
  assert.equal(projectRouteMatchesContext(snapshot, project, [allocation, { ...allocation, id: id(4), retirada: true }]), true);
  assert.equal(projectRouteMatchesContext(null, project, [allocation]), false);
  assert.equal(projectRouteMatchesContext({ ...snapshot, complete: false }, project, [allocation]), false);
  assert.equal(projectRouteMatchesContext(snapshot, project, [allocation, { ...allocation, id: id(4) }]), false);
  assert.equal(projectRouteMatchesContext(snapshot, project, [{ ...allocation, projeto_id: id(5) }]), false);
  assert.equal(projectRouteMatchesContext(snapshot, project, [{ ...allocation, updated_at: version.replace('123456', '123457') }]), false);
  assert.equal(projectRouteMatchesContext(snapshot, { ...project, updated_at: version.replace('123456', '123457') }, [allocation]), false);
});
