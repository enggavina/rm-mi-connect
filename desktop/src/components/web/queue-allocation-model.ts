import type { PcpQueueItem } from '@/server/web/pcp-data';
import type { WebRow } from '@/server/web/data';

export function queueAllocationHref(cellId: string, allocationId?: string) {
  const params = new URLSearchParams({ cell: cellId });
  if (allocationId) params.set('allocation', allocationId);
  return `/planejamento/fila?${params.toString()}${allocationId ? '#editar-alocacao' : ''}`;
}

/** A queue row is an allocation, never a project row with similar fields. */
export function queueAllocationMatches(item: PcpQueueItem, allocation: WebRow | undefined) {
  return !!allocation && allocation.id === item.id && allocation.projeto_id === item.projeto_id
    && allocation.celula_id === item.celula_id && allocation.updated_at === item.updated_at
    && allocation.retirada !== true && !['finalizado', 'n_a'].includes(allocation.status ?? '');
}
