import test from 'node:test';
import assert from 'node:assert/strict';
import type { ProjectRouteSnapshot } from '../src/server/web/project-route-data';
import { moveProjectRouteItem, projectRouteOrderChanged, projectRouteNeedsNormalization, projectRouteRequest, projectRouteDestination } from '../src/components/web/project-route-model';
import { catalogFailureState } from '../src/components/web/catalog-model';

const version = '2026-10-29T18:03:24.123456+00:00';
test('route position controls move only IDs and preserve all operational fields and the original snapshot', () => {
  const original = [{ id: 'a', indice: null, posicao: 8, prioridade: 'alta' }, { id: 'b', indice: -1, posicao: 3, prioridade: null }];
  const moved = moveProjectRouteItem(original, 'b', 0);
  assert.deepEqual(moved.map(item => item.id), ['b', 'a']); assert.equal(moved[0], original[1]); assert.equal(moved[0].posicao, 3);
  assert.deepEqual(original.map(item => item.id), ['a', 'b']); assert.equal(projectRouteOrderChanged(moved, original), true);
  assert.equal(projectRouteOrderChanged(moveProjectRouteItem(moved, 'b', 1), original), false);
  assert.deepEqual(moveProjectRouteItem(original, 'a', -1), original);
  assert.equal(projectRouteNeedsNormalization(original), true); assert.equal(projectRouteNeedsNormalization([{ indice: 1 }, { indice: 2 }]), false);
});
test('route request freezes the complete explicit sequence and exact versions without sending positions or priority', () => {
  const snapshot = { project: { id: 'project', updated_at: version }, route_version: 'hash' } as ProjectRouteSnapshot;
  const items = [{ id: 'allocation', updated_at: version, indice: 9, posicao: 5 }];
  const request = projectRouteRequest(snapshot, items, 'same-uuid'); items[0].updated_at = 'changed'; items.push({ ...items[0], id: 'extra' });
  assert.deepEqual(request, { submissionId: 'same-uuid', projeto_id: 'project', expected_project_updated_at: version, expected_route_version: 'hash', items: [{ id: 'allocation', expected_updated_at: version }] });
  assert.equal(Object.isFrozen(request.items), true); assert.throws(() => { request.items[0].id = 'different'; }, TypeError);
});
test('route navigation stays internal and ambiguous failures freeze the attempt while conflicts require reload', () => {
  assert.equal(projectRouteDestination('/cronograma?project=abc', 'abc'), '/cronograma?project=abc');
  for (const unsafe of ['https://outside.invalid', '//outside.invalid', '/\\outside.invalid', '/with space']) assert.equal(projectRouteDestination(unsafe, 'abc'), '/cronograma?project=abc');
  assert.equal(catalogFailureState({ ok: false, error: 'Safe error', code: 'UNAVAILABLE' }).uncertain, true);
  assert.equal(catalogFailureState({ ok: false, error: 'Safe error', code: 'PT409' }).stale, true);
  assert.equal(catalogFailureState({ ok: false, error: 'Safe error', code: '42501' }).unauthorized, true);
});
