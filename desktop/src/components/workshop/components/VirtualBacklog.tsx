import { useEffect, useMemo, useRef, useState } from 'react'
import { Layers3, ListFilter, ChevronLeft, ChevronRight } from 'lucide-react'
import type { SceneProps } from '../domain/types'
import { resolveProductionCells } from '../data/layout'
import { placeOrders } from '../domain/placement'

type Props = Pick<SceneProps, 'orders' | 'layoutOrders' | 'catalog' | 'resolvedCells' | 'resources' | 'placementMode' | 'illustrativeOnly' | 'selectedId' | 'onSelect'>

/** A virtual list is deliberately outside the 3D site and its camera bounds. */
export default function VirtualBacklog(props: Props) {
  const details = useRef<HTMLDetailsElement>(null)
  const [page, setPage] = useState(0)
  const entries = useMemo(() => {
    const ids = new Set(props.orders.map(order => order.id))
    const placements = placeOrders(props.layoutOrders ?? props.orders, props.resources, props.resolvedCells ?? resolveProductionCells(props.catalog), props.placementMode ?? 'process', props.illustrativeOnly)
    const byOrder = new Map<string, { order: SceneProps['orders'][number]; reason: string }>()
    for (const placement of placements) {
      if (!placement.unsupported || !ids.has(placement.order.id)) continue
      const reason = placement.unrepresentedReason === 'display-overflow' ? 'Excedente da visualização · vínculo preservado' : props.placementMode === 'physical' ? 'Sem localização registrada' : 'Sem célula em execução identificada'
      byOrder.set(placement.order.id, { order: placement.order, reason })
    }
    return [...byOrder.values()]
  }, [props.orders, props.layoutOrders, props.resources, props.catalog, props.resolvedCells, props.placementMode, props.illustrativeOnly])
  const pages = Math.max(1, Math.ceil(entries.length / 12)), current = Math.min(page, pages - 1)
  useEffect(() => {
    const index = entries.findIndex(entry => entry.order.id === props.selectedId)
    if (index >= 0) { if (details.current) details.current.open = true; setPage(Math.floor(index / 12)) }
  }, [props.selectedId, entries])
  if (!entries.length) return null
  return <details className="virtual-backlog" ref={details}>
    <summary><ListFilter size={16}/><strong>Fila virtual</strong><span>{entries.length} projetos</span><small>Sem modelo ou com exibição parcial</small></summary>
    <div className="virtual-backlog-body">
      <p>Projetos sem vínculo identificável ficam nesta lista. Quando a célula já contém todos os modelos que cabem na visualização, os demais continuam no seu total. Um projeto pode aparecer em outra célula da maquete e ter participações nesta fila. Isso não indica capacidade física.</p>
      <div className="backlog-grid">{entries.slice(current * 12, (current + 1) * 12).map(({ order, reason }) => <button key={order.id} className={props.selectedId === order.id ? 'selected' : ''} aria-pressed={props.selectedId === order.id} onClick={() => props.onSelect(order.id)}><Layers3 size={15}/><span><strong>{order.code}</strong><span>{order.equipment}</span><small>{reason}</small></span></button>)}</div>
      {pages > 1 && <div className="backlog-pagination"><button aria-label="Página anterior da fila virtual" disabled={!current} onClick={() => setPage(current - 1)}><ChevronLeft size={16}/></button><span>{current * 12 + 1}–{Math.min((current + 1) * 12, entries.length)} de {entries.length}</span><button aria-label="Próxima página da fila virtual" disabled={current + 1 === pages} onClick={() => setPage(current + 1)}><ChevronRight size={16}/></button></div>}
    </div>
  </details>
}
