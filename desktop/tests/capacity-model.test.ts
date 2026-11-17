import assert from 'node:assert/strict';
import test from 'node:test';
import { performance } from 'node:perf_hooks';
import { availabilityMinutes, bookingDiagnostics, dailyLoad, formatMinutesPt, hoursInputToMinutes, previewBookings, previewResource, utilizationLabel,
  type CapacityResource, type CapacityBooking, type CapacityBookingContext } from '../src/components/web/capacity-model';

const resource = (patch: Partial<CapacityResource> = {}): CapacityResource => ({
  id: 'r1', name: 'Recurso informado', kind: 'pessoa', active: true, weekly_minutes: [480, 480, 480, 480, 480, 0, 0],
  exceptions: [], updated_at: '2026-11-17T12:00:00.000001Z', version: 'revision', ...patch,
});
const booking = (patch: Partial<CapacityBooking> = {}): CapacityBooking => ({
  id: 'b1', resource_id: 'r1', allocation_id: 'a1', day: '2026-11-17', minutes: 240, updated_at: '2026-11-17T12:00:00.000001Z',
  project_id: 'p1', numero_projeto: 'OS real', cell_name: 'Célula', status: 'pendente', retired: false, project_closed: false,
  planned_start: '2026-11-17T15:00:00.123456Z', planned_end: '2026-11-20T15:00:00.123456Z', project_working: true, ...patch,
});
const context = (): CapacityBookingContext => {
  const { id: _id, resource_id: _resource, allocation_id: _allocation, day: _day, minutes: _minutes, ...metadata } = booking(); return metadata;
};

test('availability uses Monday-first exact minutes, inclusive dated overrides and no inferred weekend hours', () => {
  const item = resource({ exceptions: [{ date: '2026-11-17', minutes: 0, label: 'Indisponível' }, { date: '2026-11-21', minutes: 180, label: 'Disponibilidade informada' }] });
  assert.equal(availabilityMinutes(item, '2026-11-16'), 480);
  assert.equal(availabilityMinutes(item, '2026-11-17'), 0);
  assert.equal(availabilityMinutes(item, '2026-11-21'), 180);
  assert.equal(availabilityMinutes(item, '2026-11-22'), 0);
  assert.equal(availabilityMinutes(resource({ active: false }), '2026-11-17'), 0);
});

test('invalid calendars and dates remain unknown, distinct from valid explicit zero availability', () => {
  for (const item of [resource({ weekly_minutes: [480] }), resource({ weekly_minutes: [480, 480, -1, 480, 480, 0, 0] }), resource({ weekly_minutes: [480, 480, 0.5, 480, 480, 0, 0] }),
    resource({ exceptions: [{ date: '2026-02-29', minutes: 0, label: 'Inválido' }] }), resource({ exceptions: [{ date: '2026-11-17', minutes: 0, label: 'A' }, { date: '2026-11-17', minutes: 30, label: 'B' }] })]) {
    assert.equal(availabilityMinutes(item, '2026-11-17'), null);
    const load = dailyLoad([item], [booking()], '2026-11-17', 7);
    assert.equal(load.rows[0].days[0].availableMinutes, null); assert.equal(load.rows[0].days[0].bookedMinutes, 240);
    assert.equal(load.rows[0].days[0].overloaded, null); assert.equal(load.rows[0].totals.remainingMinutes, null);
    assert.equal(load.totals.pessoa.availableMinutes, null); assert.equal(load.totals.pessoa.unknownAvailabilityDays, 7);
  }
  assert.equal(availabilityMinutes(resource(), '2026-11-17T03:00:00Z'), null);
  assert.equal(availabilityMinutes(resource(), '1899-12-31'), null);
  assert.equal(availabilityMinutes(resource(), '2201-01-01'), null);
  assert.equal(availabilityMinutes(resource({ weekly_minutes: [0, 0, 0, 0, 0, 0, 0] }), '2026-11-17'), 0);
});

