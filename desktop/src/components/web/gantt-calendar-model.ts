import { calendarDay, isoCalendarDay, planningDay } from '@/server/web/gantt';
import {
  changeDateDraft, changedDateItems, draftDates, planningInterval,
  type GanttDateDraft, type GanttDrafts, type GanttDraftResult, type GanttModelRow,
  type GanttDependency, type GanttIssue, type GanttCascadeResult,
} from './gantt-planner-model';

export type GanttWorkCalendar = {
  weekdays: number[];
  exceptions: { date: string; working: boolean; label: string }[];
};
export type GanttMilestone = { id: string; label: string; date: string };
export const EVERY_DAY_CALENDAR: GanttWorkCalendar = { weekdays: [1, 2, 3, 4, 5, 6, 7], exceptions: [] };
const MIN_DAY = calendarDay('0001-01-01')!;
const MAX_DAY = calendarDay('9999-12-31')!;
const EDIT_MIN_DAY = calendarDay('1900-01-01')!;
const EDIT_MAX_DAY = calendarDay('2200-12-31')!;
type CompiledCalendar = { weekdays: Set<number>; exceptions: Map<number, boolean> };
const weekday = (day: number) => ((day + 3) % 7 + 7) % 7 + 1;
function parsedDay(value: string | number): number | null {
  return typeof value === 'number' ? Number.isSafeInteger(value) && value >= MIN_DAY && value <= MAX_DAY ? value : null : planningDay(value);
}
function compile(calendar: GanttWorkCalendar): CompiledCalendar | null {
  if (!calendar || !Array.isArray(calendar.weekdays) || !calendar.weekdays.length || calendar.weekdays.length > 7
    || calendar.weekdays.some(value => !Number.isInteger(value) || value < 1 || value > 7)
    || new Set(calendar.weekdays).size !== calendar.weekdays.length || !Array.isArray(calendar.exceptions) || calendar.exceptions.length > 366) return null;
  const exceptions = new Map<number, boolean>();
  for (const exception of calendar.exceptions) {
    if (!exception || typeof exception !== 'object') return null;
    const day = calendarDay(exception.date);
    if (day === null || typeof exception.working !== 'boolean' || exceptions.has(day)) return null;
    exceptions.set(day, exception.working);
  }
  return { weekdays: new Set(calendar.weekdays), exceptions };
}
const works = (calendar: CompiledCalendar, day: number) => calendar.exceptions.get(day) ?? calendar.weekdays.has(weekday(day));
function count(calendar: CompiledCalendar, start: number, end: number): number {
  if (end < start) return 0;
  const length = end - start + 1, weeks = Math.floor(length / 7);
  let total = weeks * calendar.weekdays.size;
  for (let offset = weeks * 7; offset < length; offset++) if (calendar.weekdays.has(weekday(start + offset))) total++;
  for (const [day, working] of calendar.exceptions) if (day >= start && day <= end) total += Number(working) - Number(calendar.weekdays.has(weekday(day)));
  return total;
}
function add(calendar: CompiledCalendar, start: number, delta: number): number | null {
  if (!Number.isSafeInteger(delta)) return null;
  if (!delta) return start;
  if (delta > 0) {
    if (count(calendar, start + 1, MAX_DAY) < delta) return null;
    let low = start + 1, high = MAX_DAY;
    while (low < high) { const middle = Math.floor((low + high) / 2); if (count(calendar, start + 1, middle) >= delta) high = middle; else low = middle + 1; }
    return low;
  }
  if (count(calendar, MIN_DAY, start - 1) < -delta) return null;
  let low = MIN_DAY, high = start - 1;
  while (low < high) { const middle = Math.ceil((low + high) / 2); if (count(calendar, middle, start - 1) >= -delta) low = middle; else high = middle - 1; }
  return low;
}
function next(calendar: CompiledCalendar, start: number, direction: 1 | -1 = 1, inclusive = true): number | null {
  return inclusive && works(calendar, start) ? start : add(calendar, start, direction);
}

