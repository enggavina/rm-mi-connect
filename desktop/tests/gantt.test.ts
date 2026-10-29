import test from 'node:test';
import assert from 'node:assert/strict';
import { calendarDay, formatGanttDay, ganttBar, ganttWindow, isoCalendarDay, planningDay, saoPauloDay } from '../src/server/web/gantt';

test('calendar inputs reject rolled-over dates and timestamps require an explicit timezone', () => {
  for (const value of ['2026-02-29', '2026-02-30', '2026-13-01', '2026-00-01', '2026-04-31', '2026-1-01', '', null]) assert.equal(calendarDay(value), null);
  assert.equal(isoCalendarDay(calendarDay('2024-02-29')!), '2024-02-29');
  assert.equal(planningDay('2026-10-29T10:00:00'), null);
  assert.equal(planningDay('2026-02-30T12:00:00Z'), null);
  assert.equal(planningDay('2026-10-29T24:00:00Z'), null);
  assert.equal(planningDay('2026-10-29T12:60:00Z'), null);
  assert.equal(planningDay('2026-10-29'), calendarDay('2026-10-29'));
});

test('São Paulo days stay consistent across UTC midnight and historical daylight-saving changes', () => {
  assert.equal(planningDay('2026-10-29T02:59:59Z'), calendarDay('2026-10-28'));
  assert.equal(planningDay('2026-10-29T03:00:00Z'), calendarDay('2026-10-29'));
  assert.equal(planningDay('2026-10-29T00:00:00-03:00'), calendarDay('2026-10-29'));
  assert.equal(planningDay('2018-12-01T02:00:00Z'), calendarDay('2018-12-01'));
  assert.equal(planningDay('2018-12-01T01:59:59Z'), calendarDay('2018-11-30'));
  assert.equal(saoPauloDay(new Date('invalid')), null);
});

test('default window starts fourteen São Paulo days ago and contains exactly six complete weeks', () => {
  const window = ganttWindow(undefined, new Date('2026-10-29T01:00:00Z'));
  assert.equal(window.isoStart, '2026-10-14');
  assert.equal(isoCalendarDay(window.end), '2026-11-24');
  assert.equal(window.endExclusive - window.start, 42);
  assert.deepEqual(window.ticks.map(tick => tick - window.start), [0, 7, 14, 21, 28, 35]);
  assert.equal(ganttWindow('2026-02-30', new Date('2026-10-29T01:00:00Z')).invalidStart, true);
  assert.equal(formatGanttDay(calendarDay('2026-10-29')!), '29/10/2026');
});

test('planned bars include the final day and clamp exactly to both window edges', () => {
  const window = ganttWindow('2026-10-01', new Date('2026-10-29T12:00:00Z'));
  const bar = ganttBar({ data_inicio: '2026-09-01', data_limite: '2026-12-01' }, window);
  assert.equal(bar.kind, 'bar');
  if (bar.kind === 'bar') { assert.equal(bar.left, 0); assert.equal(bar.width, 100); }
  const first = ganttBar({ data_inicio: '2026-09-01', data_limite: '2026-10-01' }, window);
  assert.equal(first.kind, 'bar');
  if (first.kind === 'bar') { assert.equal(first.left, 0); assert.equal(first.width, 100 / 42); }
  const last = ganttBar({ data_inicio: isoCalendarDay(window.end), data_limite: isoCalendarDay(window.end + 10) }, window);
  assert.equal(last.kind, 'bar');
  if (last.kind === 'bar') { assert.equal(last.left, 41 / 42 * 100); assert.equal(last.width, 100 / 42); }
});

test('missing, reversed and out-of-window periods never manufacture a planned duration', () => {
  const window = ganttWindow('2026-10-01', new Date('2026-10-29T12:00:00Z'));
  assert.deepEqual(ganttBar({ data_limite: '2026-10-20' }, window), { kind: 'missing' });
  assert.deepEqual(ganttBar({ data_inicio: '2026-10-20' }, window), { kind: 'missing' });
  assert.deepEqual(ganttBar({ data_inicio: 'bad', data_limite: '2026-10-20' }, window), { kind: 'invalid' });
  assert.deepEqual(ganttBar({ data_inicio: '2026-10-21', data_limite: '2026-10-20' }, window), { kind: 'invalid' });
  assert.deepEqual(ganttBar({ data_inicio: '2026-10-20T18:00:00Z', data_limite: '2026-10-20T12:00:00Z' }, window), { kind: 'invalid' });
  assert.deepEqual(ganttBar({ data_inicio: '2026-09-01', data_limite: '2026-09-30' }, window), { kind: 'outside' });
  assert.deepEqual(ganttBar({ data_inicio: isoCalendarDay(window.endExclusive), data_limite: '2026-12-01' }, window), { kind: 'outside' });
});

test('overdue uses the local deadline day and completed or N/A activities never turn red', () => {
  const window = ganttWindow('2026-10-01', new Date('2026-10-29T12:00:00Z'));
  const row = { data_inicio: '2026-10-10', data_limite: '2026-10-28', status: 'em_dia' };
  const overdue = ganttBar(row, window);
  assert.equal(overdue.kind === 'bar' && overdue.overdue, true);
  const dueToday = ganttBar({ ...row, data_limite: '2026-10-29' }, window);
  assert.equal(dueToday.kind === 'bar' && dueToday.overdue, false);
  const complete = ganttBar({ ...row, status: 'finalizado' }, window);
  assert.equal(complete.kind === 'bar' && complete.complete, true);
  assert.equal(complete.kind === 'bar' && complete.overdue, false);
  const na = ganttBar({ ...row, status: 'n_a' }, window);
  assert.equal(na.kind === 'bar' && na.overdue, false);
});
