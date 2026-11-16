import { calendarDay, isoCalendarDay, planningDay, saoPauloDay } from '@/server/web/gantt';

/** Client-safe calendar mathematics. No business mutation or resource scheduling lives here. */
export const plannerDays = [14, 42, 90] as const;
export type PlannerDays = typeof plannerDays[number];
export const MAX_GANTT_LAG_DAYS = 3650;
const MIN_DAY = calendarDay('0001-01-01')!;
const MAX_DAY = calendarDay('9999-12-31')!;
export const GANTT_EDIT_MIN_DATE = '1900-01-01';
export const GANTT_EDIT_MAX_DATE = '2200-12-31';
const EDIT_MIN_DAY = calendarDay(GANTT_EDIT_MIN_DATE)!;
const EDIT_MAX_DAY = calendarDay(GANTT_EDIT_MAX_DATE)!;

export type GanttDates = { data_inicio: string | null; data_limite: string | null };
export type GanttModelRow = GanttDates & {
  id: string; projeto_id: string; updated_at: string; status: string | null; can_edit: boolean;
};
export type GanttDependency = { projeto_id?: string; predecessor_id: string; successor_id: string; lag_days: number };
/** An omitted field is untouched, including its original offset and microseconds. */
export type GanttDateDraft = Partial<GanttDates>;
export type GanttDrafts = Record<string, GanttDateDraft>;
export type GanttDateItem = { id: string; expected_updated_at: string; changes: GanttDateDraft };
export type GanttIssue = {
  code: string; message: string; allocation_id?: string; predecessor_id?: string; successor_id?: string; earliest_start?: string;
};
export type GanttDraftResult = { ok: true; draft: GanttDateDraft } | { ok: false; code: string; error: string };
export type PlannerWindow = {
  days: PlannerDays; start: number; end: number; endExclusive: number; today: number;
  isoStart: string; isoEnd: string; ticks: number[]; invalidStart: boolean; invalidDays: boolean;
};
export type PlanningInterval = { kind: 'missing' | 'invalid' } | { kind: 'valid'; start: number; end: number; durationDays: number };
export type PlannerBar = { kind: 'missing' | 'invalid' | 'outside' } | {
  kind: 'bar'; start: number; end: number; durationDays: number; left: number; width: number;
  clippedStart: boolean; clippedEnd: boolean; overdue: boolean; complete: boolean;
};

export function plannerWindow(requestedStart?: unknown, requestedDays?: unknown, now = new Date()): PlannerWindow {
  const today = saoPauloDay(now);
  if (today === null) throw new Error('Data atual inválida.');
  const numericDays = typeof requestedDays === 'string' && /^\d+$/.test(requestedDays) ? Number(requestedDays) : requestedDays;
  const supported = plannerDays.includes(numericDays as PlannerDays);
  const days: PlannerDays = supported ? numericDays as PlannerDays : 42;
  const suppliedStart = requestedStart != null && requestedStart !== '';
  const parsed = calendarDay(requestedStart);
  const validStart = parsed !== null && parsed + days - 1 <= MAX_DAY;
  const fallbackStart = Math.max(MIN_DAY, Math.min(MAX_DAY - days + 1, today - (days === 14 ? 3 : 14)));
  const start = validStart ? parsed : fallbackStart;
  const step = days === 14 ? 1 : days === 42 ? 7 : 14;
  return { days, start, end: start + days - 1, endExclusive: start + days, today,
    isoStart: isoCalendarDay(start), isoEnd: isoCalendarDay(start + days - 1),
    ticks: Array.from({ length: Math.ceil(days / step) }, (_, index) => start + index * step),
    invalidStart: suppliedStart && !validStart,
    invalidDays: requestedDays != null && requestedDays !== '' && !supported };
}

export function dateInput(value: unknown): string {
  const parsed = planningDay(value);
  return parsed === null ? '' : isoCalendarDay(parsed);
}

export function planningInterval(row: GanttDates): PlanningInterval {
  if (!row.data_inicio || !row.data_limite) return { kind: 'missing' };
  const start = planningDay(row.data_inicio), end = planningDay(row.data_limite);
  if (start === null || end === null || end < start) return { kind: 'invalid' };
  if (calendarDay(row.data_inicio) === null && calendarDay(row.data_limite) === null
    && Date.parse(row.data_limite) < Date.parse(row.data_inicio)) return { kind: 'invalid' };
  return { kind: 'valid', start, end, durationDays: end - start + 1 };
}