test('daily loads share one resource budget across projects and keep person and machine units separate', () => {
  const resources = [resource(), resource({ id: 'm1', kind: 'maquina', weekly_minutes: [240, 240, 240, 240, 240, 0, 0] })];
  const bookings = [booking({ minutes: 300 }), booking({ id: 'b2', project_id: 'p2', allocation_id: 'a2', minutes: 240 }), booking({ id: 'b3', resource_id: 'm1', minutes: 240 }), booking({ id: 'b4', day: '2026-12-01' })];
  const result = dailyLoad(resources, bookings, '2026-11-17', 7), day = result.rows[0].days[0];
  assert.equal(result.end, '2026-11-23'); assert.equal(day.bookedMinutes, 540); assert.equal(day.availableMinutes, 480); assert.equal(day.remainingMinutes, -60); assert.equal(day.overloaded, true);
  assert.equal(day.bookings.length, 2); assert.equal(result.rows[1].days[0].overloaded, false);
  assert.equal(result.totals.pessoa.bookedMinutes, 540); assert.equal(result.totals.maquina.bookedMinutes, 240);
  assert.equal(result.totals.pessoa.availableMinutes, 2400); assert.equal(result.totals.maquina.availableMinutes, 1200);
  assert.equal(result.totals.pessoa.overloadedDays, 1); assert.equal(result.totals.pessoa.bookingCount, 2);
});

test('inactive, completed, retired and closed context never silently frees reserved capacity', () => {
  const item = resource({ active: false }), row = booking({ retired: true, project_closed: true, status: 'finalizado', project_working: false });
  const load = dailyLoad([item], [row], '2026-11-17', 7);
  assert.equal(load.rows[0].days[0].bookedMinutes, 240); assert.equal(load.rows[0].days[0].availableMinutes, 0); assert.equal(load.rows[0].days[0].overloaded, true);
  assert.deepEqual(bookingDiagnostics(row, item).map(issue => issue.code), ['RESOURCE_INACTIVE', 'PROJECT_NON_WORKING', 'ALLOCATION_RETIRED', 'PROJECT_CLOSED', 'ALLOCATION_DONE']);
  assert.ok(bookingDiagnostics(booking({ status: 'n_a' }), resource()).some(issue => issue.code === 'ALLOCATION_NOT_APPLICABLE'));
});

test('booking diagnostics use São Paulo date boundaries and preserve missing/invalid/outside context', () => {
  assert.deepEqual(bookingDiagnostics(booking({ planned_start: '2026-11-18T01:00:00Z', planned_end: '2026-11-18T02:59:59.999999Z' }), resource()), []);
  assert.ok(bookingDiagnostics(booking({ planned_start: null }), resource()).some(issue => issue.code === 'MISSING_DATES'));
  assert.ok(bookingDiagnostics(booking({ planned_start: 'bad' }), resource()).some(issue => issue.code === 'INVALID_DATES'));
  assert.ok(bookingDiagnostics(booking({ planned_start: '2026-11-20', planned_end: '2026-11-17' }), resource()).some(issue => issue.code === 'INVALID_DATES'));
  assert.ok(bookingDiagnostics(booking({ day: '2026-11-21' }), resource()).some(issue => issue.code === 'OUTSIDE_GANTT'));
  assert.ok(bookingDiagnostics(booking(), undefined).some(issue => issue.code === 'RESOURCE_MISSING'));
  assert.ok(bookingDiagnostics(booking({ day: 'bad' }), resource()).some(issue => issue.code === 'INVALID_DAY'));
});

test('hours input converts exact decimal hours only, with comma/dot and explicit zero accepted', () => {
  for (const [input, expected] of [['8', 480], ['8.5', 510], ['8,5', 510], ['0.1', 6], ['0,05', 3], ['23.95', 1437], ['24', 1440], [' 0 ', 0], ['8.50', 510]] as const) assert.equal(hoursInputToMinutes(input), expected);
  for (const input of ['', ' ', '-1', '25', '24.01', '0.01', '8:30', '1e1', '0x10', '1,2.3', 'Infinity', 'NaN', '.5', '000']) assert.equal(hoursInputToMinutes(input), null, input);
  for (let minutes = 0; minutes <= 1440; minutes++) assert.equal(hoursInputToMinutes(String(minutes / 60)), minutes, `Round trip ${minutes} minutes`);
  assert.equal(hoursInputToMinutes('0.33333'), null);
});

test('minute labels preserve fractional hours and zero-denominator utilization is never infinity or zero percent', () => {
  assert.equal(formatMinutesPt(0), '0 h'); assert.equal(formatMinutesPt(510), '8 h 30 min'); assert.equal(formatMinutesPt(-75), '−1 h 15 min'); assert.equal(formatMinutesPt(null), 'Não informado');
  assert.equal(utilizationLabel(240, 480), '50% da disponibilidade'); assert.equal(utilizationLabel(0, 480), '0% da disponibilidade');
  assert.equal(utilizationLabel(1, 0), 'Reserva sem disponibilidade'); assert.equal(utilizationLabel(0, 0), 'Sem disponibilidade');
  assert.equal(utilizationLabel(10, null), 'Disponibilidade não informada');
});

