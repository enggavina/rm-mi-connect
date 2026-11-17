import { calendarDay, formatGanttDay, isoCalendarDay, planningDay } from '@/server/web/gantt';

export type CapacityResource = {
  id: string; name: string; kind: 'pessoa' | 'maquina'; active: boolean;
  weekly_minutes: number[]; exceptions: { date: string; minutes: number; label: string }[];
  updated_at: string; version: string;
};
export type CapacityBooking = {
  id: string; resource_id: string; allocation_id: string; day: string; minutes: number; updated_at: string;
  project_id: string; numero_projeto: string | null; cell_name: string | null; status: string | null;
  retired: boolean; project_closed: boolean; planned_start: string | null; planned_end: string | null;
  project_working: boolean;
};
export type CapacityDiagnostic = { code: string; message: string };
export type CapacityDayLoad = {
  date: string; availableMinutes: number | null; bookedMinutes: number; remainingMinutes: number | null;
  overloaded: boolean | null; bookings: CapacityBooking[];
};
export type CapacityTotals = {
  availableMinutes: number | null; bookedMinutes: number; remainingMinutes: number | null;
  overloadedDays: number; unknownAvailabilityDays: number; bookingCount: number;
};
export type CapacityLoadRow = { resource: CapacityResource; days: CapacityDayLoad[]; totals: CapacityTotals };
export type CapacityLoad = { start: string; end: string; days: 7 | 14 | 28; rows: CapacityLoadRow[]; totals: Record<'pessoa' | 'maquina', CapacityTotals> };
const MIN_DAY = calendarDay('1900-01-01')!, MAX_DAY = calendarDay('2200-12-31')!;
const validMinutes = (value: number) => Number.isInteger(value) && value >= 0 && value <= 1440;
const weekday = (day: number) => ((day + 3) % 7 + 7) % 7;
function validCalendar(resource: CapacityResource): boolean {
  if (typeof resource.active !== 'boolean' || !Array.isArray(resource.weekly_minutes) || resource.weekly_minutes.length !== 7
    || !resource.weekly_minutes.every(validMinutes) || !Array.isArray(resource.exceptions) || resource.exceptions.length > 366) return false;
  const dates = new Set<string>();
  for (const entry of resource.exceptions) {
    const day = calendarDay(entry.date);
    if (day === null || day < MIN_DAY || day > MAX_DAY || !validMinutes(entry.minutes) || dates.has(entry.date)) return false;
    dates.add(entry.date);
  }
  return true;
}

/** Weekly availability starts on Monday. Zero is known unavailable; null is invalid/unknown. */
export function availabilityMinutes(resource: CapacityResource, date: string): number | null {
  const day = calendarDay(date);
  if (day === null || day < MIN_DAY || day > MAX_DAY || !validCalendar(resource)) return null;
  if (!resource.active) return 0;
  return resource.exceptions.find(entry => entry.date === date)?.minutes ?? resource.weekly_minutes[weekday(day)];
}

const emptyTotals = (): CapacityTotals => ({ availableMinutes: 0, bookedMinutes: 0, remainingMinutes: 0, overloadedDays: 0, unknownAvailabilityDays: 0, bookingCount: 0 });
function summarize(days: readonly CapacityDayLoad[]): CapacityTotals {
  const result = emptyTotals();
  for (const day of days) {
    result.bookedMinutes += day.bookedMinutes; result.bookingCount += day.bookings.length;
    result.overloadedDays += Number(day.overloaded === true);
    if (day.availableMinutes === null) { result.availableMinutes = null; result.unknownAvailabilityDays++; }
    else if (result.availableMinutes !== null) result.availableMinutes += day.availableMinutes;
  }
  result.remainingMinutes = result.availableMinutes === null ? null : result.availableMinutes - result.bookedMinutes;
  return result;
}
function addTotals(target: CapacityTotals, source: CapacityTotals) {
  target.availableMinutes = target.availableMinutes === null || source.availableMinutes === null ? null : target.availableMinutes + source.availableMinutes;
  target.bookedMinutes += source.bookedMinutes; target.overloadedDays += source.overloadedDays;
  target.unknownAvailabilityDays += source.unknownAvailabilityDays; target.bookingCount += source.bookingCount;
  target.remainingMinutes = target.availableMinutes === null ? null : target.availableMinutes - target.bookedMinutes;
}

/** Daily buckets count each resource once across every cell/project. Historical
 * and conflicting bookings remain demand until an explicit correction removes them. */