export function plannerBar(row: GanttDates & { status?: string | null }, window: PlannerWindow): PlannerBar {
  const interval = planningInterval(row);
  if (interval.kind !== 'valid') return interval;
  const visibleStart = Math.max(interval.start, window.start), visibleEnd = Math.min(interval.end + 1, window.endExclusive);
  if (visibleEnd <= visibleStart) return { kind: 'outside' };
  const complete = row.status === 'finalizado';
  return { kind: 'bar', start: interval.start, end: interval.end, durationDays: interval.durationDays,
    left: (visibleStart - window.start) / window.days * 100,
    width: (visibleEnd - visibleStart) / window.days * 100, clippedStart: interval.start < window.start,
    clippedEnd: interval.end > window.end, complete,
    overdue: !complete && row.status !== 'n_a' && interval.end < window.today };
}

export function draftDates(row: GanttDates, draft: GanttDateDraft = {}): GanttDates {
  return { data_inicio: Object.hasOwn(draft, 'data_inicio') ? draft.data_inicio! : row.data_inicio,
    data_limite: Object.hasOwn(draft, 'data_limite') ? draft.data_limite! : row.data_limite };
}

const editable = (row: GanttModelRow) => row.can_edit && !['finalizado', 'n_a'].includes(row.status ?? '');
const failure = (code: string, error: string): GanttDraftResult => ({ ok: false, code, error });

function canonicalPatch(row: GanttDates, draft: GanttDateDraft): GanttDateDraft {
  const result: GanttDateDraft = {};
  for (const field of ['data_inicio', 'data_limite'] as const) {
    if (!Object.hasOwn(draft, field)) continue;
    const value = draft[field];
    if (value !== null && (typeof value !== 'string' || calendarDay(value) === null)) throw new Error('O rascunho exige datas válidas no formato AAAA-MM-DD ou ausência explícita.');
    // Invalid historical values can be explicitly cleared; an empty input alone never clears them.
    if (value === null ? row[field] !== null : dateInput(row[field]) !== value) {
      if (value !== null && (value < GANTT_EDIT_MIN_DATE || value > GANTT_EDIT_MAX_DATE)) throw new Error('Informe uma data válida entre 1900 e 2200.');
      result[field] = value;
    }
  }
  return result;
}

const saoPauloClock = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
});

/** Match the server's date-only conversion, including historical daylight saving. */
function saoPauloNoon(value: string): number | null {
  const day = calendarDay(value);
  if (day === null) return null;
  const target = day * 86_400_000 + 12 * 3_600_000;
  let instant = target;
  for (let attempt = 0; attempt < 4; attempt++) {
    const parts = Object.fromEntries(saoPauloClock.formatToParts(instant).map(part => [part.type, part.value]));
    const observedDay = calendarDay(`${parts.year.padStart(4, '0')}-${parts.month}-${parts.day}`);
    if (observedDay === null) return null;
    const observed = observedDay * 86_400_000 + Number(parts.hour) * 3_600_000
      + Number(parts.minute) * 60_000 + Number(parts.second) * 1000;
    if (observed === target) return instant;
    instant += target - observed;
  }
  return null;
}

function effectiveInstant(value: string, changed: boolean): bigint | null {
  const milliseconds = changed || calendarDay(value) !== null ? saoPauloNoon(value) : Date.parse(value);
  if (milliseconds === null || !Number.isFinite(milliseconds)) return null;
  // JS dates retain milliseconds only. PostgreSQL timestamps can carry microseconds.
  const fraction = changed ? '' : value.match(/\.(\d+)(?:Z|[+-]\d{2}(?::?\d{2})?)$/i)?.[1] ?? '';
  const remainder = fraction.slice(3, 9).padEnd(6, '0');
  return BigInt(milliseconds) * 1_000_000n + BigInt(remainder || '0');
}