/** Dates denote São Paulo civil days. No clock arithmetic is used for working days. */
export function isWorkingDay(calendar: GanttWorkCalendar, value: string | number): boolean {
  const compiled = compile(calendar), day = parsedDay(value);
  return compiled !== null && day !== null && works(compiled, day);
}
export function countWorkingDays(calendar: GanttWorkCalendar, from: string | number, to: string | number): number | null {
  const compiled = compile(calendar), start = parsedDay(from), end = parsedDay(to);
  return compiled && start !== null && end !== null && end >= start ? count(compiled, start, end) : null;
}
/** Excludes the starting day. Delta zero preserves it, including nonworking days. */
export function addWorkingDays(calendar: GanttWorkCalendar, value: string | number, delta: number): number | null {
  const compiled = compile(calendar), start = parsedDay(value);
  return compiled && start !== null ? add(compiled, start, delta) : null;
}
export function nextWorkingDay(calendar: GanttWorkCalendar, value: string | number, direction: 1 | -1 = 1, inclusive = true): number | null {
  const compiled = compile(calendar), start = parsedDay(value);
  return compiled && start !== null && (direction === 1 || direction === -1) ? next(compiled, start, direction, inclusive) : null;
}
/** Difference in working-day indices, useful for floats, never hours or effort. */
export function workingDayDistance(calendar: GanttWorkCalendar, from: string | number, to: string | number): number | null {
  const compiled = compile(calendar), start = parsedDay(from), end = parsedDay(to);
  if (!compiled || start === null || end === null) return null;
  return end >= start ? count(compiled, start + 1, end) : -count(compiled, end + 1, start);
}

const failure = (code: string, error: string): GanttDraftResult => ({ ok: false, code, error });
const editable = (row: GanttModelRow) => row.can_edit && !['finalizado', 'n_a'].includes(row.status ?? '');
const inEditRange = (day: number | null): day is number => day !== null && day >= EDIT_MIN_DAY && day <= EDIT_MAX_DAY;
export function moveCalendarDraft(row: GanttModelRow, draft: GanttDateDraft, delta: number, calendar: GanttWorkCalendar): GanttDraftResult {
  if (!editable(row)) return failure('READ_ONLY', 'Esta etapa está disponível somente para consulta.');
  const compiled = compile(calendar);
  if (!compiled) return failure('INVALID_CALENDAR', 'O calendário de trabalho é inválido.');
  if (!Number.isSafeInteger(delta)) return failure('INVALID_VALUE', 'O deslocamento deve ser um número inteiro de dias.');
  const interval = planningInterval(draftDates(row, draft));
  if (interval.kind !== 'valid') return failure(interval.kind === 'missing' ? 'MISSING_DATES' : 'INVALID_DATES', 'Informe um intervalo válido antes de mover a etapa.');
  const duration = count(compiled, interval.start, interval.end);
  if (!duration) return failure('NO_WORKING_DURATION', 'O intervalo não possui dias úteis. Revise o início e o prazo.');
  if (!delta) return { ok: true, draft: { ...draft } };
  const shifted = interval.start + delta;
  if (!inEditRange(shifted)) return failure('OUT_OF_RANGE', 'Informe datas entre 1900 e 2200.');
  const start = next(compiled, shifted, delta < 0 ? -1 : 1), end = start === null ? null : add(compiled, start, duration - 1);
  if (!inEditRange(start) || !inEditRange(end)) return failure('OUT_OF_RANGE', 'O deslocamento ultrapassa as datas permitidas.');
  const result = changeDateDraft(row, draft, 'data_inicio', isoCalendarDay(start));
  return result.ok ? changeDateDraft(row, result.draft, 'data_limite', isoCalendarDay(end)) : result;
}
export function resizeCalendarDraft(row: GanttModelRow, draft: GanttDateDraft, edge: 'start' | 'end', delta: number, calendar: GanttWorkCalendar): GanttDraftResult {
  if (!editable(row)) return failure('READ_ONLY', 'Esta etapa está disponível somente para consulta.');
  const compiled = compile(calendar);
  if (!compiled) return failure('INVALID_CALENDAR', 'O calendário de trabalho é inválido.');
  if (!Number.isSafeInteger(delta) || !['start', 'end'].includes(edge)) return failure('INVALID_VALUE', 'Redimensionamento inválido.');
  const interval = planningInterval(draftDates(row, draft));
  if (interval.kind !== 'valid') return failure(interval.kind === 'missing' ? 'MISSING_DATES' : 'INVALID_DATES', 'Informe um intervalo válido antes de redimensionar a etapa.');
  if (!delta) return { ok: true, draft: { ...draft } };
  const shifted = (edge === 'start' ? interval.start : interval.end) + delta;
  if (!inEditRange(shifted)) return failure('OUT_OF_RANGE', 'Informe datas entre 1900 e 2200.');
  const aligned = next(compiled, shifted, delta < 0 ? -1 : 1);
  if (!inEditRange(aligned)) return failure('OUT_OF_RANGE', 'O redimensionamento ultrapassa as datas permitidas.');
  // Never move the opposite endpoint to hide an inversion.
  const candidate = edge === 'start' ? Math.min(interval.end, aligned) : Math.max(interval.start, aligned);
  if (!works(compiled, candidate)) return failure('NON_WORKING_BOUNDARY', 'O outro extremo do intervalo não é útil. Corrija as datas nos campos da etapa.');
  return changeDateDraft(row, draft, edge === 'start' ? 'data_inicio' : 'data_limite', isoCalendarDay(candidate));
}

