import test from 'node:test';
import assert from 'node:assert/strict';
import {
  baselineDelta, changeDateDraft, changedDateItems, dateInput, dependencyIssues, draftDates, draftTimingIssue,
  MAX_GANTT_LAG_DAYS, moveDraft, plannerBar, plannerWindow, planningInterval, proposeCascade, resizeDraft,
  type GanttDateDraft, type GanttDependency, type GanttModelRow,
} from '../src/components/web/gantt-planner-model';
import { calendarDay } from '../src/server/web/gantt';

const row = (id: string, overrides: Partial<GanttModelRow> = {}): GanttModelRow => ({
  id, projeto_id: 'project-one', updated_at: '2026-11-16T18:30:00.123456+00:00',
  data_inicio: '2026-11-16T15:00:00.123456+00:00', data_limite: '2026-11-18T15:00:00.654321+00:00',
  status: 'em_dia', can_edit: true, ...overrides,
});
const link = (predecessor_id: string, successor_id: string, lag_days = 0): GanttDependency => ({ predecessor_id, successor_id, lag_days });
const now = new Date('2026-11-16T02:00:00Z'); // Still November 15 in São Paulo.

test('same-day edits detect preserved timestamp conflicts without rewriting the original fields', () => {
  const original = row('a', { data_inicio: '2026-11-16T19:00:00.123456Z' });
  const draft = { data_limite: '2026-11-16' };
  assert.equal(draftTimingIssue(original, draft)?.code, 'TIME_ORDER');
  assert.deepEqual(changedDateItems([original], { a: draft })[0].changes, draft);
  assert.equal(original.data_inicio, '2026-11-16T19:00:00.123456Z');
  assert.equal(draftTimingIssue(original, { data_limite: '2026-11-17' }), null);
  assert.equal(draftTimingIssue(row('b', { data_limite: '2026-11-18T13:00:00Z' }), { data_inicio: '2026-11-18' })?.code, 'TIME_ORDER');
  assert.equal(draftTimingIssue(row('c', { data_inicio: '2026-11-16T15:00:00.000001Z' }), draft)?.code, 'TIME_ORDER');
  assert.equal(draftTimingIssue(row('d', { data_inicio: '2026-11-16T15:00:00.000000Z' }), draft), null);
});

test('timestamp validation follows São Paulo daylight saving and does not flag absent or unchanged dates', () => {
  // January 2018 noon was 14:00Z, whereas July noon was 15:00Z.
  assert.equal(draftTimingIssue(row('summer', { data_inicio: '2018-01-15T14:30:00Z' }), { data_limite: '2018-01-15' })?.code, 'TIME_ORDER');
  assert.equal(draftTimingIssue(row('winter', { data_inicio: '2018-07-15T14:30:00Z' }), { data_limite: '2018-07-15' }), null);
  const original = row('a', { data_inicio: '2026-11-16T19:00:00Z', data_limite: '2026-11-16T20:00:00Z' });
  assert.equal(draftTimingIssue(original), null);
  assert.equal(draftTimingIssue(original, { data_limite: '2026-11-16' }), null);
  assert.equal(draftTimingIssue(original, { data_inicio: null }), null);
  assert.equal(draftTimingIssue({ data_inicio: null, data_limite: null }, { data_inicio: '2026-11-16' }), null);
  assert.equal(draftTimingIssue(original, { data_inicio: 'invalid' }), null);
  assert.equal(draftTimingIssue(original, { data_inicio: '2026-11-17' }), null);
  assert.equal(draftTimingIssue(original, { data_inicio: '2026-11-20', data_limite: '2026-11-20' }), null);
});

