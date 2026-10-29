const DAY_MS = 86_400_000;
export const GANTT_DAYS = 42;
const localDate = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' });

/** An integer calendar day, independent of the machine's timezone and DST. */
export function calendarDay(value: unknown): number | null {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  const parsed = new Date(0); parsed.setUTCHours(0, 0, 0, 0); parsed.setUTCFullYear(year, month - 1, day);
  return parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day ? parsed.getTime() / DAY_MS : null;
}

export function saoPauloDay(instant: Date): number | null {
  if (!Number.isFinite(instant.getTime())) return null;
  const parts = localDate.formatToParts(instant);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find(value => value.type === type)?.value;
  return calendarDay(`${part('year')?.padStart(4, '0')}-${part('month')}-${part('day')}`);
}

/** Date-only inputs already denote a local day; database instants carry an explicit offset. */
export function planningDay(value: unknown): number | null {
  const day = calendarDay(value);
  if (day !== null) return day;
  if (typeof value !== 'string') return null;
  const timestamp = value.match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:\d{2})$/i);
  if (!timestamp || calendarDay(timestamp[1]) === null || Number(timestamp[2]) > 23 || Number(timestamp[3]) > 59 || Number(timestamp[4] ?? 0) > 59) return null;
  return saoPauloDay(new Date(value));
}

export function isoCalendarDay(day: number): string { return new Date(day * DAY_MS).toISOString().split('T')[0]; }
export function formatGanttDay(day: number, short = false): string {
  const value = new Date(day * DAY_MS);
  const date = `${String(value.getUTCDate()).padStart(2, '0')}/${String(value.getUTCMonth() + 1).padStart(2, '0')}`;
  return short ? date : `${date}/${value.getUTCFullYear()}`;
}

export function ganttWindow(requestedStart?: unknown, now = new Date()) {
  const today = saoPauloDay(now);
  if (today === null) throw new Error('Data atual inválida.');
  const parsed = calendarDay(requestedStart);
  const start = parsed ?? today - 14;
  return { start, end: start + GANTT_DAYS - 1, endExclusive: start + GANTT_DAYS, today,
    isoStart: isoCalendarDay(start), invalidStart: requestedStart != null && requestedStart !== '' && parsed === null,
    ticks: Array.from({ length: 6 }, (_, index) => start + index * 7) };
}

type IntervalInput = { data_inicio?: unknown; data_limite?: unknown; status?: unknown };
type Interval = { kind: 'missing' | 'invalid' | 'outside' } | { kind: 'bar'; start: number; end: number; left: number; width: number; overdue: boolean; complete: boolean };
export function ganttBar(row: IntervalInput, window: ReturnType<typeof ganttWindow>): Interval {
  if (!row.data_inicio || !row.data_limite) return { kind: 'missing' };
  const start = planningDay(row.data_inicio), end = planningDay(row.data_limite);
  if (start === null || end === null || end < start) return { kind: 'invalid' };
  if (calendarDay(row.data_inicio) === null && calendarDay(row.data_limite) === null
    && Date.parse(String(row.data_limite)) < Date.parse(String(row.data_inicio))) return { kind: 'invalid' };
  const visibleStart = Math.max(start, window.start), visibleEnd = Math.min(end + 1, window.endExclusive);
  if (visibleEnd <= visibleStart) return { kind: 'outside' };
  const complete = row.status === 'finalizado';
  return { kind: 'bar', start, end, left: (visibleStart - window.start) / GANTT_DAYS * 100, width: (visibleEnd - visibleStart) / GANTT_DAYS * 100,
    complete, overdue: !complete && row.status !== 'n_a' && end < window.today };
}
