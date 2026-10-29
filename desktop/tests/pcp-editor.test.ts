import test from 'node:test';
import assert from 'node:assert/strict';
import { estimatedHours, freezeCellQueueRequest, moveQueueItem, queueOrderChanged, queuePrioritiesChanged } from '../src/components/web/pcp-model';

test('moving the cell queue preserves every row and its priority without sorting by urgency', () => {
  const original = [{ id: 'a', prioridade: 'baixa' }, { id: 'b', prioridade: 'muito_alta' }, { id: 'c', prioridade: null }];
  const moved = moveQueueItem(original, 'c', 0);
  assert.deepEqual(moved.map(item => item.id), ['c', 'a', 'b']);
  assert.equal(moved[2], original[1]); assert.equal(moved[2].prioridade, 'muito_alta');
  assert.deepEqual(original.map(item => item.id), ['a', 'b', 'c']);
  assert.deepEqual(moveQueueItem(original, 'a', -1), original);
  assert.deepEqual(moveQueueItem(original, 'unknown', 0), original);
});

test('priority-only edits and restored order do not imply queue normalization', () => {
  const original = [{ id: 'a', prioridade: null }, { id: 'b', prioridade: 'alta' }];
  const priorityOnly = [{ id: 'a', prioridade: 'baixa' }, original[1]];
  assert.equal(queuePrioritiesChanged(priorityOnly, original), true);
  assert.equal(queueOrderChanged(priorityOnly, original), false);
  const restored = moveQueueItem(moveQueueItem(priorityOnly, 'b', 0), 'b', 1);
  assert.equal(queueOrderChanged(restored, original), false);
  assert.equal(queuePrioritiesChanged(restored, original), true);
});

test('queue retry freezes all items, exact timestamps and the priority-only intent', () => {
  const items = [{ id: 'row', expected_updated_at: '2026-10-29T12:00:00.123456+00:00', prioridade: 'alta' as const }];
  const frozen = freezeCellQueueRequest({ submissionId: 'same-request', celula_id: 'cell', expected_queue_version: 'opaque-revision', apply_order: false, items });
  items[0].expected_updated_at = 'different'; items.push({ ...items[0], id: 'extra' });
  assert.equal(frozen.items.length, 1); assert.equal(frozen.items[0].expected_updated_at, '2026-10-29T12:00:00.123456+00:00');
  assert.equal(frozen.apply_order, false); assert.equal(Object.isFrozen(frozen.items), true);
  assert.throws(() => { frozen.items[0].id = 'other'; }, TypeError);
});

test('missing workload estimates are distinct from an explicitly entered zero', () => {
  assert.equal(estimatedHours(null), 'Sem estimativa'); assert.equal(estimatedHours(undefined), 'Sem estimativa');
  assert.equal(estimatedHours(0), '0 h'); assert.equal(estimatedHours(12.5), '12,5 h');
});