test('planner zoom preserves inclusive São Paulo days and bounds the supported date range', () => {
  for (const days of [14, 42, 90]) {
    const window = plannerWindow('2026-11-01', String(days), now);
    assert.equal(window.days, days); assert.equal(window.endExclusive - window.start, days);
    assert.equal(window.end - window.start + 1, days); assert.equal(window.today, calendarDay('2026-11-15'));
    assert.equal(window.invalidDays, false); assert.equal(window.invalidStart, false);
    assert.ok(window.ticks.every(day => day >= window.start && day <= window.end));
  }
  assert.equal(plannerWindow(undefined, undefined, now).isoStart, '2026-11-01');
  assert.equal(plannerWindow(undefined, 14, now).isoStart, '2026-11-12');
  const invalid = plannerWindow('2026-02-30', 365, now);
  assert.equal(invalid.days, 42); assert.equal(invalid.invalidDays, true); assert.equal(invalid.invalidStart, true);
  assert.equal(plannerWindow('9999-12-31', 90, now).invalidStart, true);
  assert.equal(plannerWindow('0001-01-01', 90, now).isoStart, '0001-01-01');
  assert.throws(() => plannerWindow(undefined, 42, new Date('invalid')), /Data atual/);
});

test('bars use the chosen zoom, keep the final day, and expose clipped or missing periods honestly', () => {
  const window = plannerWindow('2026-11-01', 14, now);
  const spanning = plannerBar(row('a', { data_inicio: '2026-10-28', data_limite: '2026-11-16' }), window);
  assert.equal(spanning.kind, 'bar');
  if (spanning.kind === 'bar') {
    assert.equal(spanning.left, 0); assert.equal(spanning.width, 100);
    assert.equal(spanning.durationDays, 20); assert.equal(spanning.clippedStart, true); assert.equal(spanning.clippedEnd, true);
  }
  const final = plannerBar(row('a', { data_inicio: '2026-11-14', data_limite: '2026-11-14' }), window);
  assert.equal(final.kind, 'bar');
  if (final.kind === 'bar') { assert.equal(final.left, 13 / 14 * 100); assert.equal(final.width, 1 / 14 * 100); }
  assert.deepEqual(plannerBar(row('a', { data_inicio: '2026-11-15' }), window), { kind: 'outside' });
  assert.deepEqual(plannerBar(row('a', { data_inicio: null }), window), { kind: 'missing' });
  assert.deepEqual(plannerBar(row('a', { data_inicio: '2026-11-19' }), window), { kind: 'invalid' });
  assert.deepEqual(planningInterval(row('a', { data_inicio: '2026-11-16T18:00:00Z', data_limite: '2026-11-16T12:00:00Z' })), { kind: 'invalid' });
});

test('today, finalised and not-applicable stages do not receive false overdue colours', () => {
  const window = plannerWindow('2026-11-01', 42, now);
  for (const status of ['finalizado', 'n_a']) {
    const result = plannerBar(row('a', { data_inicio: '2026-11-01', data_limite: '2026-11-14', status }), window);
    assert.equal(result.kind === 'bar' && result.overdue, false);
  }
  const today = plannerBar(row('a', { data_inicio: '2026-11-01', data_limite: '2026-11-15' }), window);
  assert.equal(today.kind === 'bar' && today.overdue, false);
  const late = plannerBar(row('a', { data_inicio: '2026-11-01', data_limite: '2026-11-14' }), window);
  assert.equal(late.kind === 'bar' && late.overdue, true);
  const collected = plannerBar(row('a', { data_inicio: '2026-11-01', data_limite: '2026-11-14', status: 'coletado' }), window);
  assert.equal(collected.kind === 'bar' && collected.overdue, true);
});

test('date inputs and no-op edits preserve original timestamps and exact expected versions', () => {
  const original = row('a', { data_inicio: '2026-11-16T02:59:59.123456Z' });
  assert.equal(dateInput(original.data_inicio), '2026-11-15');
  assert.equal(dateInput('2018-12-01T02:00:00Z'), '2018-12-01');
  assert.equal(dateInput('2026-11-16T12:00:00'), '');
  const unchanged = changeDateDraft(original, {}, 'data_inicio', '2026-11-15');
  assert.deepEqual(unchanged, { ok: true, draft: {} });
  const changed = changeDateDraft(original, {}, 'data_limite', '2026-11-21');
  assert.equal(changed.ok, true);
  if (!changed.ok) return;
  assert.deepEqual(draftDates(original, changed.draft), { data_inicio: original.data_inicio, data_limite: '2026-11-21' });
  assert.deepEqual(changedDateItems([original], { a: changed.draft }), [{ id: 'a', expected_updated_at: original.updated_at, changes: { data_limite: '2026-11-21' } }]);
  const undone = changeDateDraft(original, changed.draft, 'data_limite', '2026-11-18');
  assert.deepEqual(undone, { ok: true, draft: {} });
  assert.deepEqual(changedDateItems([original], { a: {} }), []);
});

