export const planningPriorities = ['muito_baixa', 'baixa', 'media', 'alta', 'muito_alta'] as const;
export type PlanningPriority = typeof planningPriorities[number];
export const planningPriorityLabels: Record<PlanningPriority, string> = {
  muito_baixa: 'Muito baixa', baixa: 'Baixa', media: 'Média', alta: 'Alta', muito_alta: 'Muito alta',
};
export function priorityLabel(value: string | null | undefined): string {
  return value ? planningPriorityLabels[value as PlanningPriority] || value.replace(/_/g, ' ') : 'Sem prioridade';
}

/** Moving one item never changes priorities or the order of its neighbours. */
export function moveQueueItem<T extends { id: string }>(items: readonly T[], id: string, target: number): T[] {
  const source = items.findIndex(item => item.id === id);
  const next = [...items];
  if (source < 0 || !Number.isInteger(target) || target < 0 || target >= items.length || source === target) return next;
  const [item] = next.splice(source, 1); next.splice(target, 0, item); return next;
}
export function queueOrderChanged(current: readonly { id: string }[], original: readonly { id: string }[]): boolean {
  return current.length !== original.length || current.some((item, index) => item.id !== original[index].id);
}
export function queuePrioritiesChanged(current: readonly { id: string; prioridade: string | null }[], original: readonly { id: string; prioridade: string | null }[]): boolean {
  const values = new Map(original.map(item => [item.id, item.prioridade]));
  return current.length !== original.length || current.some(item => !values.has(item.id) || values.get(item.id) !== item.prioridade);
}
export interface CellQueueRequest {
  submissionId: string;
  celula_id: string;
  expected_queue_version: string;
  apply_order: boolean;
  items: { id: string; expected_updated_at: string; prioridade: PlanningPriority | null }[];
}
/** A transport retry keeps the whole queue, both version forms and its exact intent. */
export function freezeCellQueueRequest(request: CellQueueRequest): CellQueueRequest {
  return Object.freeze({ ...request, items: Object.freeze(request.items.map(item => Object.freeze({ ...item }))) }) as CellQueueRequest;
}
export function estimatedHours(value: number | null | undefined): string {
  return value == null ? 'Sem estimativa' : `${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 }).format(value)} h`;
}
