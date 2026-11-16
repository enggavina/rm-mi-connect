import { Filter, RotateCcw, X } from 'lucide-react'
import type { WorkshopOrder } from '../domain/types'
import { getActiveStages, isOpenOrder, unknownStageLabel } from '../domain/metrics'
import { useWorkshop } from '../state/store'
import { IconButton } from './ui'
export default function Filters({ orders, onClose }: { orders: WorkshopOrder[]; onClose: () => void }) {
  const { filters, setFilter, resetFilters, soonDays, setSoonDays } = useWorkshop()
  const options = (key: 'stage' | 'client' | 'responsible') => {
    const values = key === 'stage' ? orders.filter(isOpenOrder).flatMap(order => {
      const names = getActiveStages(order)
      return names.length ? names : [unknownStageLabel]
    }) : orders.map(o => o[key]).filter((s): s is string => !!s)
    return [...new Set(values)].sort((a, b) => a.localeCompare(b, 'pt-BR'))
  }
  return <section className="filter-panel" aria-label="Filtros da oficina">
    <div className="section-heading"><h3><Filter size={16} /> Refinar a visão</h3><IconButton label="Fechar filtros" onClick={onClose}><X size={18} /></IconButton></div>
    <div className="filter-fields">
      {(['stage', 'client', 'responsible'] as const).map((key, i) => <label key={key}>{['Etapa em execução', 'Cliente', 'Responsável'][i]}<select value={filters[key]} onChange={e => setFilter(key, e.target.value)}><option value="">Todos</option>{options(key).map(v => <option key={v}>{v}</option>)}</select></label>)}
      <label>Prazo de entrega<select value={filters.period} onChange={e => setFilter('period', e.target.value)}><option value="">Todos os prazos</option><option value="7">Próximos 7 dias</option><option value="30">Próximos 30 dias</option><option value="late">Atrasados</option><option value="unknown">Sem previsão</option></select></label>
      <label>Alerta de proximidade<select value={soonDays} onChange={e => setSoonDays(Number(e.target.value))}>{[0, 1, 3, 5, 7, 14, 30].map(n => <option value={n} key={n}>{n === 0 ? 'No dia do prazo' : `Até ${n} dias antes`}</option>)}</select></label>
    </div>
    <div className="filter-bottom"><label className="check-label"><input type="checkbox" checked={filters.onlyBlocked} onChange={e => setFilter('onlyBlocked', e.target.checked)} /> Somente bloqueios declarados</label><span className="table-note">Somente projetos em andamento na oficina</span><button className="text-button" onClick={resetFilters}><RotateCcw size={14} />Limpar filtros</button></div>
  </section>
}