function graph(rows: readonly GanttModelRow[], links: readonly GanttDependency[]) {
  const byId = new Map(rows.map(row => [row.id, row]));
  const incoming = new Map(rows.map(row => [row.id, [] as GanttDependency[]]));
  const outgoing = new Map(rows.map(row => [row.id, [] as GanttDependency[]]));
  const issues: GanttIssue[] = [], pairs = new Set<string>();
  if (byId.size !== rows.length) issues.push({ code: 'DUPLICATE_ALLOCATION', message: 'O cronograma contém etapas repetidas.' });
  for (const link of links) {
    const predecessor = byId.get(link.predecessor_id), successor = byId.get(link.successor_id), pair = JSON.stringify([link.predecessor_id, link.successor_id]);
    const context = { predecessor_id: link.predecessor_id, successor_id: link.successor_id };
    if (pairs.has(pair)) { issues.push({ ...context, code: 'DUPLICATE_LINK', message: 'A dependência foi informada mais de uma vez.' }); continue; }
    pairs.add(pair);
    if (!predecessor || !successor) { issues.push({ ...context, code: 'MISSING_ENDPOINT', message: 'Uma etapa vinculada não está no conjunto consultado.' }); continue; }
    if (predecessor.id === successor.id) { issues.push({ ...context, code: 'SELF_LINK', message: 'Uma etapa não pode depender dela mesma.' }); continue; }
    if (predecessor.projeto_id !== successor.projeto_id || link.projeto_id !== undefined && link.projeto_id !== predecessor.projeto_id) { issues.push({ ...context, code: 'CROSS_PROJECT', message: 'As etapas vinculadas devem pertencer ao mesmo projeto.' }); continue; }
    if (!Number.isInteger(link.lag_days) || link.lag_days < 0 || link.lag_days > 3650) { issues.push({ ...context, code: 'INVALID_LAG', message: 'A espera deve ser um inteiro entre 0 e 3.650 dias.' }); continue; }
    incoming.get(successor.id)!.push(link); outgoing.get(predecessor.id)!.push(link);
  }
  const degree = new Map([...incoming].map(([id, edges]) => [id, edges.length]));
  const order = rows.filter(row => degree.get(row.id) === 0).map(row => row.id);
  for (let index = 0; index < order.length; index++) for (const edge of outgoing.get(order[index]) ?? []) {
    const value = degree.get(edge.successor_id)! - 1; degree.set(edge.successor_id, value); if (!value) order.push(edge.successor_id);
  }
  if (order.length !== rows.length && !issues.some(issue => issue.code === 'DUPLICATE_ALLOCATION')) issues.push({ code: 'CYCLE', message: 'As dependências formam um ciclo. Revise os vínculos.' });
  return { byId, incoming, outgoing, order, issues };
}