/** Warn about a real timestamp inversion hidden by a same-day calendar edit. Never rewrites dates. */
export function draftTimingIssue(row: GanttDates, draft: GanttDateDraft = {}): GanttIssue | null {
  let changes: GanttDateDraft;
  try { changes = canonicalPatch(row, draft); } catch { return null; }
  if (!Object.keys(changes).length) return null;
  const effective = draftDates(row, changes);
  if (!effective.data_inicio || !effective.data_limite) return null;
  const startDay = planningDay(effective.data_inicio), endDay = planningDay(effective.data_limite);
  // Calendar inversions and malformed values already have a separate, clearer validation.
  if (startDay === null || startDay !== endDay) return null;
  const start = effectiveInstant(effective.data_inicio, Object.hasOwn(changes, 'data_inicio'));
  const end = effectiveInstant(effective.data_limite, Object.hasOwn(changes, 'data_limite'));
  if (start === null || end === null || end >= start) return null;
  return { code: 'TIME_ORDER', message: 'A alteração faria o prazo ficar antes do horário de início já registrado. Escolha um prazo posterior ou um início anterior.' };
}

export function changeDateDraft(row: GanttModelRow, draft: GanttDateDraft, field: keyof GanttDates, input: string | null): GanttDraftResult {
  if (!editable(row)) return failure('READ_ONLY', 'Esta etapa está disponível somente para consulta.');
  if (field !== 'data_inicio' && field !== 'data_limite') return failure('INVALID_VALUE', 'Campo de data inválido.');
  const value = input === '' ? null : input;
  if (value !== null && calendarDay(value) === null) return failure('INVALID_VALUE', 'Informe uma data válida.');
  if (value !== null && (value < GANTT_EDIT_MIN_DATE || value > GANTT_EDIT_MAX_DATE)) return failure('OUT_OF_RANGE', 'Informe uma data válida entre 1900 e 2200.');
  return { ok: true, draft: canonicalPatch(row, { ...draft, [field]: value }) };
}

export function moveDraft(row: GanttModelRow, draft: GanttDateDraft, delta: number): GanttDraftResult {
  if (!editable(row)) return failure('READ_ONLY', 'Esta etapa está disponível somente para consulta.');
  if (!Number.isSafeInteger(delta)) return failure('INVALID_VALUE', 'O deslocamento deve ser um número inteiro de dias.');
  const interval = planningInterval(draftDates(row, draft));
  if (interval.kind === 'missing') return failure('MISSING_DATES', 'Informe o início e o prazo antes de mover a etapa.');
  if (interval.kind !== 'valid') return failure('INVALID_DATES', 'Corrija as datas antes de mover a etapa.');
  if (interval.start + delta < EDIT_MIN_DAY || interval.end + delta > EDIT_MAX_DAY) return failure('OUT_OF_RANGE', 'Informe datas entre 1900 e 2200.');
  return { ok: true, draft: canonicalPatch(row, { ...draft,
    data_inicio: isoCalendarDay(interval.start + delta), data_limite: isoCalendarDay(interval.end + delta) }) };
}

export function resizeDraft(row: GanttModelRow, draft: GanttDateDraft, edge: 'start' | 'end', delta: number): GanttDraftResult {
  if (!editable(row)) return failure('READ_ONLY', 'Esta etapa está disponível somente para consulta.');
  if (!Number.isSafeInteger(delta) || !['start', 'end'].includes(edge)) return failure('INVALID_VALUE', 'Redimensionamento inválido.');
  const interval = planningInterval(draftDates(row, draft));
  if (interval.kind === 'missing') return failure('MISSING_DATES', 'Informe o início e o prazo antes de redimensionar.');
  if (interval.kind !== 'valid') return failure('INVALID_DATES', 'Corrija as datas antes de redimensionar.');
  const value = edge === 'start' ? Math.min(interval.end, interval.start + delta) : Math.max(interval.start, interval.end + delta);
  if (value < EDIT_MIN_DAY || value > EDIT_MAX_DAY) return failure('OUT_OF_RANGE', 'Informe datas entre 1900 e 2200.');
  return changeDateDraft(row, draft, edge === 'start' ? 'data_inicio' : 'data_limite', isoCalendarDay(value));
}

/** Builds only intentional changes. Expected versions are kept byte-for-byte. */
export function changedDateItems(rows: readonly GanttModelRow[], drafts: Readonly<GanttDrafts>): GanttDateItem[] {
  const ids = new Set(rows.map(row => row.id));
  if (ids.size !== rows.length) throw new Error('O cronograma contém etapas repetidas.');
  if (Object.keys(drafts).some(id => !ids.has(id))) throw new Error('Uma etapa do rascunho não pertence ao cronograma.');
  return rows.flatMap(row => {
    const changes = canonicalPatch(row, drafts[row.id] ?? {});
    if (!Object.keys(changes).length) return [];
    if (!editable(row)) throw new Error('Uma etapa alterada está disponível somente para consulta.');
    return [{ id: row.id, expected_updated_at: row.updated_at, changes }];
  });
}

