import test from 'node:test';
import assert from 'node:assert/strict';
import {
  addWorkingDays, analyzeCriticalPath, calendarDateIssues, calendarDependencyIssues,
  countWorkingDays, EVERY_DAY_CALENDAR, isWorkingDay, moveCalendarDraft,
  nextWorkingDay, proposeCalendarCascade, resizeCalendarDraft, workingDayDistance,
  type GanttWorkCalendar,
} from '../src/components/web/gantt-calendar-model';
import {
  changedDateItems, draftDates, moveDraft, proposeCascade, resizeDraft,
  type GanttDateDraft, type GanttDependency, type GanttModelRow,
} from '../src/components/web/gantt-planner-model';
import { calendarDay, isoCalendarDay } from '../src/server/web/gantt';

const weekdays: GanttWorkCalendar = { weekdays: [1, 2, 3, 4, 5], exceptions: [] };
const holiday: GanttWorkCalendar = { weekdays: [1, 2, 3, 4, 5], exceptions: [
  { date: '2026-11-23', working: false, label: 'Parada da oficina' },
  { date: '2026-11-28', working: true, label: 'Sábado de trabalho' },
] };
const iso = (value: number | null) => value === null ? null : isoCalendarDay(value);
const row = (id: string, start = '2026-11-16', end = start, overrides: Partial<GanttModelRow> = {}): GanttModelRow => ({
  id, projeto_id: 'project-one', data_inicio: start, data_limite: end,
  updated_at: '2026-11-16T18:30:00.123456+00:00', status: 'em_dia', can_edit: true, ...overrides,
});
const edge = (predecessor_id: string, successor_id: string, lag_days = 0): GanttDependency => ({ predecessor_id, successor_id, lag_days });
const failureCode = (result: ReturnType<typeof moveCalendarDraft>) => result.ok ? null : result.code;
function diamond() {
  const rows = [row('a', '2026-11-16', '2026-11-17'), row('b', '2026-11-18', '2026-11-23'),
    row('c', '2026-11-18', '2026-11-19'), row('d', '2026-11-24')];
  const links = [edge('a', 'b'), edge('a', 'c'), edge('b', 'd'), edge('c', 'd')];
  return { rows, links };
}

test('working-day addition, inclusive duration and signed distances respect weekends and exceptions', () => {
  assert.equal(iso(addWorkingDays(weekdays, '2026-11-20', 1)), '2026-11-23');
  assert.equal(iso(addWorkingDays(holiday, '2026-11-20', 1)), '2026-11-24');
  assert.equal(iso(addWorkingDays(holiday, '2026-11-24', -1)), '2026-11-20');
  assert.equal(iso(addWorkingDays(holiday, '2026-11-27', 1)), '2026-11-28');
  assert.equal(iso(addWorkingDays(holiday, '2026-11-30', -1)), '2026-11-28');
  assert.equal(countWorkingDays(holiday, '2026-11-20', '2026-11-30'), 7);
  assert.equal(countWorkingDays(weekdays, '2026-11-21', '2026-11-22'), 0);
  assert.equal(workingDayDistance(holiday, '2026-11-20', '2026-11-30'), 6);
  assert.equal(workingDayDistance(holiday, '2026-11-30', '2026-11-20'), -6);
  assert.equal(isWorkingDay(holiday, '2026-11-28'), true);
  assert.equal(isWorkingDay(holiday, '2026-11-23'), false);
  assert.equal(iso(nextWorkingDay(holiday, '2026-11-21')), '2026-11-24');
  assert.equal(iso(nextWorkingDay(holiday, '2026-11-23', -1)), '2026-11-20');
  assert.equal(iso(nextWorkingDay(weekdays, '2026-11-20', 1, false)), '2026-11-23');
  assert.equal(iso(addWorkingDays(weekdays, '2026-11-21', 0)), '2026-11-21');
});

test('bounded calendar mathematics agrees with an independent enumerated calendar in both directions', () => {
  const first = calendarDay('2026-10-01')!;
  const independentWorks = (day: number) => {
    const date = isoCalendarDay(day), exception = holiday.exceptions.find(item => item.date === date);
    return exception?.working ?? [1, 2, 3, 4, 5].includes(new Date(day * 86_400_000).getUTCDay() || 7);
  };
  for (let offset = 0; offset < 90; offset += 3) {
    const start = first + offset, finish = start + 21;
    let expected = 0;
    for (let day = start; day <= finish; day++) expected += Number(independentWorks(day));
    assert.equal(countWorkingDays(holiday, start, finish), expected);
    for (const delta of [-17, -3, -1, 1, 3, 17]) {
      let day = start, left = Math.abs(delta);
      while (left) { day += Math.sign(delta); if (independentWorks(day)) left--; }
      assert.equal(addWorkingDays(holiday, start, delta), day);
    }
  }
});

