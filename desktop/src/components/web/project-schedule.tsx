import type { ReactNode } from 'react';
import type { WebRow } from '@/server/web/data';
import { scheduleHref, type ScheduleTab } from '@/server/web/project-schedule-policy';
import { Empty, Status, date } from './ui';
import { Icon } from './icons';
import s from './project-schedule.module.css';

/** The route-order editor can be composed here without changing queue position. */
export function ProjectAllocationList({ projectId, allocations, cells, selectedId, tab, orderControl }: {
  projectId: string; allocations: WebRow[]; cells: WebRow[]; selectedId?: string; tab?: ScheduleTab; orderControl?: ReactNode;
}) {
  const names = new Map(cells.map(cell => [cell.id, cell.nome]));
  return <section className="panel"><div className="panel-header"><div><h2>Células do projeto <span className="inline-count">{allocations.length}</span></h2><p>Ordem de execução do roteiro</p></div>{orderControl}</div>
    {allocations.length ? <nav className={s.allocations} aria-label="Selecionar célula do projeto">{allocations.map((allocation, index) => <a
      key={allocation.id} href={scheduleHref(projectId, allocation.id, tab)} className={s.allocation}
      aria-current={selectedId === allocation.id ? 'page' : undefined}>
      <span className={s.sequence}>{index + 1}</span><div className={s.allocationCopy}><strong>{names.get(allocation.celula_id) || 'Célula não disponível'}</strong>
        <span>{date(allocation.data_inicio)} — {date(allocation.data_limite)}</span>
        <span>{allocation.visibilidade ? 'Disponível no mobile' : 'Oculta no mobile'}{allocation.bloqueada === 'sim' ? ' · Execução bloqueada' : ''}</span>
        <Status value={allocation.status} /></div><Icon name="chevron" size={16} />
    </a>)}</nav> : <Empty title="Nenhuma célula alocada" detail="O roteiro deste projeto ainda não foi planejado." icon="board" />}
  </section>;
}