test('explicit clearing differs from an untouched missing or invalid historical date', () => {
  const original = row('a', { data_inicio: 'invalid legacy date', data_limite: null });
  assert.deepEqual(draftDates(original), { data_inicio: 'invalid legacy date', data_limite: null });
  assert.deepEqual(changeDateDraft(original, {}, 'data_inicio', ''), { ok: true, draft: { data_inicio: null } });
  assert.deepEqual(changeDateDraft(original, {}, 'data_limite', ''), { ok: true, draft: {} });
  const invalid = changeDateDraft(original, {}, 'data_inicio', '2026-02-30');
  assert.equal(invalid.ok, false);
  // Date input edits may temporarily have one endpoint; dragging must not manufacture the other.
  const partial = row('b', { data_inicio: null, data_limite: null });
  const draft = changeDateDraft(partial, {}, 'data_inicio', '2026-11-20');
  assert.equal(draft.ok, true);
  if (draft.ok) assert.equal(moveDraft(partial, draft.draft, 1).ok, false);
});

test('moving is immutable, duration-preserving and reversible without timestamp truncation', () => {
  const original = row('a'); const frozen = Object.freeze(original);
  const existing = Object.freeze({});
  const moved = moveDraft(frozen, existing, 4);
  assert.deepEqual(moved, { ok: true, draft: { data_inicio: '2026-11-20', data_limite: '2026-11-22' } });
  if (!moved.ok) return;
  const reverted = moveDraft(original, moved.draft, -4);
  assert.deepEqual(reverted, { ok: true, draft: {} });
  assert.equal(original.data_inicio, '2026-11-16T15:00:00.123456+00:00');
  assert.deepEqual(moveDraft(original, {}, 0), { ok: true, draft: {} });
  assert.equal(moveDraft(original, {}, 1.5).ok, false);
  assert.equal(moveDraft(original, {}, Number.MAX_SAFE_INTEGER).ok, false);
  assert.equal(moveDraft(row('a', { data_inicio: '0001-01-01', data_limite: '0001-01-02' }), {}, -1).ok, false);
});

test('resize never crosses endpoints and only changes the dragged edge', () => {
  const original = row('a');
  assert.deepEqual(resizeDraft(original, {}, 'end', 2), { ok: true, draft: { data_limite: '2026-11-20' } });
  assert.deepEqual(resizeDraft(original, {}, 'start', 99), { ok: true, draft: { data_inicio: '2026-11-18' } });
  assert.deepEqual(resizeDraft(original, {}, 'end', -99), { ok: true, draft: { data_limite: '2026-11-16' } });
  assert.equal(resizeDraft(original, {}, 'end', Number.MAX_SAFE_INTEGER).ok, false);
  for (const locked of [row('a', { can_edit: false }), row('a', { status: 'finalizado' }), row('a', { status: 'n_a' })]) {
    assert.equal(changeDateDraft(locked, {}, 'data_inicio', '2026-11-20').ok, false);
    assert.equal(moveDraft(locked, {}, 1).ok, false); assert.equal(resizeDraft(locked, {}, 'end', 1).ok, false);
  }
  assert.equal(moveDraft(row('a', { status: 'coletado' }), {}, 1).ok, true);
});