test('civil dates survive leap days, historical Sao Paulo daylight saving and extreme readable dates', () => {
  assert.equal(countWorkingDays(EVERY_DAY_CALENDAR, '2024-02-28', '2024-03-01'), 3);
  assert.equal(iso(addWorkingDays(EVERY_DAY_CALENDAR, '2024-02-28', 1)), '2024-02-29');
  assert.equal(iso(addWorkingDays(EVERY_DAY_CALENDAR, '2018-11-03T23:30:00-03:00', 1)), '2018-11-04');
  assert.equal(iso(addWorkingDays(EVERY_DAY_CALENDAR, '2018-11-04T02:30:00Z', 1)), '2018-11-04');
  assert.equal(isWorkingDay(weekdays, '2026-11-16T02:59:59.123456Z'), false); // Sunday in Sao Paulo.
  assert.equal(countWorkingDays(EVERY_DAY_CALENDAR, '0001-01-01', '9999-12-31'), 3_652_059);
  assert.equal(addWorkingDays(EVERY_DAY_CALENDAR, '9999-12-31', 1), null);
  assert.equal(addWorkingDays(EVERY_DAY_CALENDAR, '0001-01-01', -1), null);
  assert.equal(iso(addWorkingDays(EVERY_DAY_CALENDAR, '9999-12-31', -3_652_058)), '0001-01-01');
});

test('invalid or reversed dates and malformed calendars fail without inventing useful durations', () => {
  for (const calendar of [
    { weekdays: [], exceptions: [] }, { weekdays: [1, 1], exceptions: [] }, { weekdays: [0], exceptions: [] },
    { weekdays: [1], exceptions: [{ date: '2026-02-30', working: false, label: 'Inválido' }] },
    { weekdays: [1], exceptions: [{ date: '2026-11-16', working: false, label: 'a' }, { date: '2026-11-16', working: true, label: 'b' }] },
    { weekdays: [1], exceptions: [null] },
  ] as GanttWorkCalendar[]) {
    assert.equal(isWorkingDay(calendar, '2026-11-16'), false);
    assert.equal(countWorkingDays(calendar, '2026-11-16', '2026-11-18'), null);
    assert.equal(addWorkingDays(calendar, '2026-11-16', 1), null);
  }
  assert.equal(countWorkingDays(weekdays, '2026-11-18', '2026-11-16'), null);
  assert.equal(countWorkingDays(weekdays, '2026-02-30', '2026-11-16'), null);
  assert.equal(addWorkingDays(weekdays, '2026-11-16', 1.5), null);
  assert.equal(addWorkingDays(weekdays, Number.MAX_SAFE_INTEGER, 1), null);
  assert.equal(workingDayDistance(weekdays, 'invalid', '2026-11-16'), null);
});

test('all-seven-day mode preserves the previous move, resize and cascade behavior byte-for-byte', () => {
  const original = row('a', '2026-11-16T15:00:00.123456+00:00', '2026-11-18T15:00:00.654321+00:00');
  for (const delta of [-2, 0, 4]) {
    assert.deepEqual(moveCalendarDraft(original, {}, delta, EVERY_DAY_CALENDAR), moveDraft(original, {}, delta));
    for (const edge of ['start', 'end'] as const) assert.deepEqual(resizeCalendarDraft(original, {}, edge, delta, EVERY_DAY_CALENDAR), resizeDraft(original, {}, edge, delta));
  }
  const rows = [original, row('b', '2026-11-17', '2026-11-18'), row('c', '2026-11-20', '2026-11-21')];
  assert.deepEqual(proposeCalendarCascade(rows, [edge('a', 'b', 1), edge('b', 'c')], {}, EVERY_DAY_CALENDAR),
    proposeCascade(rows, [edge('a', 'b', 1), edge('b', 'c')], {}));
});