/** Separate from dependency constraints: existing nonworking boundaries can be shown as warnings. */
export function calendarDateIssues(rows: readonly GanttModelRow[], drafts: Readonly<GanttDrafts>, calendar: GanttWorkCalendar): GanttIssue[] {
  const compiled = compile(calendar);
  if (!compiled) return [{ code: 'INVALID_CALENDAR', message: 'O calendário de trabalho é inválido.' }];
  const issues: GanttIssue[] = [];
  for (const row of rows) {
    const dates = draftDates(row, drafts[row.id]);
    for (const [field, name] of [['data_inicio', 'início'], ['data_limite', 'prazo']] as const) {
      const day = planningDay(dates[field]);
      if (day !== null && !works(compiled, day)) issues.push({ code: field === 'data_inicio' ? 'NON_WORKING_START' : 'NON_WORKING_END', allocation_id: row.id,
        message: `O ${name} da etapa está em dia não útil (${isoCalendarDay(day)}). As datas não foram alteradas automaticamente.` });
    }
  }
  return issues;
}
export function calendarDependencyIssues(rows: readonly GanttModelRow[], links: readonly GanttDependency[], drafts: Readonly<GanttDrafts>, calendar: GanttWorkCalendar): GanttIssue[] {
  const compiled = compile(calendar);
  if (!compiled) return [{ code: 'INVALID_CALENDAR', message: 'O calendário de trabalho é inválido.' }];
  const plan = graph(rows, links);
  if (plan.issues.length) return plan.issues;
  const issues: GanttIssue[] = [], seen = new Set<string>();
  for (const edge of links) {
    for (const id of [edge.predecessor_id, edge.successor_id]) if (!seen.has(id)) {
      seen.add(id); const interval = planningInterval(draftDates(plan.byId.get(id)!, drafts[id]));
      if (interval.kind !== 'valid') issues.push({ code: interval.kind === 'missing' ? 'MISSING_DATES' : 'INVALID_DATES', allocation_id: id,
        message: interval.kind === 'missing' ? 'Uma etapa vinculada está sem início ou prazo.' : 'Uma etapa vinculada tem um intervalo inválido.' });
    }
    const predecessor = planningInterval(draftDates(plan.byId.get(edge.predecessor_id)!, drafts[edge.predecessor_id]));
    const successor = planningInterval(draftDates(plan.byId.get(edge.successor_id)!, drafts[edge.successor_id]));
    if (predecessor.kind !== 'valid' || successor.kind !== 'valid') continue;
    const earliest = add(compiled, predecessor.end, edge.lag_days + 1);
    if (earliest === null) issues.push({ code: 'OUT_OF_RANGE', predecessor_id: edge.predecessor_id, successor_id: edge.successor_id, message: 'A dependência ultrapassa as datas permitidas.' });
    else if (successor.start < earliest) issues.push({ code: 'FS_VIOLATION', predecessor_id: edge.predecessor_id, successor_id: edge.successor_id,
      allocation_id: edge.successor_id, earliest_start: isoCalendarDay(earliest), message: `A etapa sucessora só pode começar em ${isoCalendarDay(earliest)} ou depois, considerando os dias úteis.` });
  }
  return issues;
}