test('preview edits only explicitly supplied pair/days and never mutates original metadata or other reservations', () => {
  const base = [booking(), booking({ id: 'b2', allocation_id: 'a2' }), booking({ id: 'b3', resource_id: 'r2' }), booking({ id: 'b4', day: '2026-11-18' })];
  const original = structuredClone(base);
  const result = previewBookings(base, 'r1', 'a1', [{ date: '2026-11-17', minutes: 120 }, { date: '2026-11-18', minutes: 0 }, { date: '2026-11-19', minutes: 90 }], day => ({ ...context(), project_working: day !== '2026-11-19' }));
  assert.deepEqual(base, original); assert.equal(result.length, 4);
  assert.equal(result[0].minutes, 120); assert.equal(result[0].updated_at, base[0].updated_at); assert.equal(result[0].planned_start, base[0].planned_start);
  assert.equal(result[1], base[1]); assert.equal(result[2], base[2]);
  assert.equal(result[3].day, '2026-11-19'); assert.equal(result[3].minutes, 90); assert.equal(result[3].project_working, false);
  assert.throws(() => previewBookings(base, 'r1', 'a1', [{ date: '2026-11-19', minutes: 90 }]), /contexto/);
  assert.equal(previewBookings(base, 'r1', 'a1', [{ date: '2026-11-17', minutes: 240 }])[0], base[0]);
  assert.throws(() => previewBookings(base, 'r1', 'a1', [{ date: '2026-11-17', minutes: 1 }, { date: '2026-11-17', minutes: 2 }]), /inválida/);
});

test('resource previews preserve all unrelated resources and exact revisions', () => {
  const first = resource(), second = resource({ id: 'r2' }), list = [first, second];
  const changed = previewResource(list, 'r1', { active: false });
  assert.equal(changed[0].active, false); assert.equal(first.active, true); assert.equal(changed[0].version, first.version); assert.equal(changed[1], second);
  const added = previewResource(list, resource({ id: 'r3' })); assert.equal(added.length, 3); assert.equal(added[0], first);
  assert.throws(() => previewResource(list, 'unknown', { active: false }), /ausente/);
});

test('windows handle leap days and DST as civil dates, rejecting partial/duplicate/foreign sets', () => {
  assert.equal(dailyLoad([resource()], [], '2028-02-27', 7).rows[0].days[2].date, '2028-02-29');
  assert.equal(dailyLoad([resource()], [], '2018-11-01', 7).end, '2018-11-07');
  assert.throws(() => dailyLoad([resource()], [], '2026-02-29', 7), /inválida/);
  assert.throws(() => dailyLoad([resource(), resource()], [], '2026-11-17', 7), /incompleta/);
  assert.throws(() => dailyLoad([resource()], [booking(), booking()], '2026-11-17', 7), /incompleta/);
  assert.throws(() => dailyLoad([resource()], [booking({ resource_id: 'foreign' })], '2026-11-17', 7), /ausente/);
  assert.throws(() => dailyLoad([resource()], [], '2200-12-30', 7), /inválida/);
});

test('maximum daily workload is bucketed once and remains bounded at 200 resources / 10000 bookings', () => {
  const resources = Array.from({ length: 200 }, (_, index) => resource({ id: `r${index}` }));
  const bookings = Array.from({ length: 10000 }, (_, index) => booking({ id: `b${index}`, resource_id: `r${index % 200}`, allocation_id: `a${index}`, minutes: 15 }));
  const started = performance.now(), result = dailyLoad(resources, bookings, '2026-11-17', 28), elapsed = performance.now() - started;
  assert.equal(result.rows.length, 200); assert.equal(result.totals.pessoa.bookingCount, 10000); assert.equal(result.totals.pessoa.bookedMinutes, 150000);
  assert.equal(result.rows[0].days[0].bookedMinutes, 750); assert.ok(elapsed < 2000, `Daily bucketing took ${elapsed} ms`);
  assert.throws(() => dailyLoad([...resources, resource({ id: 'extra' })], bookings, '2026-11-17', 28), /incompleta/);
});
