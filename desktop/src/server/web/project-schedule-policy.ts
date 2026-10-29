import { uuid } from './policy';
import type { WebRow } from './data';
import type { StageApprovalListItem } from './stage-approval-data';

export type ScheduleParams = Record<string, string | string[] | undefined>;
export type ScheduleTab = 'fotos' | 'formularios' | 'etapas';
export function scheduleView(params: ScheduleParams, canReadProjects: boolean): 'project' | 'gantt' {
  if (!canReadProjects || params.view === 'gantt') return 'gantt';
  if (params.view !== 'project' && !params.project && ['start', 'cell', 'status'].some(key => typeof params[key] === 'string')) return 'gantt';
  return 'project';
}
export function scheduleId(value: unknown): string | undefined {
  return uuid.safeParse(value).success ? (value as string).toLowerCase() : undefined;
}
export function scheduleTab(value: unknown, allowed: readonly ScheduleTab[]): ScheduleTab | undefined {
  return allowed.includes(value as ScheduleTab) ? value as ScheduleTab : allowed[0];
}
export function scheduleHref(project?: string, allocation?: string, tab?: ScheduleTab, page?: number) {
  const query = new URLSearchParams({ view: 'project' });
  const projectId = scheduleId(project), allocationId = scheduleId(allocation);
  if (projectId) {
    query.set('project', projectId);
    if (allocationId) {
      query.set('allocation', allocationId);
      if (tab) query.set('tab', tab);
      if (page && page > 1) query.set('page', String(page));
    }
  }
  return `/cronograma?${query}`;
}
export function orderedProjectAllocations<T extends WebRow>(rows: readonly T[], projectId: string): T[] {
  const order = (row: T) => typeof row.indice === 'number' && Number.isFinite(row.indice) ? row.indice : Number.POSITIVE_INFINITY;
  return rows.filter(row => row.projeto_id === projectId).slice().sort((a, b) => order(a) - order(b) || a.id.localeCompare(b.id));
}
export function selectedAllocation(rows: readonly WebRow[], projectId: string, allocationId: unknown): WebRow | undefined {
  const id = scheduleId(allocationId);
  return id ? rows.find(row => row.id === id && row.projeto_id === projectId) : undefined;
}
export function allocationRecords(records: readonly WebRow[], allocation: WebRow): WebRow[] {
  return records.filter(row => row.projeto_id === allocation.projeto_id && row.celula_id === allocation.celula_id);
}
export function allocationStage(item: StageApprovalListItem, allocation: WebRow): boolean {
  return item.stage.projeto_id === allocation.projeto_id && item.stage.celula_origem_id === allocation.celula_id
    && (item.stage.celula_projeto_id === allocation.id || item.stage.celula_projeto_id === null);
}