export function dailyLoad(resources: readonly CapacityResource[], bookings: readonly CapacityBooking[], start: string, days: 7 | 14 | 28): CapacityLoad {
  const first = calendarDay(start);
  if (first === null || first < MIN_DAY || first + days - 1 > MAX_DAY || ![7, 14, 28].includes(days)
    || resources.length > 200 || bookings.length > 10000 || new Set(resources.map(resource => resource.id)).size !== resources.length
    || new Set(bookings.map(booking => booking.id)).size !== bookings.length) throw new RangeError('Consulta de capacidade inválida ou incompleta.');
  const resourceIds = new Set(resources.map(resource => resource.id));
  const buckets = new Map<string, Map<string, CapacityBooking[]>>();
  for (const booking of bookings) {
    if (!resourceIds.has(booking.resource_id) || !Number.isInteger(booking.minutes) || booking.minutes <= 0 || booking.minutes > 1440) throw new RangeError('Reserva inválida ou recurso ausente no conjunto completo.');
    const day = calendarDay(booking.day);
    if (day === null) throw new RangeError('Data inválida de reserva.');
    if (day < first || day >= first + days) continue;
    let byDate = buckets.get(booking.resource_id); if (!byDate) { byDate = new Map(); buckets.set(booking.resource_id, byDate); }
    const list = byDate.get(booking.day) ?? []; list.push(booking); byDate.set(booking.day, list);
  }
  const totals = { pessoa: emptyTotals(), maquina: emptyTotals() };
  const rows = resources.map(resource => {
    if (resource.kind !== 'pessoa' && resource.kind !== 'maquina') throw new RangeError('Tipo de recurso inválido.');
    const calendarValid = validCalendar(resource), exceptions = new Map((Array.isArray(resource.exceptions) ? resource.exceptions : []).map(entry => [entry.date, entry.minutes]));
    const dates = Array.from({ length: days }, (_, offset): CapacityDayLoad => {
      const day = first + offset, date = isoCalendarDay(day), booked = buckets.get(resource.id)?.get(date) ?? [];
      const availableMinutes = calendarValid ? resource.active ? exceptions.get(date) ?? resource.weekly_minutes[weekday(day)] : 0 : null;
      const bookedMinutes = booked.reduce((sum, booking) => sum + booking.minutes, 0);
      return { date, availableMinutes, bookedMinutes, remainingMinutes: availableMinutes === null ? null : availableMinutes - bookedMinutes,
        overloaded: availableMinutes === null ? null : bookedMinutes > availableMinutes, bookings: booked };
    });
    const row = { resource, days: dates, totals: summarize(dates) }; addTotals(totals[resource.kind], row.totals); return row;
  });
  return { start, end: isoCalendarDay(first + days - 1), days, rows, totals };
}

/** Diagnostics never erase a reservation or pretend a status released a resource. */
export function bookingDiagnostics(booking: CapacityBooking, resource?: CapacityResource): CapacityDiagnostic[] {
  const issues: CapacityDiagnostic[] = [];
  if (!resource || resource.id !== booking.resource_id) issues.push({ code: 'RESOURCE_MISSING', message: 'O recurso desta reserva não está no conjunto consultado.' });
  else if (!resource.active) issues.push({ code: 'RESOURCE_INACTIVE', message: 'O recurso está inativo; a reserva continua registrada.' });
  const bookedDay = calendarDay(booking.day), start = planningDay(booking.planned_start), end = planningDay(booking.planned_end);
  if (bookedDay === null) issues.push({ code: 'INVALID_DAY', message: 'A data da reserva é inválida.' });
  if (booking.planned_start === null || booking.planned_end === null) issues.push({ code: 'MISSING_DATES', message: 'A etapa está sem intervalo completo no Gantt.' });
  else if (start === null || end === null || end < start) issues.push({ code: 'INVALID_DATES', message: 'O intervalo da etapa no Gantt é inválido.' });
  else if (bookedDay !== null && (bookedDay < start || bookedDay > end)) issues.push({ code: 'OUTSIDE_GANTT', message: 'A reserva está fora das datas atuais da etapa no Gantt.' });
  if (booking.project_working === false) issues.push({ code: 'PROJECT_NON_WORKING', message: 'A reserva está em dia sem trabalho no calendário atual do projeto.' });
  if (booking.retired) issues.push({ code: 'ALLOCATION_RETIRED', message: 'A etapa foi retirada; a reserva foi preservada para revisão.' });
  if (booking.project_closed) issues.push({ code: 'PROJECT_CLOSED', message: 'O projeto está encerrado; a reserva foi preservada para revisão.' });
  if (booking.status === 'finalizado') issues.push({ code: 'ALLOCATION_DONE', message: 'A etapa está finalizada; a reserva continua registrada.' });
  if (booking.status === 'n_a') issues.push({ code: 'ALLOCATION_NOT_APPLICABLE', message: 'A etapa está como não aplicável; a reserva continua registrada.' });
  return issues;
}