/** Explicit forward-only proposal; no operational status or immutable date is changed. */
export function proposeCalendarCascade(rows: readonly GanttModelRow[], links: readonly GanttDependency[], drafts: Readonly<GanttDrafts>, calendar: GanttWorkCalendar): GanttCascadeResult {
  const compiled = compile(calendar), plan = graph(rows, links);
  const reject = (issues: GanttIssue[]): GanttCascadeResult => ({ ok: false, issues, error: issues[0].message });
  if (!compiled) return reject([{ code: 'INVALID_CALENDAR', message: 'O calendário de trabalho é inválido.' }]);
  if (plan.issues.length) return reject(plan.issues);
  try { changedDateItems(rows, drafts); } catch (error) { return reject([{ code: 'INVALID_DRAFT', message: error instanceof Error ? error.message : 'Rascunho inválido.' }]); }
  const issues = calendarDependencyIssues(rows, links, drafts, calendar).filter(issue => issue.code !== 'FS_VIOLATION');
  if (issues.length) return reject(issues);
  const result: GanttDrafts = Object.fromEntries(Object.entries(drafts).map(([id, value]) => [id, { ...value }]));
  const changedIds: string[] = [];
  for (const id of plan.order) {
    const predecessors = plan.incoming.get(id)!;
    if (!predecessors.length) continue;
    const row = plan.byId.get(id)!, interval = planningInterval(draftDates(row, result[id]));
    if (interval.kind !== 'valid') return reject([{ code: 'INVALID_DATES', allocation_id: id, message: 'Defina um intervalo válido antes de reprogramar.' }]);
    const minimums = predecessors.map(edge => {
      const before = planningInterval(draftDates(plan.byId.get(edge.predecessor_id)!, result[edge.predecessor_id]));
      return before.kind === 'valid' ? add(compiled, before.end, edge.lag_days + 1) : null;
    });
    if (minimums.some(value => value === null)) return reject([{ code: 'OUT_OF_RANGE', allocation_id: id, message: 'A reprogramação ultrapassa as datas permitidas.' }]);
    const earliest = Math.max(...minimums as number[]);
    if (interval.start >= earliest) continue;
    if (!editable(row)) return reject([{ code: 'READ_ONLY', allocation_id: id, message: 'A proposta exigiria mover uma etapa disponível somente para consulta. Nenhuma data foi aplicada.' }]);
    const duration = count(compiled, interval.start, interval.end);
    if (!duration) return reject([{ code: 'NO_WORKING_DURATION', allocation_id: id, message: 'Uma etapa vinculada não possui duração em dias úteis.' }]);
    const end = add(compiled, earliest, duration - 1);
    if (!inEditRange(earliest) || !inEditRange(end)) return reject([{ code: 'OUT_OF_RANGE', allocation_id: id, message: 'A reprogramação ultrapassa as datas permitidas.' }]);
    const first = changeDateDraft(row, result[id] ?? {}, 'data_inicio', isoCalendarDay(earliest));
    const second = first.ok ? changeDateDraft(row, first.draft, 'data_limite', isoCalendarDay(end)) : first;
    if (!second.ok) return reject([{ code: second.code, allocation_id: id, message: second.error }]);
    result[id] = second.draft; changedIds.push(id);
  }
  return { ok: true, drafts: result, changedIds };
}

export type CriticalPathNode = {
  id: string; durationDays: number;
  earliestStart: string; earliestFinish: string; latestStart: string; latestFinish: string;
  totalFloatDays: number; scheduledSlackDays: number; schedulingDeviationDays: number;
  critical: boolean; negativeFloat: boolean; networkFloatDays: number; networkCritical: boolean;
};
export type CriticalPathResult = {
  complete: boolean; issues: GanttIssue[]; warnings: string[]; nodes: CriticalPathNode[];
  projectStart: string | null; networkFinish: string | null; targetFinish: string | null;
  finishVarianceDays: number | null; criticalIds: string[]; negativeFloatIds: string[];
  networkCriticalIds: string[]; excludedIds: string[];
};
export type CriticalPathOptions = { startDate?: string | null; targetDate?: string | null };

/** CPM describes the planned dependency network, never resource availability or
 * actual remaining production. Current scheduled starts do not become hidden
 * constraints: their difference from early/late dates is returned separately. */
