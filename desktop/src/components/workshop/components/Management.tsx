import { ArrowUpRight, Ban, MapPin } from 'lucide-react'
import type { WorkshopOrder, WorkshopSnapshot } from '../domain/types'
import { formatDate, getMetrics, getOccupancy, getActiveStages } from '../domain/metrics'
import { useWorkshop } from '../state/store'
import { EmptyState, StatusBadge } from './ui'
export default function Management({ snapshot, orders }: { snapshot: WorkshopSnapshot; orders: WorkshopOrder[] }) {
  const { select, soonDays, selectedId } = useWorkshop()
  const metrics = getMetrics(orders, snapshot.referenceAt)
  const occupancy = getOccupancy(orders, snapshot.resources, false, snapshot.referenceAt)
  return <div className="management-view">
    <div className="management-intro"><div><span className="eyebrow">DA OFICINA PARA A DECISÃO</span><h2>Operação em detalhe</h2><p>Os mesmos projetos da cena, organizados para acompanhamento.</p></div><span className="tiny-pill">{orders.length} registros filtrados</span></div>
    <div className="management-stats"><div><span>Em andamento na oficina</span><b>{metrics.open.toString().padStart(2, '0')}</b><small>Recebidos e com status PCP operacional</small></div><div><span>Sem prazo informado</span><b>{metrics.noDeadline.toString().padStart(2, '0')}</b><small>Projetos ativos sem prazo calculável</small></div><div><span>{'Ocupação registrada'}</span><b>{occupancy.total ? `${occupancy.occupied}/${occupancy.total}` : '—'}</b><small>{occupancy.total ? 'Recursos com vínculo / cadastrados' : 'Localização física indisponível'}</small></div></div>
    <div className="table-container">
      <table>
        <thead><tr><th>Projeto / equipamento</th><th>Cliente</th><th>Etapas em execução</th><th>Prazo</th><th>Situação</th><th><span className="sr-only">Detalhes</span></th></tr></thead>
        <tbody>{orders.map(order => <tr key={order.id} className={selectedId === order.id ? 'selected-row' : ''}>
          <td><button className="table-project" onClick={() => select(order.id)}>{order.code}<small>{order.equipment}</small></button></td>
          <td>{order.client ?? 'Não informado'}</td>
          <td><span className="table-stage">{getActiveStages(order).join(' · ') || 'Sem etapa ativa identificada'}</span>{!order.locationId && <small className="table-location"><MapPin size={10} /> Local não cadastrado</small>}</td>
          <td>{formatDate(order.dueAt)}</td>
          <td><StatusBadge order={order} at={snapshot.referenceAt} soonDays={soonDays} />{order.blockDeclared && <span className="table-block"><Ban size={11} /> Bloqueio declarado</span>}</td>
          <td><button className="icon-button" aria-label={`Detalhes de ${order.code}`} onClick={() => select(order.id)}><ArrowUpRight size={17} /></button></td>
        </tr>)}</tbody>
      </table>
      {!orders.length && <EmptyState title="Nenhum projeto nesta seleção">Limpe ou altere os filtros para continuar.</EmptyState>}
    </div>
    <p className="table-note">Prazos calculados por dia civil em São Paulo. Cores de prazo são derivadas e não substituem o status registrado no sistema de gestão.</p>
  </div>
}