test('moves preserve working duration across holidays and snap in the pointer direction without mutating data', () => {
  const original = Object.freeze(row('a', '2026-11-19T15:00:00.123456+00:00', '2026-11-20T15:00:00.654321+00:00'));
  const draft = Object.freeze({});
  const moved = moveCalendarDraft(original, draft, 2, holiday);
  assert.deepEqual(moved, { ok: true, draft: { data_inicio: '2026-11-24', data_limite: '2026-11-25' } });
  const back = moveCalendarDraft(row('b', '2026-11-24', '2026-11-25'), {}, -1, holiday);
  assert.deepEqual(back, { ok: true, draft: { data_inicio: '2026-11-20', data_limite: '2026-11-24' } });
  assert.deepEqual(moveCalendarDraft(original, draft, 0, holiday), { ok: true, draft: {} });
  assert.equal(original.data_inicio, '2026-11-19T15:00:00.123456+00:00');
  if (moved.ok) {
    assert.equal(countWorkingDays(holiday, ...Object.values(draftDates(original, moved.draft)) as [string, string]), 2);
    assert.equal(changedDateItems([original], { a: moved.draft })[0].expected_updated_at, original.updated_at);
  }
  assert.equal(failureCode(moveCalendarDraft(row('a', '2026-11-21', '2026-11-22'), {}, 1, holiday)), 'NO_WORKING_DURATION');
  assert.equal(failureCode(moveCalendarDraft(row('a', '2200-12-30', '2200-12-31'), {}, 2, holiday)), 'OUT_OF_RANGE');
  assert.equal(failureCode(moveCalendarDraft(row('a', undefined, undefined, { data_inicio: null }), {}, 1, holiday)), 'MISSING_DATES');
  for (const overrides of [{ can_edit: false }, { status: 'finalizado' }, { status: 'n_a' }]) {
    assert.equal(failureCode(moveCalendarDraft(row('a', undefined, undefined, overrides), {}, 1, holiday)), 'READ_ONLY');
  }
});

test('resize snaps only the dragged boundary and retains exact opposite timestamps, including clamping', () => {
  const original = row('a', '2026-11-19T15:00:00.123456+00:00', '2026-11-20T15:00:00.654321+00:00');
  const resized = resizeCalendarDraft(original, {}, 'end', 1, holiday);
  assert.deepEqual(resized, { ok: true, draft: { data_limite: '2026-11-24' } });
  if (resized.ok) assert.equal(draftDates(original, resized.draft).data_inicio, original.data_inicio);
  assert.deepEqual(resizeCalendarDraft(original, {}, 'start', 10, holiday), { ok: true, draft: { data_inicio: '2026-11-20' } });
  assert.deepEqual(resizeCalendarDraft(original, {}, 'end', -10, holiday), { ok: true, draft: { data_limite: '2026-11-19' } });
  assert.equal(failureCode(resizeCalendarDraft(row('b', '2026-11-20', '2026-11-22'), {}, 'start', 10, holiday)), 'NON_WORKING_BOUNDARY');
  assert.equal(failureCode(resizeCalendarDraft(original, {}, 'end', 0.5, holiday)), 'INVALID_VALUE');
});

test('existing nonworking boundaries are explicit warnings and FS lags count useful days', () => {
  const rows = [row('a', '2026-11-20'), row('b', '2026-11-23', '2026-11-24')];
  assert.deepEqual(calendarDateIssues(rows, {}, holiday).map(issue => [issue.allocation_id, issue.code]), [['b', 'NON_WORKING_START']]);
  const issues = calendarDependencyIssues(rows, [edge('a', 'b', 1)], {}, holiday);
  assert.equal(issues.length, 1); assert.equal(issues[0].earliest_start, '2026-11-25');
  assert.deepEqual(calendarDependencyIssues(rows, [edge('a', 'b', 1)], { b: { data_inicio: '2026-11-25', data_limite: '2026-11-25' } }, holiday), []);
  assert.equal(rows[1].data_inicio, '2026-11-23');
});

test('calendar cascade follows branching dependencies atomically while retaining working durations and fixed predecessors', () => {
  const rows = [row('a', '2026-11-20', undefined, { status: 'finalizado', can_edit: false }),
    row('b', '2026-11-19', '2026-11-20'), row('c', '2026-11-20'), row('d', '2026-11-20')];
  const links = [edge('a', 'b'), edge('a', 'c', 1), edge('b', 'd'), edge('c', 'd')];
  const draft = Object.freeze({});
  const result = proposeCalendarCascade(rows, links, draft, holiday);
  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.deepEqual(result.changedIds, ['b', 'c', 'd']);
  assert.deepEqual(result.drafts, {
    b: { data_inicio: '2026-11-24', data_limite: '2026-11-25' },
    c: { data_inicio: '2026-11-25', data_limite: '2026-11-25' },
    d: { data_inicio: '2026-11-26', data_limite: '2026-11-26' },
  });
  assert.deepEqual(calendarDependencyIssues(rows, links, result.drafts, holiday), []);
  assert.equal(rows[1].data_inicio, '2026-11-19'); assert.deepEqual(draft, {});
  const blocked = proposeCalendarCascade(rows.map(item => item.id === 'd' ? { ...item, can_edit: false } : item), links, {}, holiday);
  assert.equal(blocked.ok, false); if (!blocked.ok) assert.equal(blocked.issues[0].code, 'READ_ONLY');
});