export function analyzeCriticalPath(rows: readonly GanttModelRow[], links: readonly GanttDependency[], drafts: Readonly<GanttDrafts>, calendar: GanttWorkCalendar, options: CriticalPathOptions = {}): CriticalPathResult {
  const excludedIds = rows.filter(row => row.status === 'n_a').map(row => row.id), excluded = new Set(excludedIds);
  const warnings: string[] = [];
  if (excludedIds.length) warnings.push(`${excludedIds.length} etapa(s) não aplicável(is) foram excluídas da análise.`);
  if (rows.some(row => row.status === 'finalizado')) warnings.push('Etapas finalizadas entram somente pela sua duração planejada; a análise não é uma previsão da execução restante.');
  const fail = (issues: GanttIssue[]): CriticalPathResult => ({ complete: false, issues, warnings, nodes: [], projectStart: null,
    networkFinish: null, targetFinish: null, finishVarianceDays: null, criticalIds: [], negativeFloatIds: [], networkCriticalIds: [], excludedIds });
  const compiled = compile(calendar);
  if (!compiled) return fail([{ code: 'INVALID_CALENDAR', message: 'O calendário de trabalho é inválido.' }]);
  if (rows.length > 2000 || links.length > 4000) return fail([{ code: 'INCOMPLETE_SCOPE', message: 'O conjunto excede o limite da análise completa.' }]);
  if (new Set(rows.map(row => row.projeto_id)).size > 1) return fail([{ code: 'CROSS_PROJECT', message: 'O caminho crítico exige o roteiro completo de um único projeto.' }]);
  if (links.some(link => excluded.has(link.predecessor_id) || excluded.has(link.successor_id))) return fail([{ code: 'NOT_APPLICABLE_LINK',
    message: 'Há dependências ligadas a uma etapa não aplicável. Revise os vínculos; não foram criadas ligações de substituição.' }]);
  const activeRows = rows.filter(row => !excluded.has(row.id));
  if (!activeRows.length) return fail([{ code: 'EMPTY_NETWORK', message: 'Não há etapas aplicáveis para analisar.' }]);
  const plan = graph(activeRows, links);
  if (plan.issues.length) return fail(plan.issues);
  const intervals = new Map<string, { start: number; end: number; duration: number }>(), issues: GanttIssue[] = [];
  for (const row of activeRows) {
    const interval = planningInterval(draftDates(row, drafts[row.id]));
    if (interval.kind !== 'valid') { issues.push({ code: interval.kind === 'missing' ? 'MISSING_DATES' : 'INVALID_DATES', allocation_id: row.id,
      message: 'Toda etapa aplicável precisa de início e prazo válidos para calcular a rede completa.' }); continue; }
    const duration = count(compiled, interval.start, interval.end);
    if (!works(compiled, interval.start) || !works(compiled, interval.end) || duration < 1) {
      issues.push({ code: 'NON_WORKING_BOUNDARY', allocation_id: row.id, message: 'Há início ou prazo em dia não útil. Revise o intervalo antes de analisar o caminho crítico.' }); continue;
    }
    intervals.set(row.id, { start: interval.start, end: interval.end, duration });
  }
  if (issues.length) return fail(issues);
  const requestedStart = options.startDate ? planningDay(options.startDate) : null;
  if (options.startDate && requestedStart === null) return fail([{ code: 'INVALID_ANCHOR', message: 'A data de início da análise é inválida.' }]);
  const initial = requestedStart ?? Math.min(...[...intervals.values()].map(interval => interval.start));
  const anchor = next(compiled, initial);
  if (anchor === null) return fail([{ code: 'OUT_OF_RANGE', message: 'O início da análise ultrapassa o calendário permitido.' }]);
  if (anchor !== initial) warnings.push(`O início teórico foi ajustado para o próximo dia útil (${isoCalendarDay(anchor)}), sem alterar o projeto.`);
  const early = new Map<string, { start: number; end: number }>();
  for (const id of plan.order) {
    let start = anchor;
    for (const edge of plan.incoming.get(id)!) {
      const minimum = add(compiled, early.get(edge.predecessor_id)!.end, edge.lag_days + 1);
      if (minimum === null) return fail([{ code: 'OUT_OF_RANGE', allocation_id: id, message: 'A rede ultrapassa as datas permitidas.' }]);
      start = Math.max(start, minimum);
    }
    const end = add(compiled, start, intervals.get(id)!.duration - 1);
    if (end === null) return fail([{ code: 'OUT_OF_RANGE', allocation_id: id, message: 'A duração da rede ultrapassa as datas permitidas.' }]);
    early.set(id, { start, end });
  }
  const networkFinish = Math.max(...[...early.values()].map(interval => interval.end));
  const requestedTarget = options.targetDate ? planningDay(options.targetDate) : networkFinish;
  if (requestedTarget === null) return fail([{ code: 'INVALID_TARGET', message: 'A data-alvo da análise é inválida.' }]);
  const target = next(compiled, requestedTarget, -1);
  if (target === null) return fail([{ code: 'OUT_OF_RANGE', message: 'A data-alvo ultrapassa as datas permitidas.' }]);
  if (target !== requestedTarget) warnings.push(`Para respeitar o alvo, o término teórico foi limitado ao dia útil anterior (${isoCalendarDay(target)}), sem alterar a data contratual.`);
  function backwards(finish: number) {
    const late = new Map<string, { start: number; end: number }>();
    for (const id of [...plan.order].reverse()) {
      let end = finish;
      for (const edge of plan.outgoing.get(id)!) {
        const latest = add(compiled!, late.get(edge.successor_id)!.start, -(edge.lag_days + 1));
        if (latest === null) return null;
        end = Math.min(end, latest);
      }
      const start = add(compiled!, end, -(intervals.get(id)!.duration - 1));
      if (start === null) return null;
      late.set(id, { start, end });
    }
    return late;
  }
  const late = backwards(target), naturalLate = target === networkFinish ? late : backwards(networkFinish);
  if (!late || !naturalLate) return fail([{ code: 'OUT_OF_RANGE', message: 'O cálculo das datas-limite ultrapassa o calendário permitido.' }]);
  const distance = (from: number, to: number) => to >= from ? count(compiled, from + 1, to) : -count(compiled, to + 1, from);
  const nodes: CriticalPathNode[] = plan.order.map(id => {
    const first = early.get(id)!, last = late.get(id)!, scheduled = intervals.get(id)!, networkLast = naturalLate.get(id)!;
    const totalFloatDays = distance(first.start, last.start), networkFloatDays = distance(first.start, networkLast.start);
    return { id, durationDays: scheduled.duration, earliestStart: isoCalendarDay(first.start), earliestFinish: isoCalendarDay(first.end),
      latestStart: isoCalendarDay(last.start), latestFinish: isoCalendarDay(last.end), totalFloatDays,
      scheduledSlackDays: distance(scheduled.start, last.start), schedulingDeviationDays: distance(first.start, scheduled.start),
      critical: totalFloatDays === 0, negativeFloat: totalFloatDays < 0, networkFloatDays, networkCritical: networkFloatDays === 0 };
  });
  if (!links.length && nodes.length > 1) warnings.push('Nenhuma dependência foi registrada: a análise considera as etapas independentes, sem presumir a ordem do roteiro.');
  return { complete: true, issues: [], warnings, nodes, projectStart: isoCalendarDay(anchor), networkFinish: isoCalendarDay(networkFinish),
    targetFinish: isoCalendarDay(target), finishVarianceDays: distance(networkFinish, target), criticalIds: nodes.filter(node => node.critical).map(node => node.id),
    negativeFloatIds: nodes.filter(node => node.negativeFloat).map(node => node.id), networkCriticalIds: nodes.filter(node => node.networkCritical).map(node => node.id), excludedIds };
}
