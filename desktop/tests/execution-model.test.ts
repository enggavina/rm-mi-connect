import test from 'node:test';
import assert from 'node:assert/strict';
import { allocationExecutionState, confirmedExecutionEffort, executionEvidenceAge, executionInputInstant, executionNeedsReview, executionSaoPauloInput, executionSearchMatches, parseExecutionMinutes, type ExecutionEvidence } from '../src/components/web/execution-model';
const session = (state: ExecutionEvidence['state'], extra: Partial<ExecutionEvidence> = {}): ExecutionEvidence => ({ state, needs_review: false, clock_warning: false, has_review: false, confirmed_minutes: null, ...extra });
test('execution cards show evidence with unknown distinct from stopped and multiple operators preserved', () => {
  assert.equal(allocationExecutionState([]), 'unknown'); assert.equal(allocationExecutionState([session('void')]), 'unknown');
  assert.equal(allocationExecutionState([session('finished'), session('paused')]), 'paused');
  assert.equal(allocationExecutionState([session('finished'), session('paused'), session('running')]), 'running');
  assert.equal(allocationExecutionState([session('running'), session('review')]), 'review');
});
test('clock warnings remain visible evidence but a manager review can reconcile them without erasing the warning', () => {
  const raw = session('finished', { clock_warning: true }); assert.equal(executionNeedsReview(raw), true);
  assert.equal(executionNeedsReview({ ...raw, has_review: true }), false);
  assert.equal(executionNeedsReview({ ...raw, has_review: true, needs_review: true }), true);
});
test('effort totals sum only explicit declarations, preserve zero and exclude void sessions', () => {
  assert.deepEqual(confirmedExecutionEffort([session('running')]), { minutes: null, confirmed: 0, missing: 1, sessions: 1 });
  assert.deepEqual(confirmedExecutionEffort([session('finished', { confirmed_minutes: 0 }), session('finished', { confirmed_minutes: 25 }), session('paused'), session('void', { confirmed_minutes: 100 })]), { minutes: 25, confirmed: 2, missing: 1, sessions: 3 });
  assert.deepEqual(confirmedExecutionEffort([session('finished', { confirmed_minutes: 30, needs_review: true }), session('finished', { confirmed_minutes: 0 }), session('finished', { confirmed_minutes: 15, clock_warning: true, has_review: true })]), { minutes: 15, confirmed: 2, missing: 1, sessions: 3 });
  assert.equal(parseExecutionMinutes(''), null); assert.equal(parseExecutionMinutes('0'), 0); assert.equal(parseExecutionMinutes('1000000'), 1000000);
  for (const value of ['-1', '1.5', '1,5', '1000001', 'Infinity']) assert.equal(parseExecutionMinutes(value), undefined);
});
test('timestamps for reported work use explicit São Paulo civil minutes including historic daylight saving', () => {
  assert.equal(executionInputInstant('2026-11-17T08:30'), '2026-11-17T11:30:00.000Z');
  assert.equal(executionInputInstant('2018-11-05T08:30'), '2018-11-05T10:30:00.000Z');
  assert.equal(executionInputInstant('2018-11-04T00:30'), null);
  assert.equal(executionInputInstant('2019-02-16T23:30'), null);
  for (const value of ['2026-02-30T12:00', '2026-11-17T24:00', '2026-11-17T08:60', '1899-12-31T12:00', '2201-01-01T12:00']) assert.equal(executionInputInstant(value), null);
  assert.equal(executionSaoPauloInput('2026-11-17T11:30:47.123456+00:00'), '2026-11-17T08:30');
  assert.equal(executionSaoPauloInput(null), '');
});
test('search ignores accents while evidence age describes only known receiving time', () => {
  assert.equal(executionSearchMatches('JOAO', ['João', 'Célula']), true);
  assert.equal(executionSearchMatches('cliente x', ['Cliente Y']), false);
  assert.equal(executionEvidenceAge(null, '2026-11-17T12:00Z'), 'Sem atualização recebida');
  assert.equal(executionEvidenceAge('2026-11-16T12:00Z', '2026-11-17T12:00Z'), 'Recebido há 1 dia(s)');
  assert.match(executionEvidenceAge('2026-11-18T12:00Z', '2026-11-17T12:00Z'), /posterior/);
});