test('date payload refuses unknown, duplicate, read-only and malformed draft rows', () => {
  const original = row('a');
  assert.throws(() => changedDateItems([original], { unknown: { data_inicio: '2026-11-20' } }), /não pertence/);
  assert.throws(() => changedDateItems([original, original], {}), /repetidas/);
  assert.throws(() => changedDateItems([row('a', { can_edit: false })], { a: { data_inicio: '2026-11-20' } }), /somente para consulta/);
  assert.throws(() => changedDateItems([original], { a: { data_inicio: '2026-11-20T12:00:00Z' } }), /AAAA-MM-DD/);
  assert.throws(() => changedDateItems([original], { a: { data_inicio: '1899-12-31' } }), /1900 e 2200/);
});

test('editable dates obey the 1900 to 2200 backend range while historical dates remain readable', () => {
  const historical = row('a', { data_inicio: '1890-02-01T15:00:00Z', data_limite: '1890-02-05T15:00:00Z' });
  assert.equal(dateInput(historical.data_inicio), '1890-02-01');
  assert.equal(plannerBar(historical, plannerWindow('1890-02-01', 14, now)).kind, 'bar');
  assert.deepEqual(changedDateItems([historical], {}), []);
  assert.equal(changeDateDraft(historical, {}, 'data_inicio', '1899-12-31').ok, false);
  assert.equal(changeDateDraft(historical, {}, 'data_inicio', '1900-01-01').ok, true);
  assert.equal(changeDateDraft(historical, {}, 'data_limite', '2200-12-31').ok, true);
  assert.equal(changeDateDraft(historical, {}, 'data_limite', '2201-01-01').ok, false);
  assert.equal(moveDraft(row('a', { data_inicio: '1900-01-01', data_limite: '1900-01-02' }), {}, -1).ok, false);
  assert.equal(resizeDraft(row('a', { data_inicio: '2200-12-30', data_limite: '2200-12-31' }), {}, 'end', 1).ok, false);
});

test('FS uses the day after the inclusive end plus calendar-day lag, with current drafts', () => {
  const rows = [row('a'), row('b', { data_inicio: '2026-11-19', data_limite: '2026-11-20' })];
  assert.deepEqual(dependencyIssues(rows, [link('a', 'b')]), []);
  const lag = dependencyIssues(rows, [link('a', 'b', 2)]);
  assert.equal(lag[0].code, 'FS_VIOLATION'); assert.equal(lag[0].earliest_start, '2026-11-21');
  assert.deepEqual(dependencyIssues(rows, [link('a', 'b', 2)], { b: { data_inicio: '2026-11-21', data_limite: '2026-11-22' } }), []);
  const equalDay = dependencyIssues([rows[0], row('b', { data_inicio: '2026-11-18' })], [link('a', 'b')]);
  assert.equal(equalDay[0].code, 'FS_VIOLATION');
  assert.equal(dependencyIssues([rows[0], row('b', { data_inicio: null })], [link('a', 'b')])[0].code, 'MISSING_DATES');
});

test('dependency validation refuses invalid endpoints, project crossing, duplicate links, cycles and lag', () => {
  const rows = [row('a'), row('b'), row('c', { projeto_id: 'another-project' })];
  const code = (links: GanttDependency[]) => dependencyIssues(rows, links).map(issue => issue.code);
  assert.ok(code([link('a', 'missing')]).includes('MISSING_ENDPOINT'));
  assert.ok(code([link('a', 'a')]).includes('SELF_LINK'));
  assert.ok(code([link('a', 'c')]).includes('CROSS_PROJECT'));
  assert.ok(code([{ ...link('a', 'b'), projeto_id: 'another-project' }]).includes('CROSS_PROJECT'));
  assert.ok(code([link('a', 'b'), link('a', 'b')]).includes('DUPLICATE_LINK'));
  assert.ok(code([link('a', 'b'), link('b', 'a')]).includes('CYCLE'));
  for (const lag of [-1, .5, Infinity, MAX_GANTT_LAG_DAYS + 1]) assert.ok(code([link('a', 'b', lag)]).includes('INVALID_LAG'));
  assert.ok(!code([link('a', 'b', MAX_GANTT_LAG_DAYS)]).includes('INVALID_LAG'));
});