/** Input is hours, output is integer minutes. Fractions requiring partial minutes
 * are rejected rather than rounded into capacity. */
export function hoursInputToMinutes(input: string): number | null {
  const text = input.trim();
  if (!/^\d{1,2}(?:[.,]\d{1,20})?$/.test(text)) return null;
  const hours = Number(text.replace(',', '.'));
  if (!Number.isFinite(hours) || hours > 24) return null;
  const value = hours * 60, minutes = Math.round(value);
  // A stored minute rendered as hours can be a repeating decimal (20 / 60).
  // Tolerate only floating point round-trip error, not partial-minute input.
  return Math.abs(value - minutes) <= 1e-8 && validMinutes(minutes) ? minutes : null;
}
export function formatMinutesPt(minutes: number | null): string {
  if (minutes === null || !Number.isSafeInteger(minutes)) return 'Não informado';
  const sign = minutes < 0 ? '−' : '', value = Math.abs(minutes), hours = Math.floor(value / 60), remaining = value % 60;
  return remaining ? `${sign}${hours} h ${String(remaining).padStart(2, '0')} min` : `${sign}${hours} h`;
}
export function utilizationLabel(bookedMinutes: number, availableMinutes: number | null): string {
  if (!Number.isSafeInteger(bookedMinutes) || bookedMinutes < 0 || availableMinutes === null || !Number.isSafeInteger(availableMinutes) || availableMinutes < 0) return 'Disponibilidade não informada';
  if (!availableMinutes) return bookedMinutes ? 'Reserva sem disponibilidade' : 'Sem disponibilidade';
  return `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 }).format(bookedMinutes / availableMinutes * 100)}% da disponibilidade`;
}

export type CapacityBookingContext = Omit<CapacityBooking, 'id' | 'resource_id' | 'allocation_id' | 'day' | 'minutes'>;
export type CapacityBookingPatchDay = { date: string; minutes: number };
/** Only explicit pair/day patches replace or remove rows. Missing days and all
 * other resources/allocations retain their original objects and metadata. */
export function previewBookings(bookings: readonly CapacityBooking[], resourceId: string, allocationId: string, patchDays: readonly CapacityBookingPatchDay[],
  context?: CapacityBookingContext | ((day: string) => CapacityBookingContext)): CapacityBooking[] {
  const patches = new Map<string, number>();
  for (const entry of patchDays) {
    const day = entry.date;
    if (calendarDay(day) === null || !validMinutes(entry.minutes) || patches.has(day)) throw new RangeError('Prévia de reservas inválida.');
    patches.set(day, entry.minutes);
  }
  const output: CapacityBooking[] = [];
  for (const booking of bookings) {
    if (booking.resource_id !== resourceId || booking.allocation_id !== allocationId || !patches.has(booking.day)) { output.push(booking); continue; }
    const minutes = patches.get(booking.day)!; patches.delete(booking.day);
    if (minutes) output.push(minutes === booking.minutes ? booking : { ...booking, minutes });
  }
  for (const [day, minutes] of patches) {
    if (!minutes) continue;
    if (!context) throw new RangeError('A prévia de uma nova reserva exige o contexto atual da etapa.');
    const metadata = typeof context === 'function' ? context(day) : context;
    output.push({ ...metadata, id: `preview:${resourceId}:${allocationId}:${day}`, resource_id: resourceId, allocation_id: allocationId, day, minutes });
  }
  return output;
}
type ResourceMetadata = Partial<Pick<CapacityResource, 'name' | 'kind' | 'active' | 'weekly_minutes' | 'exceptions'>>;
export function previewResource(resources: readonly CapacityResource[], resource: CapacityResource): CapacityResource[];
export function previewResource(resources: readonly CapacityResource[], resourceId: string, patch: ResourceMetadata): CapacityResource[];
export function previewResource(resources: readonly CapacityResource[], resourceOrId: CapacityResource | string, patch?: ResourceMetadata): CapacityResource[] {
  if (typeof resourceOrId === 'string') {
    if (!resources.some(resource => resource.id === resourceOrId)) throw new RangeError('Recurso ausente na prévia.');
    return resources.map(resource => resource.id === resourceOrId ? { ...resource, ...patch } : resource);
  }
  return resources.some(resource => resource.id === resourceOrId.id) ? resources.map(resource => resource.id === resourceOrId.id ? resourceOrId : resource) : [...resources, resourceOrId];
}

export function capacityDateLabel(value: string): string { const day = calendarDay(value); return day === null ? 'Data inválida' : formatGanttDay(day); }