function dependencyGraph(rows: readonly GanttModelRow[], links: readonly GanttDependency[]) {
  const byId = new Map(rows.map(row => [row.id, row]));
  const issues: GanttIssue[] = [];
  if (byId.size !== rows.length) issues.push({ code: 'DUPLICATE_ALLOCATION', message: 'O cronograma contém etapas repetidas.' });
  const incoming = new Map(rows.map(row => [row.id, [] as GanttDependency[]]));
  const outgoing = new Map(rows.map(row => [row.id, [] as GanttDependency[]]));
  const pairs = new Set<string>();
  for (const link of links) {
    const context = { predecessor_id: link.predecessor_id, successor_id: link.successor_id };
    const before = byId.get(link.predecessor_id), after = byId.get(link.successor_id);
    const pair = JSON.stringify([link.predecessor_id, link.successor_id]);
    if (pairs.has(pair)) { issues.push({ ...context, code: 'DUPLICATE_LINK', message: 'A mesma dependência foi informada mais de uma vez.' }); continue; }
    pairs.add(pair);
    if (!before || !after) { issues.push({ ...context, code: 'MISSING_ENDPOINT', message: 'Uma etapa da dependência não está no conjunto consultado. Recarregue o projeto completo.' }); continue; }
    if (before.id === after.id) { issues.push({ ...context, code: 'SELF_LINK', message: 'Uma etapa não pode depender dela mesma.' }); continue; }
    if (before.projeto_id !== after.projeto_id || (link.projeto_id !== undefined && link.projeto_id !== before.projeto_id)) {
      issues.push({ ...context, code: 'CROSS_PROJECT', message: 'As duas etapas da dependência devem pertencer ao mesmo projeto.' }); continue;
    }
    if (!Number.isInteger(link.lag_days) || link.lag_days < 0 || link.lag_days > MAX_GANTT_LAG_DAYS) {
      issues.push({ ...context, code: 'INVALID_LAG', message: `A espera deve ser um inteiro entre 0 e ${MAX_GANTT_LAG_DAYS} dias.` }); continue;
    }
    incoming.get(after.id)!.push(link); outgoing.get(before.id)!.push(link);
  }
  const degree = new Map([...incoming].map(([id, values]) => [id, values.length]));
  const pending = rows.filter(row => degree.get(row.id) === 0).map(row => row.id);
  const order: string[] = [];
  for (let index = 0; index < pending.length; index++) {
    const id = pending[index]; order.push(id);
    for (const link of outgoing.get(id) ?? []) {
      const next = degree.get(link.successor_id)! - 1; degree.set(link.successor_id, next);
      if (next === 0) pending.push(link.successor_id);
    }
  }
  if (order.length !== rows.length && !issues.some(issue => issue.code === 'DUPLICATE_ALLOCATION'))
    issues.push({ code: 'CYCLE', message: 'As dependências formam um ciclo. Remova a ligação que retorna a uma etapa anterior.' });
  return { byId, incoming, outgoing, order, issues };
}

function invalidLinkDates(rows: Map<string, GanttModelRow>, links: readonly GanttDependency[], drafts: Readonly<GanttDrafts>): GanttIssue[] {
  const invalid: GanttIssue[] = [];
  const seen = new Set<string>();
  for (const link of links) for (const id of [link.predecessor_id, link.successor_id]) {
    if (seen.has(id)) continue; seen.add(id);
    const row = rows.get(id)!;
    const interval = planningInterval(draftDates(row, drafts[id]));
    if (interval.kind !== 'valid') invalid.push({ code: interval.kind === 'missing' ? 'MISSING_DATES' : 'INVALID_DATES', allocation_id: id,
      message: interval.kind === 'missing' ? 'Uma etapa vinculada está sem início ou prazo. Defina as datas antes de replanejar.' : 'Uma etapa vinculada tem datas inválidas. Corrija-as antes de replanejar.' });
  }
  return invalid;
}