test('calendar cascade and dependencies refuse incomplete, cross-project, duplicate or cyclic graphs', () => {
  const rows = [row('a'), row('b')];
  const cases: [GanttModelRow[], GanttDependency[], string][] = [
    [rows, [edge('a', 'missing')], 'MISSING_ENDPOINT'],
    [rows, [edge('a', 'a')], 'SELF_LINK'],
    [rows, [edge('a', 'b'), edge('a', 'b')], 'DUPLICATE_LINK'],
    [rows, [edge('a', 'b'), edge('b', 'a')], 'CYCLE'],
    [[rows[0], { ...rows[1], projeto_id: 'another' }], [edge('a', 'b')], 'CROSS_PROJECT'],
    [rows, [edge('a', 'b', -1)], 'INVALID_LAG'],
    [[rows[0], { ...rows[1], data_limite: null }], [edge('a', 'b')], 'MISSING_DATES'],
    [[rows[0], { ...rows[1], data_inicio: '2026-11-20' }], [edge('a', 'b')], 'INVALID_DATES'],
  ];
  for (const [items, links, code] of cases) {
    assert.equal(calendarDependencyIssues(items, links, {}, holiday)[0].code, code);
    const result = proposeCalendarCascade(items, links, {}, holiday);
    assert.equal(result.ok, false); if (!result.ok) assert.equal(result.issues[0].code, code);
  }
  const invalidDraft = proposeCalendarCascade(rows, [], { missing: { data_inicio: '2026-11-18' } }, holiday);
  assert.equal(invalidDraft.ok, false); if (!invalidDraft.ok) assert.equal(invalidDraft.issues[0].code, 'INVALID_DRAFT');
});

test('CPM calculates a branching planned network and distinguishes current scheduling from total network float', () => {
  const { rows, links } = diamond();
  const result = analyzeCriticalPath(rows, links, {}, weekdays);
  assert.equal(result.complete, true);
  assert.equal(result.projectStart, '2026-11-16'); assert.equal(result.networkFinish, '2026-11-24');
  assert.deepEqual(result.networkCriticalIds, ['a', 'b', 'd']); assert.deepEqual(result.criticalIds, ['a', 'b', 'd']);
  const c = result.nodes.find(item => item.id === 'c')!;
  assert.equal(c.durationDays, 2); assert.equal(c.earliestStart, '2026-11-18'); assert.equal(c.earliestFinish, '2026-11-19');
  assert.equal(c.latestStart, '2026-11-20'); assert.equal(c.latestFinish, '2026-11-23');
  assert.equal(c.totalFloatDays, 2); assert.equal(c.scheduledSlackDays, 2); assert.equal(c.schedulingDeviationDays, 0);
  const shifted = analyzeCriticalPath(rows, links, { c: { data_inicio: '2026-11-20', data_limite: '2026-11-23' } }, weekdays);
  assert.equal(shifted.networkFinish, result.networkFinish); // Current starts are not implicit constraints.
  const shiftedC = shifted.nodes.find(item => item.id === 'c')!;
  assert.equal(shiftedC.totalFloatDays, 2); assert.equal(shiftedC.schedulingDeviationDays, 2); assert.equal(shiftedC.scheduledSlackDays, 0);
});

test('contract targets expose negative or positive float without losing the longest network chain', () => {
  const { rows, links } = diamond();
  const tight = analyzeCriticalPath(rows, links, {}, weekdays, { targetDate: '2026-11-23' });
  assert.equal(tight.finishVarianceDays, -1); assert.deepEqual(tight.negativeFloatIds, ['a', 'b', 'd']);
  assert.deepEqual(tight.criticalIds, []); assert.deepEqual(tight.networkCriticalIds, ['a', 'b', 'd']);
  assert.equal(tight.nodes.find(item => item.id === 'c')!.totalFloatDays, 1);
  const loose = analyzeCriticalPath(rows, links, {}, weekdays, { targetDate: '2026-11-26' });
  assert.equal(loose.finishVarianceDays, 2); assert.deepEqual(loose.criticalIds, []);
  assert.deepEqual(loose.networkCriticalIds, ['a', 'b', 'd']);
  assert.ok(loose.nodes.every(item => item.totalFloatDays > 0));
});

