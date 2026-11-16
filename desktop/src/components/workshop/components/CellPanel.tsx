import { ArrowLeft, ArrowUpRight, Ban, Crosshair, Factory, Layers3, Search } from 'lucide-react'
import { useMemo, useState } from 'react'
import type { PcpCell } from '../data/layout'
import { getCellMapCode, getCellSummaries } from '../data/layout'
import type { WorkshopOrder } from '../domain/types'
import { getCellWorkload } from '../domain/cells'
import { useWorkshop } from '../state/store'
import { IconButton } from './ui'

export default function CellPanel({ cells, orders }: { cells: PcpCell[]; orders: WorkshopOrder[] }) {
  const { selectedCellId, selectCell, select, camera, setPage } = useWorkshop()
  const [query, setQuery] = useState('')
  const selectedCell = cells.find(cell => cell.id === selectedCellId)
  const summaries = useMemo(() => getCellSummaries(orders, cells), [orders, cells])
  if (selectedCell) {
    const workload = getCellWorkload(selectedCell, orders)
    return <aside className="context-panel cell-panel" aria-label={`Célula ${selectedCell.name}`}>
      <div className="context-heading"><IconButton label="Todas as células" onClick={() => selectCell(null)}><ArrowLeft size={17}/></IconButton><span className="eyebrow">{selectedCell.group}</span><span className="cell-code">{selectedCell.id}</span></div>
      <div className="cell-detail-heading"><span style={{ background: selectedCell.color }}/><h2>{selectedCell.name}</h2></div>
      <p className="cell-subtitle">Célula do catálogo PCP · posição conceitual</p>
      <div className="cell-metrics"><div><b>{workload.running}</b><span>em execução</span></div><div><b>{workload.waiting}</b><span>outras pendências</span></div><div><b>{workload.blocked}</b><span>com bloqueio</span></div></div>
      <p className="cell-count-note">Projetos distintos nesta seleção. Execução e bloqueio podem coexistir; as contagens não devem ser somadas.</p>
      <button className="primary-button cell-focus" onClick={() => { setPage('workshop'); camera('focus') }}><Crosshair size={15}/> Aproximar esta célula</button>
      <div className="detail-section"><h3>Projetos associados <span>{workload.entries.length}</span></h3>
        {workload.entries.length ? <div className="cell-orders">{workload.entries.map(({ order, activities, running, blocked }) => <button key={order.id} onClick={() => select(order.id)}><div><strong>{order.code}</strong><ArrowUpRight size={14}/></div><span>{order.equipment}</span><small>{activities.length ? [...new Set(activities.map(a => a.status ?? 'Não informado'))].join(' · ') : running ? 'Em execução' : 'Pendente'}{blocked && <b><Ban size={11}/> Bloqueado</b>}</small></button>)}</div> : <div className="empty-cell-notice"><Factory size={25}/><strong>Sem projetos nesta seleção</strong><p>A célula continua presente no planejamento. Isso não comprova disponibilidade física ou capacidade.</p></div>}
      </div>
      <div className="cell-origin-note">{selectedCell.sourceId ? 'Cadastro confirmado pela API do rmmi.' : 'Nome baseado no catálogo auditado do rmmi.'} O posicionamento na cena e os personagens são ilustrativos.</div>
    </aside>
  }
  const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
  const visibleCells = cells.filter(cell => normalize(`${cell.name} ${cell.group}`).includes(normalize(query)))
  const groups = [...new Set(visibleCells.map(cell => cell.group))]
  return <aside className="context-panel cell-panel" aria-label="Células de PCP">
    <div className="context-heading"><h2><Layers3 size={17}/> Células de PCP</h2><span className="cell-total">{cells.length}</span></div>
    <p className="context-subtitle">Cada célula permanece visível, inclusive vazia.</p>
    <label className="cell-search"><Search size={14}/><input aria-label="Buscar célula PCP" placeholder="Encontrar uma célula…" value={query} onChange={event => setQuery(event.target.value)}/></label>
    <div className="cell-directory-heading"><span>CÉLULA</span><span>EM EXECUÇÃO</span></div>
    {groups.map(group => <section className="cell-group" key={group}><h3>{group}</h3>{visibleCells.filter(cell => cell.group === group).map(cell => {
      const count = summaries.find(summary => summary.cellId === cell.id)?.count ?? 0
      return <button className={`cell-row ${count ? 'occupied' : 'empty'}`} key={cell.id} onClick={() => selectCell(cell.id)}><i style={{ background: cell.color }}/><small className="cell-floor-id" aria-hidden="true">{getCellMapCode(cell.id)}</small><span>{cell.name}</span><b>{count}</b></button>
    })}</section>)}
    {!visibleCells.length && <p className="cell-count-note">Nenhuma célula com esse nome.</p>}
    <div className="cell-origin-note">Contagens sobre todos os projetos filtrados, independentemente da página 3D. Um projeto pode executar atividades em mais de uma célula.</div>
  </aside>
}
