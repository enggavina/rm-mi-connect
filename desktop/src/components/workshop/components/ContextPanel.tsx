import { ArrowDownRight, ArrowUpRight, Ban, ChevronRight, Clock3, Crosshair, ExternalLink, Info, MapPin, Package, ShieldAlert, UserRound, X } from 'lucide-react'
import type { WorkshopOrder, WorkshopResource, WorkshopSnapshot } from '../domain/types'
import { daysBetween, formatDate, getDeadlineStatus, isOpenOrder, getActiveStages } from '../domain/metrics'
import { useWorkshop } from '../state/store'
import { EmptyState, IconButton, StatusBadge } from './ui'

function Facts({ items }: { items: [string, string][] }) { return <dl className="facts">{items.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl> }
export default function ContextPanel({ snapshot, orders, selected, resource, canFocusSelected = true }: { canFocusSelected?: boolean; snapshot: WorkshopSnapshot; orders: WorkshopOrder[]; selected?: WorkshopOrder; resource?: WorkshopResource }) {
  const { select, soonDays, camera, setPage } = useWorkshop()
  const at = snapshot.referenceAt
  if (selected) {
    const location = snapshot.resources.find(r => r.id === selected.locationId)
    const days = daysBetween(selected.enteredAt, selected.completedAt ?? at)
    return <aside className="context-panel detail-panel" aria-label="Detalhes do equipamento">
      <div className="context-heading"><span className="eyebrow">EQUIPAMENTO SELECIONADO</span><IconButton label="Fechar detalhes" onClick={() => select(null)}><X size={17} /></IconButton></div>
      <div className="detail-title"><span className="equipment-symbol"><Package size={25} strokeWidth={1.4} /></span><div><h2>{selected.code}</h2><p>{selected.equipment}</p></div></div>
      <div className="badge-row"><StatusBadge order={selected} at={at} soonDays={soonDays} />{selected.blockDeclared && <span className="status-badge blocked"><Ban size={11} /> Bloqueado</span>}</div>

      <div className="detail-section"><h3>Operação</h3><Facts items={[
        ['Cliente', selected.client ?? 'Não informado'], ['Etapa em execução', getActiveStages(selected).join(' · ') || 'Não identificada'], ['Status na origem', selected.status ?? 'Não informado'], ['Responsável', selected.responsible ?? 'Não informado'], ['Prioridade', selected.priority ?? 'Não informada'],
      ]} /></div>
      {selected.blockDeclared === true && <div className="block-notice"><ShieldAlert size={18} /><div><strong>Bloqueio declarado</strong><p>{selected.blockReason ?? 'Motivo não informado na origem.'}</p></div></div>}
      {selected.blockDeclared === null && <p className="inline-note"><Info size={14} /> Situação de bloqueio não informada.</p>}
      <div className="detail-section"><h3>Prazos e permanência</h3><Facts items={[
        ['Entrada', formatDate(selected.enteredAt)], ['Prazo de entrega', formatDate(selected.dueAt)], ['Origem do prazo', selected.dueSource === 'contractual' ? 'Data contratual' : selected.dueSource === 'renegotiated' ? 'Data renegociada' : 'Não disponível'], ...(selected.completedAt ? [['Entrega registrada', formatDate(selected.completedAt)] as [string, string]] : []), ['Permanência', days === null || days < 0 ? 'Indisponível' : `${days} dias corridos`],
      ]} /></div>
      <div className="location-box"><MapPin size={17} /><div><strong>{location?.name ?? 'Localização não registrada'}</strong><span>{selected.locationVerified && location && !location.illustrative ? 'Localização registrada na origem' : location ? 'Posição ilustrativa · não medida' : 'A fonte não informa uma posição física'}</span></div></div>
      <div className="detail-section"><h3>Características disponíveis</h3><Facts items={[
        ['Tipo do equipamento', selected.equipmentType ?? 'Não informado'], ['Representação 3D', selected.modelVerified ? 'Estilizada conforme o tipo cadastrado' : 'Ilustrativa · tipo não confirmado'],
        ['Potência', selected.powerKw === null ? selected.powerRaw ? `${selected.powerRaw} (texto da origem)` : 'Não informada' : `${selected.powerKw.toLocaleString('pt-BR')} kW`], ['Rotação', selected.rpm === null ? selected.rpmRaw ? `${selected.rpmRaw} (texto da origem)` : 'Não informada' : `${selected.rpm.toLocaleString('pt-BR')} rpm`], ['Nº de série', selected.serial ?? 'Não informado'],
      ]} /></div>
      {selected.activities && selected.activities.length > 0 && <div className="detail-section"><h3>Células do projeto <span>{selected.activities.length}</span></h3><div className="activity-list">{selected.activities.map(a => <div key={a.id}><i className={a.blocked ? 'activity-dot blocked' : 'activity-dot'} /><div><strong>{a.name ?? 'Cadastro da célula indisponível'}</strong><span>{a.status ?? 'Status não informado'} · {a.blocked === true ? 'Marcada como bloqueada na origem' : a.blocked === null ? 'Bloqueio não informado' : 'Sem bloqueio declarado'}</span>{a.blockReason && <p>{a.blockReason}</p>}</div></div>)}</div></div>}
      <div className="detail-section"><h3>Histórico </h3>{selected.history.length ? <div className="timeline">{selected.history.map((event, i) => <div key={i}><i /><span>{event.label}<small>{formatDate(event.at)}</small></span></div>)}</div> : <p className="muted small">Histórico cronológico não disponível no contrato atual.</p>}</div>
      <div className="detail-actions"><button disabled={!canFocusSelected} title={canFocusSelected ? 'Enquadrar este equipamento' : 'Projeto disponível na fila virtual; sem modelo posicionado'} className="primary-button" onClick={() => { setPage('workshop'); camera('focus') }}><Crosshair size={16} /> {canFocusSelected ? 'Localizar na cena' : 'Na fila virtual'}</button>{selected.sourceUrl ? <a className="secondary-button" href={selected.sourceUrl} target="_blank" rel="noopener noreferrer">Abrir projeto no sistema<ExternalLink size={14} /></a> : <span className="muted small">Link da origem não disponível.</span>}</div>
    </aside>
  }
  if (resource) {
    const assigned = orders.filter(o => o.locationId === resource.id && isOpenOrder(o))
    return <aside className="context-panel"><div className="context-heading"><span className="eyebrow">RECURSO SELECIONADO</span><IconButton label="Fechar recurso" onClick={() => select(null)}><X size={17} /></IconButton></div><h2>{resource.name}</h2><p className="muted">{resource.sector}</p><div className="location-box"><MapPin size={18}/><div><strong>{resource.illustrative ? 'Recurso ilustrativo' : 'Recurso cadastrado'}</strong><span>{resource.illustrative ? 'Dimensões e posição precisam de validação.' : 'Ocupação baseada nos vínculos registrados.'}</span></div></div><Facts items={[
      ['Capacidade real cadastrada', resource.illustrative || resource.capacity === null ? 'Não informada' : `${resource.capacity} equipamento(s)`], ['Vínculos nesta leitura', String(assigned.length)], ['Utilização medida', 'Indisponível'],
    ]}/><div className="detail-section"><h3>Equipamentos vinculados</h3>{assigned.length ? assigned.map(o => <button key={o.id} className="order-link" onClick={() => select(o.id)}><span><strong>{o.code}</strong><small>{o.equipment}</small></span><ChevronRight size={16}/></button>) : <p className="muted small">Nenhum vínculo registrado. Ausência de vínculo não comprova disponibilidade física.</p>}</div></aside>
  }
  const active = orders.filter(isOpenOrder)
  const alerts = active.filter(o => o.blockDeclared || getDeadlineStatus(o, at, soonDays) === 'late').sort((a, b) => Number(b.blockDeclared) - Number(a.blockDeclared))
  const deliveries = active.filter(o => { const d = daysBetween(at, o.dueAt); return d !== null && d >= 0 && d <= 7 }).sort((a, b) => Date.parse(a.dueAt!) - Date.parse(b.dueAt!)).slice(0, 3)
  return <aside className="context-panel" aria-label="Resumo operacional">
    <div className="context-heading"><h2>Pulso da oficina</h2><span className="live-dot" /></div><p className="context-subtitle">O que merece sua atenção agora.</p>
    <div className="attention-heading"><span><ShieldAlert size={15} /> Pontos de atenção</span><b>{alerts.length.toString().padStart(2, '0')}</b></div>
    <div className="alert-list">{alerts.length ? alerts.slice(0, 4).map(order => <button className={`alert-card ${order.blockDeclared ? 'has-block' : ''}`} key={order.id} onClick={() => select(order.id)}><div><span className="alert-dot"/><strong>{order.code}</strong><ArrowUpRight size={15} /></div><p>{order.blockDeclared ? order.blockReason ?? 'Bloqueio sem motivo informado' : `${Math.abs(daysBetween(at, order.dueAt) ?? 0)} dias após o prazo de entrega`}</p><small>{order.stage ?? 'Etapa não informada'}<span>{order.blockDeclared ? 'Bloqueado' : 'Atrasado'}</span></small></button>) : <div className="quiet-note">Nenhum atraso ou bloqueio declarado nesta visão.</div>}</div>
    <div className="panel-divider" />
    <div className="section-heading"><h3><Clock3 size={15} /> Próximas entregas</h3><span className="tiny-pill">7 dias</span></div>
    <div className="delivery-list">{deliveries.length ? deliveries.map(order => <button key={order.id} onClick={() => select(order.id)}><span className="delivery-date"><b>{calendarDayNumber(order.dueAt)}</b><small>{new Intl.DateTimeFormat('pt-BR', { month: 'short', timeZone: 'America/Sao_Paulo' }).format(new Date(order.dueAt!)).replace('.', '')}</small></span><span><strong>{order.code}</strong><small>{order.client ?? 'Cliente não informado'}</small></span><ChevronRight size={15} /></button>) : <p className="muted small">Sem entregas previstas nesta janela.</p>}</div>
    <div className="insight-note"><ArrowDownRight size={18} /><div><strong>Explore a operação</strong><p>Selecione um equipamento na oficina para consultar prazos, atividades e responsáveis.</p></div></div>
    {!orders.length && <EmptyState title="Nenhum resultado">Ajuste os filtros para visualizar os projetos.</EmptyState>}
    <div className="panel-footnote"><UserRound size={13} />Visão gerencial · somente leitura</div>
  </aside>
}
function calendarDayNumber(value: string | null) { return value ? new Intl.DateTimeFormat('pt-BR', { day: '2-digit', timeZone: 'America/Sao_Paulo' }).format(new Date(value)) : '—' }