test('CPM counts lag over exceptions and normalizes analysis anchors and targets explicitly without mutation', () => {
  const rows = [row('a', '2026-11-20'), row('b', '2026-11-25')];
  const result = analyzeCriticalPath(rows, [edge('a', 'b', 1)], {}, holiday);
  assert.equal(result.complete, true); assert.equal(result.networkFinish, '2026-11-25');
  const normalized = analyzeCriticalPath(rows, [edge('a', 'b', 1)], {}, holiday, { startDate: '2026-11-21', targetDate: '2026-11-29' });
  assert.equal(normalized.projectStart, '2026-11-24'); assert.equal(normalized.targetFinish, '2026-11-28');
  assert.equal(normalized.warnings.length, 2); assert.equal(rows[0].data_inicio, '2026-11-20');
  assert.equal(analyzeCriticalPath(rows, [], {}, holiday, { startDate: '2026-02-30' }).issues[0].code, 'INVALID_ANCHOR');
  assert.equal(analyzeCriticalPath(rows, [], {}, holiday, { targetDate: 'invalid' }).issues[0].code, 'INVALID_TARGET');
});

test('CPM returns no invented metrics for missing, reversed, nonworking or cyclic networks, even on unlinked stages', () => {
  const cases: [GanttModelRow[], GanttDependency[], string][] = [
    [[row('a'), { ...row('b'), data_inicio: null }], [], 'MISSING_DATES'],
    [[row('a', '2026-11-18', '2026-11-16')], [], 'INVALID_DATES'],
    [[row('a', '2026-11-21', '2026-11-24')], [], 'NON_WORKING_BOUNDARY'],
    [[row('a'), row('b')], [edge('a', 'b'), edge('b', 'a')], 'CYCLE'],
    [[row('a'), row('b', undefined, undefined, { projeto_id: 'another' })], [], 'CROSS_PROJECT'],
  ];
  for (const [rows, links, code] of cases) {
    const result = analyzeCriticalPath(rows, links, {}, holiday);
    assert.equal(result.complete, false); assert.equal(result.issues[0].code, code);
    assert.deepEqual(result.nodes, []); assert.equal(result.projectStart, null); assert.equal(result.finishVarianceDays, null);
    assert.deepEqual(result.criticalIds, []);
  }
});

test('not-applicable stages are excluded with warnings and linked exclusions stay incomplete; completed durations remain planned', () => {
  const rows = [row('a', '2026-11-16', '2026-11-17', { status: 'finalizado', can_edit: false }),
    row('b', undefined, undefined, { data_inicio: null, data_limite: null, status: 'n_a', can_edit: false })];
  const result = analyzeCriticalPath(rows, [], {}, weekdays);
  assert.equal(result.complete, true); assert.deepEqual(result.excludedIds, ['b']); assert.equal(result.nodes.length, 1);
  assert.equal(result.nodes[0].durationDays, 2); assert.equal(result.warnings.length, 2);
  const linked = analyzeCriticalPath(rows, [edge('a', 'b')], {}, weekdays);
  assert.equal(linked.complete, false); assert.equal(linked.issues[0].code, 'NOT_APPLICABLE_LINK');
  assert.equal(analyzeCriticalPath([rows[1]], [], {}, weekdays).issues[0].code, 'EMPTY_NETWORK');
  assert.equal(analyzeCriticalPath([row('a'), row('b')], [], {}, weekdays).warnings.length, 1);
});

test('a full deep project network is topologically analyzed without recursion or hiding the scope limit', () => {
  const rows = Array.from({ length: 2000 }, (_, index) => row(`r${index}`));
  const links = rows.slice(1).map((item, index) => edge(rows[index].id, item.id));
  const result = analyzeCriticalPath(rows, links, {}, EVERY_DAY_CALENDAR);
  assert.equal(result.complete, true); assert.equal(result.nodes.length, 2000); assert.equal(result.criticalIds.length, 2000);
  assert.equal(result.networkFinish, isoCalendarDay(calendarDay('2026-11-16')! + 1999));
  const excessive = analyzeCriticalPath([...rows, row('extra')], links, {}, EVERY_DAY_CALENDAR);
  assert.equal(excessive.complete, false); assert.equal(excessive.issues[0].code, 'INCOMPLETE_SCOPE');
});