export function dependencyIssues(rows: readonly GanttModelRow[], links: readonly GanttDependency[], drafts: Readonly<GanttDrafts> = {}): GanttIssue[] {
  const graph = dependencyGraph(rows, links);
  if (graph.issues.length) return graph.issues;
  const issues = invalidLinkDates(graph.byId, links, drafts);
  for (const link of links) {
    const before = planningInterval(draftDates(graph.byId.get(link.predecessor_id)!, drafts[link.predecessor_id]));
    const after = planningInterval(draftDates(graph.byId.get(link.successor_id)!, drafts[link.successor_id]));
    if (before.kind !== 'valid' || after.kind !== 'valid') continue;
    const earliest = before.end + 1 + link.lag_days;
    if (earliest > MAX_DAY) issues.push({ code: 'OUT_OF_RANGE', predecessor_id: link.predecessor_id, successor_id: link.successor_id,
      message: 'A dependência ultrapassa as datas permitidas.' });
    else if (after.start < earliest) issues.push({ code: 'FS_VIOLATION', predecessor_id: link.predecessor_id, successor_id: link.successor_id,
      allocation_id: link.successor_id, earliest_start: isoCalendarDay(earliest),
      message: `A etapa sucessora só pode começar em ${isoCalendarDay(earliest)} ou depois.` });
  }
  return issues;
}

export type GanttCascadeResult = { ok: true; drafts: GanttDrafts; changedIds: string[] } | { ok: false; issues: GanttIssue[]; error: string };

/** Explicit forward-only proposal. The caller must still preview and submit to the server. */
export function proposeCascade(rows: readonly GanttModelRow[], links: readonly GanttDependency[], drafts: Readonly<GanttDrafts> = {}): GanttCascadeResult {
  const graph = dependencyGraph(rows, links);
  const reject = (issues: GanttIssue[]): GanttCascadeResult => ({ ok: false, issues, error: issues[0].message });
  if (graph.issues.length) return reject(graph.issues);
  try { changedDateItems(rows, drafts); } catch (error) {
    return reject([{ code: 'INVALID_DRAFT', message: error instanceof Error ? error.message : 'Rascunho inválido.' }]);
  }
  const invalidDates = invalidLinkDates(graph.byId, links, drafts);
  if (invalidDates.length) return reject(invalidDates);
  const next: GanttDrafts = Object.fromEntries(Object.entries(drafts).map(([id, draft]) => [id, { ...draft }]));
  const changedIds: string[] = [];
  for (const id of graph.order) {
    const predecessors = graph.incoming.get(id)!;
    if (!predecessors.length) continue;
    const row = graph.byId.get(id)!;
    const interval = planningInterval(draftDates(row, next[id]));
    if (interval.kind !== 'valid') return reject([{ code: 'INVALID_DATES', allocation_id: id, message: 'Corrija as datas da etapa antes de replanejar.' }]);
    const earliest = Math.max(...predecessors.map(link => {
      const before = planningInterval(draftDates(graph.byId.get(link.predecessor_id)!, next[link.predecessor_id]));
      return before.kind === 'valid' ? before.end + 1 + link.lag_days : Number.POSITIVE_INFINITY;
    }));
    if (interval.start >= earliest) continue;
    if (!editable(row)) return reject([{ code: 'READ_ONLY', allocation_id: id, message: 'A proposta exigiria mover uma etapa disponível somente para consulta. Nenhuma data foi aplicada.' }]);
    const moved = moveDraft(row, next[id] ?? {}, earliest - interval.start);
    if (!moved.ok) return reject([{ code: moved.code, allocation_id: id, message: moved.error }]);
    next[id] = moved.draft; changedIds.push(id);
  }
  return { ok: true, drafts: next, changedIds };
}

/** Calendar-day differences, never a progress percentage or an inferred baseline. */
export function baselineDelta(row: GanttDates, baseline: GanttDates | null | undefined, draft: GanttDateDraft = {}) {
  if (!baseline) return { startDays: null, endDays: null, changed: false };
  const current = draftDates(row, draft);
  const start = planningDay(current.data_inicio), end = planningDay(current.data_limite);
  const originalStart = planningDay(baseline.data_inicio), originalEnd = planningDay(baseline.data_limite);
  return { startDays: start !== null && originalStart !== null ? start - originalStart : null,
    endDays: end !== null && originalEnd !== null ? end - originalEnd : null,
    changed: start !== originalStart || end !== originalEnd };
}