test('explicit cascade follows strongest predecessor, preserves duration and never pulls a later task earlier', () => {
  const rows = [row('a'), row('b', { data_inicio: '2026-11-17', data_limite: '2026-11-18' }),
    row('c', { data_inicio: '2026-11-18', data_limite: '2026-11-21' }),
    row('d', { data_inicio: '2026-12-01', data_limite: '2026-12-02' }),
    row('independent', { data_inicio: null, data_limite: null })];
  const links = [link('a', 'b', 1), link('a', 'c'), link('b', 'c', 2), link('c', 'd')];
  const input = Object.freeze({ a: Object.freeze({ data_limite: '2026-11-20' }) });
  const result = proposeCascade(rows, links, input);
  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.deepEqual(result.changedIds, ['b', 'c']);
  assert.deepEqual(result.drafts.b, { data_inicio: '2026-11-22', data_limite: '2026-11-23' });
  assert.deepEqual(result.drafts.c, { data_inicio: '2026-11-26', data_limite: '2026-11-29' });
  assert.equal(result.drafts.d, undefined); assert.equal(result.drafts.independent, undefined);
  assert.deepEqual(input, { a: { data_limite: '2026-11-20' } });
  assert.deepEqual(dependencyIssues(rows, links, result.drafts), []);
  assert.equal(proposeCascade(rows, links, result.drafts).ok, true);
});

test('cascade fails atomically for missing dates, cycles, immutable successors or out-of-range output', () => {
  const before = row('a'); const after = row('b', { data_inicio: '2026-11-17', data_limite: '2026-11-18' });
  for (const changed of [row('b', { can_edit: false }), row('b', { status: 'finalizado' }), row('b', { data_inicio: null }), row('b', { data_inicio: '2026-12-20' })]) {
    const proposal = proposeCascade([before, changed], [link('a', 'b')]);
    assert.equal(proposal.ok, false); assert.equal('drafts' in proposal, false);
  }
  assert.equal(proposeCascade([before, after], [link('a', 'b'), link('b', 'a')]).ok, false);
  const outside = proposeCascade([row('a', { data_inicio: '9999-12-30', data_limite: '9999-12-31' }), after], [link('a', 'b')]);
  assert.equal(outside.ok, false);
  // A fixed, already completed predecessor is valid evidence and is never itself moved.
  const fixed = proposeCascade([row('a', { can_edit: false, status: 'finalizado' }), after], [link('a', 'b')]);
  assert.equal(fixed.ok, true);
});

test('cascade refuses an invalid initial draft and detects cycles without recursive stack growth', () => {
  assert.equal(proposeCascade([row('a')], [], { missing: { data_inicio: '2026-11-20' } }).ok, false);
  const rows = Array.from({ length: 2000 }, (_, index) => row(`task-${index}`));
  const links = rows.slice(1).map((current, index) => link(rows[index].id, current.id));
  links.push(link(rows.at(-1)!.id, rows[0].id));
  const result = proposeCascade(rows, links);
  assert.equal(result.ok, false);
  if (!result.ok) assert.ok(result.issues.some(issue => issue.code === 'CYCLE'));
});

test('baseline differences compare calendar days and preserve unknown dates rather than inventing progress', () => {
  const original = row('a');
  assert.deepEqual(baselineDelta(original, original), { startDays: 0, endDays: 0, changed: false });
  assert.deepEqual(baselineDelta(original, original, { data_limite: '2026-11-20' }), { startDays: 0, endDays: 2, changed: true });
  assert.deepEqual(baselineDelta(original, { data_inicio: null, data_limite: null }), { startDays: null, endDays: null, changed: true });
  assert.deepEqual(baselineDelta(original, null), { startDays: null, endDays: null, changed: false });
  const cleared: GanttDateDraft = { data_inicio: null };
  assert.deepEqual(baselineDelta(original, original, cleared), { startDays: null, endDays: 0, changed: true });
});
