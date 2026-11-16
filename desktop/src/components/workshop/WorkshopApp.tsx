'use client';

import { Component, lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { Activity, ArrowDownRight, ArrowRight, Ban, Box, ChevronDown, CircleHelp, Clock3, Database, Factory, Filter, Focus, Layers3, LayoutDashboard, List, MapPin, Maximize2, Minus, PanelRightClose, PanelRightOpen, Pause, Play, Plus, RefreshCw, RotateCw, Search, ShieldAlert, SlidersHorizontal, Truck, UsersRound, Warehouse, X } from 'lucide-react'
import type { BooleanSceneLayer, RoofMode, ViewMode } from './domain/types'
import { deadlineColors, deadlineLabels, statusColors, filterOrders, formatDate, formatTime, getMetrics, getOccupancy, isWorkshopActiveOrder } from './domain/metrics'
import { getStageColor } from './scene/getOrderColor'
import { placeOrders } from './domain/placement'
import { useDataSource } from './data/useDataSource'
import { defaultResources, resolveProductionCells } from './data/layout'
import { useWorkshop } from './state/store'
import { EmptyState, IconButton } from './components/ui'
import Filters from './components/Filters'
import ContextPanel from './components/ContextPanel'
import Management from './components/Management'
import SourcePanel from './components/SourcePanel'
import HelpDialog from './components/HelpDialog'
import CellPanel from './components/CellPanel'
import VirtualBacklog from './components/VirtualBacklog'
import './workshop.css'
const WorkshopScene = lazy(() => import('./scene/WorkshopScene'))
const modes: { id: ViewMode; label: string; icon: typeof Box }[] = [
  { id: 'overview', label: 'Visão geral', icon: Box }, { id: 'stages', label: 'Etapas', icon: Layers3 }, { id: 'deadlines', label: 'Prazos', icon: Clock3 }, { id: 'blocks', label: 'Bloqueios', icon: Ban }, { id: 'capacity', label: 'Capacidade', icon: Warehouse },
]
class SceneBoundary extends Component<{ children: ReactNode; onList: () => void }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() { return { failed: true } }
  render() { return this.state.failed ? <EmptyState title="A cena 3D não pôde ser iniciada">Verifique o suporte WebGL do navegador.<button className="primary-button" onClick={this.props.onList}>Abrir visão gerencial</button></EmptyState> : this.props.children }
}
export default function App() {
  const data = useDataSource()
  const { snapshot, source, loading, error, refresh } = data
  const { mode, setMode, page, setPage, layers, toggleLayer, setRoofMode, soonDays, filters, setFilter, resetFilters, selectedId, selectedResourceId, select, selectResource, cameraCommand, camera } = useWorkshop()
  const { selectedCellId, selectCell, placementMode, setPlacementMode, animationRunning, toggleAnimation, showWorkers, toggleWorkers, showLogistics, toggleLogistics } = useWorkshop()
  const [filtersOpen, setFiltersOpen] = useState(false), [layersOpen, setLayersOpen] = useState(false), [helpOpen, setHelpOpen] = useState(false), [panelOpen, setPanelOpen] = useState(true)
  const [sceneReady, setSceneReady] = useState(false)
  const [scenePage, setScenePage] = useState(0)
  const [reducedMotion, setReducedMotion] = useState(false)
  const previousCells = useRef<ReturnType<typeof resolveProductionCells>>([])
  // Canonical coordinates are geometry only; the directory shows the current EM catalog.
  const cells = useMemo(() => snapshot ? resolveProductionCells(snapshot.cells, previousCells.current).filter(cell => !!cell.sourceId) : [], [snapshot?.cells])
  useEffect(() => { previousCells.current = cells }, [cells])
  const workshopOrders = useMemo(() => snapshot ? snapshot.orders.filter(order => isWorkshopActiveOrder(order, snapshot.referenceAt)) : [], [snapshot])
  const orders = useMemo(() => snapshot ? filterOrders(workshopOrders, filters, snapshot.referenceAt) : [], [snapshot, workshopOrders, filters])
  const metrics = snapshot ? getMetrics(orders, snapshot.referenceAt) : null
  const occupancy = snapshot ? getOccupancy(orders, snapshot.resources, false, snapshot.referenceAt) : null
  const representedIds = useMemo(() => new Set(placeOrders(workshopOrders, snapshot?.resources.length ? snapshot.resources : defaultResources, cells, placementMode, source === 'supabase' && !snapshot?.resources.length).filter(item => !item.unsupported).map(item => item.order.id)), [workshopOrders, snapshot?.resources, cells, placementMode, source])
  const selected = orders.find(o => o.id === selectedId)
  const resource = (snapshot?.resources.length ? snapshot.resources : defaultResources).find(r => r.id === selectedResourceId)
  const activeFilters = [filters.stage, filters.client, filters.responsible, filters.period, filters.onlyBlocked].filter(Boolean).length
  const filtered = !!(activeFilters || filters.query)
  const scenePageCount = Math.max(1, Math.ceil(orders.length / 32))
  const currentScenePage = Math.min(scenePage, scenePageCount - 1)
  const sceneOrders = orders.slice(currentScenePage * 32, (currentScenePage + 1) * 32)
  useEffect(() => { setScenePage(0) }, [filters, source])
  useEffect(() => { if (selectedId) { const index = orders.findIndex(o => o.id === selectedId); if (index >= 0) setScenePage(Math.floor(index / 32)) } }, [selectedId, orders])
  useEffect(() => { if (selectedId && !orders.some(o => o.id === selectedId)) select(null) }, [orders, selectedId, select])
  useEffect(() => { if (selectedId || selectedResourceId || selectedCellId) setPanelOpen(true) }, [selectedId, selectedResourceId, selectedCellId])
  useEffect(() => { const preference = window.matchMedia('(prefers-reduced-motion: reduce)'); const update = () => setReducedMotion(preference.matches); update(); preference.addEventListener('change', update); return () => preference.removeEventListener('change', update) }, [])
  useEffect(() => { const handle = (event: KeyboardEvent) => { if (event.key === '/' && !(event.target instanceof HTMLInputElement) && !(event.target instanceof HTMLSelectElement)) { event.preventDefault(); document.querySelector<HTMLInputElement>('.search-box input')?.focus() } }; document.addEventListener('keydown', handle); return () => document.removeEventListener('keydown', handle) }, [])
  const chooseMode = (next: ViewMode) => { setMode(next); setPage('workshop') }
  return <div className="em-workshop"><div className="app-shell">
    <div className="app-main">
      <header className="app-header"><div className="unit-label"><Warehouse size={17}/><span>Gêmeo digital<small>Oficina de equipamentos</small></span></div><div className="header-spacer"/><label className="search-box"><Search size={17}/><input aria-label="Buscar projeto, equipamento ou cliente" placeholder="Buscar projeto, equipamento…" value={filters.query} onChange={e => setFilter('query', e.target.value)}/><kbd>/</kbd></label><button className={`source-pill ${source}`} onClick={() => setPage('source')}><i/>{'Dados da oficina'}<ChevronDown size={12}/></button><IconButton label="Como navegar" onClick={() => setHelpOpen(true)}><CircleHelp size={20}/></IconButton><IconButton label="Atualizar dados" onClick={() => void refresh()} disabled={loading}><RefreshCw size={17} className={loading ? 'spin' : ''}/></IconButton></header>
      <main>
        {page === 'source' ? <SourcePanel onBack={() => setPage('workshop')} source={source} snapshot={snapshot} loading={loading} error={error} refresh={() => void refresh()}/> : <>
          <div className="page-heading"><div><div className="breadcrumb">PCP<span>/</span>OFICINA DE EQUIPAMENTOS</div><h1>{page === 'management' ? 'Visão gerencial' : 'Sua oficina, célula por célula.'}</h1><p>{'Projetos e células do EM, com a mesma base de dados do aplicativo e do planejamento.'}</p></div><div className="heading-right"><span className="update-text">{loading ? 'Consultando a fonte…' : snapshot ? `${'Referência'} ${formatDate(snapshot.referenceAt, true)}` : 'Sem leitura disponível'}</span><div className="view-switch" aria-label="Tipo de visualização"><button className={page === 'workshop' ? 'selected' : ''} onClick={() => setPage('workshop')}><Box size={15}/>Oficina 3D</button><button className={page === 'management' ? 'selected' : ''} onClick={() => setPage('management')}><List size={16}/>Gerencial</button></div></div></div>
          {error && <div className="error-banner" role="alert"><ShieldAlert size={20}/><div><strong>Dados não atualizados</strong><p>{error}{snapshot && ' Os indicadores foram ocultados até uma leitura válida.'}</p></div><button className="secondary-button" onClick={() => setPage('source')}>Ver integração<ArrowRight size={15}/></button></div>}
          {!error && snapshot && metrics ? <>
            <section className="kpi-strip" aria-label="Indicadores da seleção">
              <Kpi label="Em andamento na oficina" value={metrics.open} icon={Box} detail={filtered ? 'Na seleção atual' : 'Recebidos · serviço ainda em andamento'} tone="neutral" onClick={() => setPage('management')}/>
              <Kpi label="Fora do prazo" value={metrics.late} icon={Clock3} detail="Prazo de entrega ultrapassado" tone="red" onClick={() => { setFilter('period', 'late'); chooseMode('deadlines') }}/>
              <Kpi label="Bloqueios declarados" value={metrics.blocked} icon={Ban} detail={metrics.unknownBlocks ? `${metrics.unknownBlocks} sem informação de bloqueio` : 'Com impedimento registrado'} tone="amber" onClick={() => { setFilter('onlyBlocked', true); chooseMode('blocks') }}/>
              <Kpi label="Entregas nos próximos 7 dias" value={metrics.upcoming} icon={ArrowDownRight} detail="Previsões a partir de hoje" tone="teal" onClick={() => { setFilter('period', '7'); chooseMode('deadlines') }}/>
            </section>
            <section className="workspace" aria-label="Oficina e acompanhamento">
              <div className="workspace-toolbar"><div className="mode-tabs" role="group" aria-label="Camada de informação">{modes.map(({ id, label, icon: Icon }) => <button className={mode === id && page === 'workshop' ? 'active' : ''} onClick={() => chooseMode(id)} key={id}><Icon size={15}/><span>{label}</span></button>)}</div><div className="toolbar-actions"><button className={`tool-button ${filtersOpen || activeFilters ? 'active' : ''}`} onClick={() => setFiltersOpen(!filtersOpen)}><SlidersHorizontal size={15}/>Filtros{activeFilters > 0 && <b>{activeFilters}</b>}</button><span className="toolbar-divider"/><IconButton label={panelOpen ? 'Ocultar painel' : 'Mostrar painel'} onClick={() => setPanelOpen(!panelOpen)}>{panelOpen ? <PanelRightClose size={18}/> : <PanelRightOpen size={18}/>}</IconButton></div></div>
              {filtersOpen && <Filters orders={workshopOrders} onClose={() => setFiltersOpen(false)}/>}
              {filtered && <div className="filter-summary"><Filter size={13}/><span>{orders.length} de {workshopOrders.length} projetos em andamento · filtros aplicados{filters.query ? ` · “${filters.query}”` : ''}</span><button onClick={resetFilters}>Limpar<X size={12}/></button></div>}
              {page === 'workshop' && <div className="pcp-controlbar">
                <div className="placement-switch" role="group" aria-label="Posicionamento dos equipamentos"><button className={placementMode === 'process' ? 'active' : ''} onClick={() => setPlacementMode('process')}><Layers3 size={14}/>Mapa PCP</button><button className={placementMode === 'physical' ? 'active' : ''} onClick={() => setPlacementMode('physical')}><MapPin size={14}/>Localização</button></div>
                <button className={`area-label-toggle ${layers.areaLabels ? 'active' : ''}`} aria-pressed={layers.areaLabels} onClick={() => toggleLayer('areaLabels')} title="Quando desligadas, as legendas aparecem ao passar o mouse ou selecionar uma área."><Layers3 size={14}/>Legendas das áreas</button>
                <label className="roof-control">Cobertura<select aria-label="Cobertura da oficina" value={layers.roofMode ?? (layers.roof ? 'translucent' : 'hidden')} onChange={event => setRoofMode(event.target.value as RoofMode)}><option value="hidden">Oculta</option><option value="translucent">Translúcida</option><option value="closed">Fechada</option></select></label>
                <span className="pcp-view-note">{placementMode === 'process' ? `${cells.length} células · posições por atividade` : 'Somente vínculos físicos registrados'}</span>
                <div className="life-controls"><button aria-pressed={showWorkers} className={showWorkers ? 'active' : ''} title="Mostrar ou ocultar personagens ilustrativos" onClick={toggleWorkers}><UsersRound size={14}/><span>Pessoas</span></button><button aria-pressed={showLogistics} className={showLogistics ? 'active' : ''} title="Mostrar ou ocultar logística ilustrativa" onClick={toggleLogistics}><Truck size={15}/><span>Logística</span></button><button className="animation-toggle" onClick={toggleAnimation} disabled={reducedMotion || (!showWorkers && !showLogistics && !layers.cranes)} title={reducedMotion ? 'Movimento reduzido ativado no sistema' : animationRunning ? 'Pausar animação ilustrativa' : 'Retomar animação ilustrativa'}>{animationRunning && !reducedMotion ? <Pause size={13}/> : <Play size={13}/>}<span>{reducedMotion ? 'Movimento reduzido' : animationRunning ? 'Pausar' : 'Retomar'}</span></button></div>
              </div>}
              <div className={`workspace-body ${panelOpen ? '' : 'panel-hidden'}`}>
                {page === 'workshop' ? <div className="scene-column"><div className="scene-container">
                  <div className="scene-topline"><div><span className="scene-overline">MI ELECTRIC · PLANEJAMENTO E CONTROLE</span><h2>{placementMode === 'process' ? 'Mapa das células' : 'Localização dos equipamentos'}<span>{cells.length}</span></h2></div><div className="scene-count"><i/>{orders.length} em andamento na oficina</div></div>
                  <div className="canvas-wrap" aria-label="Cena tridimensional interativa da oficina"><SceneBoundary onList={() => setPage('management')}><Suspense fallback={<div className="scene-loading"><Factory size={30}/><span>Preparando a oficina…</span></div>}><WorkshopScene onUnavailable={() => setPage('management')} orders={sceneOrders} allOrders={orders} layoutOrders={workshopOrders} resolvedCells={cells} catalog={snapshot.cells} placementMode={placementMode} resources={snapshot.resources.length ? snapshot.resources : defaultResources} illustrativeOnly={source === 'supabase' && !snapshot.resources.length} selectedId={selectedId} selectedResourceId={selectedResourceId} selectedCellId={selectedCellId} onSelect={select} onSelectResource={selectResource} onSelectCell={selectCell} mode={mode} layers={layers} referenceAt={snapshot.referenceAt} soonDays={soonDays} cameraCommand={cameraCommand} animationRunning={animationRunning && !reducedMotion} showWorkers={showWorkers} showLogistics={showLogistics} onReady={() => setSceneReady(true)}/></Suspense></SceneBoundary></div>
                  {scenePageCount > 1 && <div className="scene-pagination"><button disabled={currentScenePage === 0} onClick={() => { setScenePage(currentScenePage - 1); select(null) }}>Anterior</button><span>{currentScenePage * 32 + 1}–{Math.min((currentScenePage + 1) * 32, orders.length)} de {orders.length} projetos</span><button disabled={currentScenePage + 1 >= scenePageCount} onClick={() => { setScenePage(currentScenePage + 1); select(null) }}>Próximos</button></div>}
                  {!orders.length && <div className="scene-empty"><h3>Nenhum projeto encontrado</h3><p>O ambiente permanece visível para orientação.</p><button className="secondary-button" onClick={resetFilters}>Limpar filtros</button></div>}
                  <div className="scene-side-controls"><div className="layer-control"><IconButton label="Camadas do ambiente" className={layersOpen ? 'active' : ''} onClick={() => setLayersOpen(!layersOpen)}><Layers3 size={19}/></IconButton>{layersOpen && <div className="layers-popover"><h3>Elementos da oficina</h3>{([['architecture', 'Arquitetura'], ['cranes', 'Ponte rolante'], ['labels', 'Identificadores dos equipamentos'], ['areaLabels', 'Legendas das áreas'], ['sectors', 'Destaque das células']] as [BooleanSceneLayer, string][]).map(([key, label]) => <label key={key}><input type="checkbox" checked={layers[key]} onChange={() => toggleLayer(key)}/><span>{label}</span></label>)}<p>As células permanecem visíveis, mesmo vazias.</p></div>}</div><span className="controls-gap"/><IconButton label="Aproximar" onClick={() => camera('zoom-in')}><Plus size={19}/></IconButton><IconButton label="Afastar" onClick={() => camera('zoom-out')}><Minus size={19}/></IconButton><IconButton label="Girar a vista" onClick={() => camera('rotate')}><RotateCw size={17}/></IconButton><IconButton label="Centralizar seleção" onClick={() => camera('focus')} disabled={!(selectedId && representedIds.has(selectedId)) && !selectedResourceId && !selectedCellId}><Focus size={18}/></IconButton><IconButton label="Enquadrar a oficina" onClick={() => camera('reset')}><Maximize2 size={17}/></IconButton></div>
                  <div className="scene-bottomline"><span className="scene-caption"><span className="estimate-dot"/>{placementMode === 'process' ? 'Mapa de processo · não é posição física' : 'Planta conceitual · localização só quando registrada'}</span><span className="scene-compass" title="Perspectiva isométrica; orientação geográfica não confirmada">ISO<span>↗</span></span></div>
                </div><div className="scene-legend"><div>{mode === 'blocks' ? <><Legend color={statusColors.danger} label="Bloqueio declarado"/><Legend color={statusColors.success} label="Sem bloqueio declarado"/><Legend color={statusColors.muted} label="Não informado"/></> : mode === 'capacity' ? <><Legend color={statusColors.success} label="Recurso com vínculo"/><Legend color={statusColors.muted} label="Sem vínculo"/><span className="legend-note">{'Ocupação física não disponível'}</span></> : mode === 'stages' ? <span className="legend-note">Cores por etapa · consulte a distribuição abaixo</span> : (['on-time', 'soon', 'late', 'unknown'] as const).map(key => <Legend key={key} color={deadlineColors[key]} label={deadlineLabels[key]}/>)}</div><button className="scene-help" onClick={() => setHelpOpen(true)}><CircleHelp size={14}/>Navegação</button></div>
                <VirtualBacklog orders={orders} layoutOrders={workshopOrders} resolvedCells={cells} catalog={snapshot.cells} resources={snapshot.resources.length ? snapshot.resources : defaultResources} placementMode={placementMode} illustrativeOnly={source === 'supabase' && !snapshot.resources.length} selectedId={selectedId} onSelect={select}/>
                <div className="stages-strip"><div className="stages-label" title="Projetos únicos por etapa; um projeto pode participar de várias etapas."><Activity size={15}/><strong>Em execução</strong><small>Etapas podem coexistir</small></div><div className="stage-items">{metrics.stages.map(stage => <button key={stage.name} title={`${stage.name}: ${stage.count} projetos. Um projeto pode participar de várias etapas.`} onClick={() => { setFilter('stage', stage.name); setMode('stages') }}><span className="stage-mini-bar" style={{ backgroundColor: getStageColor(stage.name) }}/><span>{stage.name}</span><b>{stage.count.toString().padStart(2, '0')}</b></button>)}</div></div>
                <div className="simulation-note"><Truck size={13}/><span><strong>Animação ilustrativa.</strong> Pessoas, ensaios, ponte e logística são ilustrativos; os projetos e as etapas vêm da fonte selecionada.</span></div>
                </div> : <Management snapshot={snapshot} orders={orders}/>}
                {panelOpen && (page === 'workshop' && !selected && !resource ? <CellPanel cells={cells} orders={orders}/> : <ContextPanel snapshot={snapshot} orders={orders} selected={selected} resource={resource} canFocusSelected={!!selectedId && representedIds.has(selectedId)}/>)}
              </div>
            </section>
            {source === 'supabase' && snapshot.warnings.length > 0 && <details className="data-warnings data-warnings-footer"><summary>Critérios e qualidade desta leitura · {snapshot.warnings.length} observações</summary><ul>{snapshot.warnings.map(warning => <li key={warning}>{warning}</li>)}</ul></details>}
          </> : !error && <div className="data-placeholder"><Database size={32}/><h2>{loading ? 'Buscando dados da oficina…' : 'Nenhuma leitura disponível'}</h2><p>{loading ? 'A primeira consulta percorre as páginas de projetos e atividades. Isso pode levar alguns instantes.' : 'Atualize a consulta para carregar os dados autorizados do EM.'}</p><button className="secondary-button" onClick={() => setPage('source')}>Ver fonte de dados</button></div>}
          <footer className="app-footer"><span><span className={`footer-status ${source}`}/>{'DADOS DA OFICINA · SOMENTE LEITURA'}</span><span>{page === 'workshop' && sceneReady ? 'Vista isométrica · ' : ''}{snapshot ? `Leitura às ${formatTime(snapshot.fetchedAt)} · ` : ''}EM<span className="footer-version">Gêmeo digital</span></span></footer>
        </>}
      </main>
    </div>{helpOpen && <HelpDialog onClose={() => setHelpOpen(false)}/>}
  </div></div>
}
function Kpi({ label, value, icon: Icon, detail, tone, onClick }: { label: string; value: number; icon: typeof Box; detail: string; tone: string; onClick: () => void }) {
  return <button className={`kpi ${tone}`} onClick={onClick}><div className="kpi-label"><span>{label}</span><Icon size={17} strokeWidth={1.7}/></div><div className="kpi-value"><strong>{value.toString().padStart(2, '0')}</strong><span className="kpi-action"><ArrowRight size={19}/></span></div><small>{detail}</small></button>
}
function Legend({ color, label }: { color: string; label: string }) { return <span className="legend-item"><i style={{ background: color }}/>{label}</span> }
