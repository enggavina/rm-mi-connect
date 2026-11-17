'use client';

import { useEffect, useId, useMemo, useRef, useState, type CSSProperties, type PointerEvent } from 'react';
import type { GanttSnapshot, GanttItem, GanttLink } from '@/server/web/gantt-data';
import type { SaveGanttPlanInput } from '@/server/web/gantt-policy';
import { saveGanttPlan } from '@/server/web/gantt-actions';
import { formatGanttDay, isoCalendarDay, planningDay } from '@/server/web/gantt';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { display, date } from './ui';
import { Icon } from './icons';
import { GANTT_EDIT_MIN_DATE, GANTT_EDIT_MAX_DATE, baselineDelta, changeDateDraft, changedDateItems, dateInput, draftDates, draftTimingIssue,
  plannerBar, plannerWindow, planningInterval, type GanttDateDraft, type GanttDraftResult, type GanttDrafts, type PlannerDays } from './gantt-planner-model';
import { EVERY_DAY_CALENDAR as DEFAULT_GANTT_CALENDAR, analyzeCriticalPath, calendarDateIssues, calendarDependencyIssues, countWorkingDays, isWorkingDay, moveCalendarDraft, proposeCalendarCascade, resizeCalendarDraft } from './gantt-calendar-model';
import { GanttSettingsPanel, type GanttSettingsState } from './gantt-settings-panel';
import { GanttCriticalPath, GanttStageAnalysis } from './gantt-critical-path';
import s from './gantt-planner.module.css';

export type GanttScope = 'general' | 'project' | 'cell';
type Props = { snapshot: GanttSnapshot; scope: GanttScope; canManage: boolean; canProjects: boolean; destination: string; initialStart?: string; initialDays?: string; initialAllocation?: string };
const linkSignature = (links: readonly GanttLink[]) => links.map(link => `${link.projeto_id}:${link.predecessor_id}:${link.successor_id}:${link.lag_days}`).sort().join('|');
const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const rowLabel = (row: GanttItem) => `${row.numero_projeto ? `OS ${row.numero_projeto}` : 'Projeto sem OS'} · ${row.celula_nome || 'Célula'}`;
const dayLabel = (value: string | null | undefined) => { const parsed = planningDay(value); return parsed === null ? 'Não informado' : formatGanttDay(parsed); };

export function GanttPlanner({ snapshot, scope, canManage, canProjects, destination, initialStart, initialDays, initialAllocation }: Props) {
  // The server's instant avoids hydration differences at midnight in São Paulo.
  const [period, setPeriod] = useState(() => plannerWindow(initialStart, initialDays, new Date(snapshot.as_of)));
  const [drafts, setDrafts] = useState<GanttDrafts>({});
  const [links, setLinks] = useState(snapshot.links);
  const [selectedId, setSelectedId] = useState(initialAllocation && snapshot.items.some(item => item.id === initialAllocation) ? initialAllocation : '');
  const [search, setSearch] = useState(''), [groupBy, setGroupBy] = useState<'project' | 'cell'>(scope === 'cell' ? 'cell' : 'project');
  const [mode, setMode] = useState<'all' | 'period' | 'unscheduled'>('period');
  const [status, setStatus] = useState(''), [reason, setReason] = useState(''), [notice, setNotice] = useState('');
  const [showBaseline, setShowBaseline] = useState(true), [showLinks, setShowLinks] = useState(scope === 'project');
  const [baselineLabel, setBaselineLabel] = useState(''), [predecessor, setPredecessor] = useState(''), [lag, setLag] = useState('0');
  const [saved, setSaved] = useState(false);
  const [settingsState, setSettingsState] = useState<GanttSettingsState | null>(null);
  const [useTarget, setUseTarget] = useState(false);
  const leaving = useRef(false), detail = useRef<HTMLElement>(null);
  const drag = useRef<{ id: string; x: number; edge: 'move' | 'start' | 'end'; initial: GanttDateDraft; lastDelta: number; target: HTMLElement; pointer: number } | null>(null);
  const arrowId = `gantt-arrow-${useId().replace(/:/g, '')}`;
  const save = useEngineeringSave<SaveGanttPlanInput>(async input => {
    const result = await saveGanttPlan(input);
    if (result.ok) { leaving.current = true; setSaved(true); }
    return result;
  }, destination);
  const locked = save.locked || saved || !!(settingsState?.dirty || settingsState?.locked);
  const editable = canManage && snapshot.complete && !locked
    && !(scope === 'project' && snapshot.projects.find(row => row.id === snapshot.filters.project_id)?.closed);
  const items = useMemo(() => changedDateItems(snapshot.items, drafts), [snapshot.items, drafts]);
  const linksDirty = linkSignature(links) !== linkSignature(snapshot.links);
  const dirty = items.length > 0 || linksDirty;
  const rows = useMemo(() => snapshot.items.map(row => ({ ...row, ...draftDates(row, drafts[row.id]) })), [snapshot.items, drafts]);
  const selected = snapshot.items.find(row => row.id === selectedId);
  const selectedDates = selected ? draftDates(selected, drafts[selected.id]) : null;
  const selectedBaseline = snapshot.baseline?.items.find(item => item.allocation_id === selectedId);
  const project = scope === 'project' ? snapshot.projects.find(item => item.id === snapshot.filters.project_id) : undefined;
  const settingsByProject = useMemo(() => new Map((snapshot.settings ?? []).map(setting => [setting.projeto_id, setting])), [snapshot.settings]);
  const projectSettings = project ? settingsByProject.get(project.id) ?? null : null;
  const calendarFor = (row: GanttItem) => settingsByProject.get(row.projeto_id)?.calendar ?? DEFAULT_GANTT_CALENDAR;
  const projectCalendar = projectSettings?.calendar ?? DEFAULT_GANTT_CALENDAR;
  const targetDate = project?.renegotiated_date || project?.contract_date;
  const analysis = useMemo(() => project ? analyzeCriticalPath(snapshot.items, links, drafts, projectCalendar,
    { startDate: project.planned_start, targetDate: useTarget ? targetDate : null }) : null,
  [project, snapshot.items, links, drafts, projectCalendar, useTarget, targetDate]);
  const criticalIds = new Set(analysis?.networkCriticalIds ?? []);
  const selectedAnalysis = analysis?.nodes.find(node => node.id === selectedId);
  const markers = project ? [
    { id: 'planned-start', label: 'Início do projeto', date: project.planned_start, custom: false },
    { id: 'planned-end', label: 'Entrega prevista', date: project.planned_end, custom: false },
    { id: 'contract', label: 'Data contratual', date: project.contract_date, custom: false },
    { id: 'renegotiated', label: 'Data renegociada', date: project.renegotiated_date, custom: false },
    ...(projectSettings?.milestones ?? []).map(item => ({ ...item, custom: true })),
  ].flatMap(marker => { const day = planningDay(marker.date); return day === null ? [] : [{ ...marker, day }]; }) : [];
  const issues = useMemo(() => [
    ...snapshot.projects.flatMap(project => {
      const projectRows = snapshot.items.filter(row => row.projeto_id === project.id), calendar = settingsByProject.get(project.id)?.calendar ?? DEFAULT_GANTT_CALENDAR;
      return [...calendarDependencyIssues(projectRows, links.filter(link => link.projeto_id === project.id), drafts, calendar), ...calendarDateIssues(projectRows, drafts, calendar)];
    }),
    ...snapshot.items.flatMap(row => { const issue = draftTimingIssue(row, drafts[row.id]); return issue ? [{ ...issue, allocation_id: row.id }] : []; }),
  ], [snapshot.items, snapshot.projects, links, drafts, settingsByProject]);
  const affectedProjects = new Set(items.map(item => snapshot.items.find(row => row.id === item.id)!.projeto_id));
  if (linksDirty && project) affectedProjects.add(project.id);
  const blockingIssues = issues.filter(issue => {
    if (issue.code === 'MISSING_DATES') return false;
    if (issue.code === 'NON_WORKING_START' || issue.code === 'NON_WORKING_END') {
      const field = issue.code === 'NON_WORKING_START' ? 'data_inicio' : 'data_limite';
      if (!items.some(item => item.id === issue.allocation_id && Object.hasOwn(item.changes, field))) return false;
    }
    const endpoints = [issue.allocation_id, issue.predecessor_id, issue.successor_id].filter(Boolean);
    return !dirty || !endpoints.length || endpoints.some(id => affectedProjects.has(snapshot.items.find(row => row.id === id)?.projeto_id ?? ''));
  });
  const changedInvalid = items.some(item => planningInterval(draftDates(snapshot.items.find(row => row.id === item.id)!, drafts[item.id])).kind === 'invalid');
  const daysWidth = period.days === 14 ? 48 : period.days === 42 ? 24 : 14;
  const chartWidth = daysWidth * period.days;
  const nonWorkingOffsets = useMemo(() => project ? Array.from({ length: period.days }, (_, offset) => offset).filter(offset => !isWorkingDay(projectCalendar, period.start + offset)) : [], [project, projectCalendar, period.days, period.start]);
  const filtered = useMemo(() => rows.filter(row => {
    if (search && !normalize(`${rowLabel(row)} ${row.cliente_nome_export || ''} ${row.responsavel_nome || ''}`).includes(normalize(search))) return false;
    if (status && row.status !== status) return false;
    const bar = plannerBar(row, period);
    return mode === 'all' || mode === 'unscheduled' && (bar.kind === 'missing' || bar.kind === 'invalid') || mode === 'period' && bar.kind !== 'outside';
  }), [rows, search, status, period, mode]);
  const groups = useMemo(() => {
    const grouped = new Map<string, { id: string; label: string; rows: GanttItem[] }>();
    for (const row of filtered) {
      const id = groupBy === 'project' ? row.projeto_id : row.celula_id;
      const label = groupBy === 'project' ? `${row.numero_projeto ? `OS ${row.numero_projeto}` : 'Projeto sem OS'}${row.cliente_nome_export ? ` · ${row.cliente_nome_export}` : ''}` : row.celula_nome || 'Célula';
      const group = grouped.get(id) ?? { id, label, rows: [] }; group.rows.push(row); grouped.set(id, group);
    }
    for (const group of grouped.values()) group.rows.sort((a, b) => (groupBy === 'project' ? (a.indice ?? 1e9) - (b.indice ?? 1e9) : (a.posicao ?? 1e9) - (b.posicao ?? 1e9)) || a.id.localeCompare(b.id));
    return [...grouped.values()];
  }, [filtered, groupBy]);
  const positions = useMemo(() => {
    let y = 0; const positions = new Map<string, number>();
    for (const group of groups) { y += 39; for (const row of group.rows) { positions.set(row.id, y + 29); y += 67; } }
    return { rows: positions, height: y };
  }, [groups]);
  const absent = rows.filter(row => planningInterval(row).kind === 'missing').length;
  const invalid = rows.filter(row => planningInterval(row).kind === 'invalid').length;
  const late = rows.filter(row => { const bar = plannerBar(row, period); return bar.kind === 'bar' && bar.overdue; }).length;

  useEffect(() => {
    if (!dirty && !save.busy && !save.uncertain && !settingsState?.dirty && !settingsState?.busy && !settingsState?.uncertain) return;
    const prompt = () => save.uncertain || settingsState?.uncertain ? 'O envio ainda não foi confirmado. Sair do Gantt?' : 'Há alterações no Gantt que não foram salvas. Sair sem salvar?';
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && (save.stale || settingsState?.stale) && !save.uncertain && !save.busy && !settingsState?.uncertain && !settingsState?.busy) { leaving.current = true; return; }
      if (!window.confirm(prompt())) { event.preventDefault(); event.stopPropagation(); } else leaving.current = true;
    };
    const submit = (event: Event) => {
      if (leaving.current || !(event.target instanceof HTMLFormElement) || event.target.hasAttribute('data-gantt-local')) return;
      if (!window.confirm(prompt())) { event.preventDefault(); event.stopPropagation(); } else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true); document.addEventListener('submit', submit, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); document.removeEventListener('submit', submit, true); };
  }, [dirty, save.busy, save.uncertain, save.stale, settingsState]);
  useEffect(() => { setPredecessor(''); setLag('0'); }, [selectedId]);

  function update(id: string, result: GanttDraftResult) {
    if (!editable) return;
    if (!result.ok) { setNotice(result.error); return; }
    setNotice(''); setDrafts(previous => { const next = { ...previous }; if (Object.keys(result.draft).length) next[id] = result.draft; else delete next[id]; return next; });
  }
  function choose(row: GanttItem, focus = false) {
    setSelectedId(row.id);
    if (focus) setTimeout(() => { detail.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); detail.current?.focus({ preventScroll: true }); }, 0);
  }
  function beginDrag(event: PointerEvent<HTMLButtonElement>, row: GanttItem, edge: 'move' | 'start' | 'end') {
    choose(row);
    if (!editable || !row.can_edit || event.button !== 0 || event.pointerType === 'touch' && edge === 'move') return;
    event.preventDefault(); event.stopPropagation();
    event.currentTarget.setPointerCapture(event.pointerId);
    drag.current = { id: row.id, x: event.clientX, edge, initial: { ...drafts[row.id] }, lastDelta: 0, target: event.currentTarget, pointer: event.pointerId };
  }
  function movePointer(event: PointerEvent<HTMLButtonElement>) {
    const current = drag.current; if (!current || current.pointer !== event.pointerId || !editable) return;
    const delta = Math.round((event.clientX - current.x) / daysWidth); if (delta === current.lastDelta) return;
    current.lastDelta = delta; const row = snapshot.items.find(row => row.id === current.id)!;
    update(row.id, current.edge === 'move' ? moveCalendarDraft(row, current.initial, delta, calendarFor(row)) : resizeCalendarDraft(row, current.initial, current.edge, delta, calendarFor(row)));
  }
  function endPointer(event: PointerEvent<HTMLButtonElement>, cancel = false) {
    const current = drag.current; if (!current || current.pointer !== event.pointerId) return;
    if (cancel) update(current.id, { ok: true, draft: current.initial });
    drag.current = null; if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
  }
  function setWindow(start: string, days: PlannerDays = period.days) { setPeriod(plannerWindow(start, days, new Date(snapshot.as_of))); }
  function fit() {
    const intervals = rows.map(planningInterval).filter(value => value.kind === 'valid');
    if (!intervals.length && !markers.length) { setNotice('Ainda não há um intervalo completo para ajustar o período.'); return; }
    const start = Math.min(...intervals.map(value => value.start), ...markers.map(marker => marker.day)), end = Math.max(...intervals.map(value => value.end), ...markers.map(marker => marker.day));
    setWindow(isoCalendarDay(start), end - start < 14 ? 14 : end - start < 42 ? 42 : 90);
    if (end - start >= 90) setNotice('O plano ultrapassa 90 dias. Use Próximo para consultar os demais períodos.');
  }
  function cascade() {
    if (!editable || scope !== 'project') return;
    const result = proposeCalendarCascade(snapshot.items, links, drafts, projectCalendar);
    if (!result.ok) { setNotice(result.error); return; }
    setDrafts(result.drafts); setNotice(result.changedIds.length ? `${result.changedIds.length} etapa(s) ajustada(s) na prévia. Revise antes de salvar.` : 'As datas já respeitam as dependências. Nenhuma alteração adicional.');
  }
  function addLink() {
    if (!selected || !editable || scope !== 'project' || !predecessor) return;
    const days = Number(lag);
    if (!Number.isInteger(days) || days < 0 || days > 3650) { setNotice('Informe uma espera entre 0 e 3.650 dias do calendário de trabalho.'); return; }
    if (links.some(link => link.predecessor_id === predecessor && link.successor_id === selected.id)) { setNotice('Essa dependência já existe. Remova o vínculo para alterar a espera.'); return; }
    const next = [...links, { projeto_id: selected.projeto_id, predecessor_id: predecessor, successor_id: selected.id, lag_days: days }];
    setLinks(next); setPredecessor(''); setNotice('Dependência acrescentada à prévia. Confira as datas antes de salvar.');
  }
  function payload(baseline?: { projeto_id: string; label: string }): SaveGanttPlanInput {
    const affected = new Set(items.map(item => snapshot.items.find(row => row.id === item.id)!.projeto_id));
    if (linksDirty && project) affected.add(project.id);
    if (baseline) affected.add(baseline.projeto_id);
    return { submissionId: crypto.randomUUID(), reason: baseline ? `Referência do planejamento: ${baseline.label}` : reason.trim(),
      projects: snapshot.projects.filter(row => affected.has(row.id)).sort((a, b) => a.id.localeCompare(b.id)).map(row => ({ id: row.id, expected_updated_at: row.updated_at, expected_plan_version: row.plan_version })),
      items, ...(linksDirty && project ? { dependencies: { projeto_id: project.id, links: links.map(({ predecessor_id, successor_id, lag_days }) => ({ predecessor_id, successor_id, lag_days })) } } : {}),
      ...(baseline ? { baseline } : {}) };
  }
  function commit() {
    if (save.uncertain) { save.retry(); return; }
    if (!editable || !dirty || reason.trim().length < 3 || changedInvalid || blockingIssues.length) return;
    void save.send(payload());
  }

  if (!snapshot.complete) return <div className="notice" role="status">O escopo tem {snapshot.total.toLocaleString('pt-BR')} etapas e excede o limite de 2.000. Abra o Gantt de uma célula ou de um projeto para trabalhar com um conjunto completo. Nenhuma página parcial pode ser salva.</div>;

  return <div className={s.workspace} data-gantt-planner>
    <EngineeringSaveNotice state={save} reload={destination} />
    {saved && <p className="notice success" role="status">Alterações confirmadas. Atualizando o Gantt…</p>}
    {(period.invalidDays || period.invalidStart) && <p className="notice">O período informado é inválido. Usando uma janela válida de planejamento.</p>}
    {notice && <p className="notice" role="status">{notice}</p>}
    {settingsState?.dirty && <p className="notice" role="status">Salve ou descarte a configuração de calendário e marcos para voltar à edição das datas. A análise abaixo usa o calendário salvo.</p>}
    {project && <GanttSettingsPanel project={project} settings={projectSettings} canManage={canManage && canProjects} destination={destination}
      hasPendingDateChanges={dirty || save.locked || saved} onStateChange={setSettingsState} onSaved={() => { leaving.current = true; setSaved(true); }} />}
    {analysis && <GanttCriticalPath analysis={analysis} rows={snapshot.items} useTarget={useTarget} hasTarget={!!targetDate} onTargetChange={setUseTarget} dirty={dirty} onSelect={row => choose(row, true)} />}
    <section className="panel">
      {project && <div className={s.projectDates}>
        <span>Início do projeto<strong>{dayLabel(project.planned_start)}</strong></span><span>Entrega prevista<strong>{dayLabel(project.planned_end)}</strong></span>
        <span>Data contratual<strong>{dayLabel(project.contract_date)}</strong></span><span>Data renegociada<strong>{dayLabel(project.renegotiated_date)}</strong></span>
        <span>Referência<strong>{snapshot.baseline?.label || 'Ainda não registrada'}</strong></span>
      </div>}
      <div className={s.toolbar}>
        <div className={s.period}><button type="button" className="button small secondary" onClick={() => setWindow(isoCalendarDay(period.start - period.days))} aria-label="Período anterior"><Icon name="back" size={14} /></button><strong>{formatGanttDay(period.start)} a {formatGanttDay(period.end)}</strong><button type="button" className="button small secondary" onClick={() => setWindow(isoCalendarDay(period.start + period.days))} aria-label="Próximo período"><Icon name="arrow" size={14} /></button><button className="button small secondary" type="button" onClick={() => setWindow(isoCalendarDay(period.today - 3))}>Hoje</button><button className="button small secondary" type="button" onClick={fit}>Ajustar às datas</button></div>
        <label>Escala<select aria-label="Escala do Gantt" value={period.days} onChange={event => setWindow(period.isoStart, Number(event.target.value) as PlannerDays)}><option value={14}>Dias · 2 semanas</option><option value={42}>Semanas · 6 semanas</option><option value={90}>Meses · 90 dias</option></select></label>
        <label>Início do período<input type="date" aria-label="Início do período do Gantt" value={period.isoStart} onChange={event => event.target.value && setWindow(event.target.value)} /></label>
      </div>
      <div className={s.toolbar}>
        <label className={s.search}>Pesquisar nesta visão<input aria-label="Pesquisar etapas do Gantt" value={search} onChange={event => setSearch(event.target.value)} placeholder="OS, célula, cliente ou responsável" /></label>
        {scope === 'general' && <label>Agrupar por<select aria-label="Agrupar Gantt por" value={groupBy} onChange={event => setGroupBy(event.target.value as 'project' | 'cell')}><option value="project">Projeto</option><option value="cell">Célula</option></select></label>}
        <label>Etapas<select aria-label="Etapas exibidas" value={mode} onChange={event => setMode(event.target.value as typeof mode)}><option value="period">No período e sem programação</option><option value="all">Todas deste escopo</option><option value="unscheduled">Sem datas ou com datas inválidas</option></select></label>
        <label>Status<select aria-label="Status no Gantt" value={status} onChange={event => setStatus(event.target.value)}><option value="">Todos</option>{[...new Set(snapshot.items.map(row => row.status).filter((value): value is string => !!value))].sort().map(value => <option value={value} key={value}>{display(value)}</option>)}</select></label>
      </div>
      <div className={s.summary}><span><strong>{filtered.length}</strong> de {snapshot.total} etapas exibidas</span><span className={absent || invalid ? s.warn : ''}><strong>{absent}</strong> sem intervalo · <strong>{invalid}</strong> com datas inválidas</span><span><strong>{late}</strong> com prazo vencido no período</span><span>Consulta em {date(snapshot.as_of, true)}</span></div>
      <div className={s.legend}><span><i />Planejado</span><span><i className={s.late} />Prazo vencido</span><span><i className={s.done} />Finalizado</span><span><i className={s.draft} />Alteração não salva</span>{analysis?.complete && <span><i className={s.criticalLegend} />Caminho crítico da rede</span>}{project && <span><i className={s.nonWorkingLegend} />Dia não útil</span>}{snapshot.baseline && <label><input type="checkbox" checked={showBaseline} onChange={event => setShowBaseline(event.target.checked)} /> Mostrar referência</label>}<label><input type="checkbox" checked={showLinks} onChange={event => setShowLinks(event.target.checked)} /> Mostrar dependências</label></div>
      {markers.length > 0 && <details className={s.markerList}><summary>Marcos e datas de referência · {markers.length}</summary><ul>{markers.map(marker => <li key={marker.id}><strong>{formatGanttDay(marker.day)}</strong> · {marker.label}{!marker.custom && <small> · data do projeto</small>}<button type="button" className="button small secondary" onClick={() => setWindow(isoCalendarDay(marker.day - 3))}>Ver no Gantt</button></li>)}</ul><p className="form-note">Marcos sinalizam datas; não acrescentam duração ou dependências à rede.</p></details>}
      <div className={`${s.body} ${selected ? s.withDetails : ''}`}>
        <div className={s.chartPane}><div className={s.chartScroll} role="region" aria-label="Gantt de etapas com rolagem horizontal e vertical" tabIndex={0}>
          <div className={s.chart} style={{ width: `calc(var(--label-width, 250px) + ${chartWidth}px)`, minHeight: markers.some(marker => marker.day >= period.start && marker.day <= period.end) ? 87 : undefined, '--day-width': `${daysWidth}px` } as CSSProperties}>
            <div className={s.axis}><div className={s.axisLabel}>Projeto / etapa</div><div className={s.axisTrack}>{period.ticks.map(tick => <span className={s.tick} key={tick} style={{ left: (tick - period.start) * daysWidth }}>{formatGanttDay(tick, true)}</span>)}</div></div>
            {markers.filter(marker => marker.day >= period.start && marker.day <= period.end).map(marker => <div key={marker.id} className={`${s.marker} ${marker.custom ? s.customMarker : ''}`} aria-hidden="true" title={`${marker.label}: ${formatGanttDay(marker.day)}`} style={{ left: `calc(var(--label-width) + ${(marker.day - period.start + .5) * daysWidth}px)`, height: Math.max(39, positions.height) }}><span>◆</span></div>)}
            {groups.map(group => {
              const valid = group.rows.map(planningInterval).filter(value => value.kind === 'valid');
              const groupBar = valid.length ? plannerBar({ data_inicio: isoCalendarDay(Math.min(...valid.map(value => value.start))), data_limite: isoCalendarDay(Math.max(...valid.map(value => value.end))) }, period) : null;
              return <div key={group.id}><div className={s.group}><div className={s.groupTitle} title={group.label}>{group.label}</div><div className={s.groupTrack}>{groupBar?.kind === 'bar' && <span className={s.groupBar} style={{ left: `${groupBar.left}%`, width: `${groupBar.width}%` }} />}</div></div>{group.rows.map(row => {
                const original = snapshot.items.find(item => item.id === row.id)!;
                const bar = plannerBar(row, period), baseline = snapshot.baseline?.items.find(item => item.allocation_id === row.id), reference = baseline && plannerBar(baseline, period);
                const title = `${rowLabel(row)}. ${dayLabel(row.data_inicio)} a ${dayLabel(row.data_limite)}. ${display(row.status)}.`;
                const writable = editable && row.can_edit;
                return <div className={`${s.row} ${selectedId === row.id ? s.selected : ''}`} key={row.id} data-gantt-row={row.id}>
                  <button type="button" className={s.rowTitle} data-gantt-row-title={row.id} onClick={() => choose(original, true)} aria-label={`Planejar ${rowLabel(row)}`} aria-pressed={selectedId === row.id}><strong>{groupBy === 'project' ? row.celula_nome || 'Célula' : row.numero_projeto ? `OS ${row.numero_projeto}` : 'Projeto sem OS'}</strong><small>{display(row.status)}{row.bloqueada === 'sim' ? ' · Bloqueada' : ''}{!row.visibilidade ? ' · Oculta no mobile' : ''}</small><small>{row.responsavel_nome || 'Responsável não informado'}</small></button>
                  <div className={s.track}>
                    {nonWorkingOffsets.map(offset => <span aria-hidden="true" className={s.nonWorking} key={offset} style={{ left: offset * daysWidth, width: daysWidth }} />)}
                    {period.today >= period.start && period.today <= period.end && <span className={s.today} style={{ left: (period.today - period.start + .5) * daysWidth }} />}
                    {reference?.kind === 'bar' && showBaseline && <span className={s.baseline} style={{ left: `${reference.left}%`, width: `${reference.width}%` }} title={`Referência: ${dayLabel(baseline?.data_inicio)} a ${dayLabel(baseline?.data_limite)}`} />}
                    {bar.kind === 'bar' ? <div data-gantt-critical={criticalIds.has(row.id) || undefined} className={`${s.bar} ${drafts[row.id] ? s.draft : bar.complete ? s.done : bar.overdue ? s.late : ''} ${criticalIds.has(row.id) ? s.critical : ''}`} style={{ left: `${bar.left}%`, width: `${bar.width}%` }}>
                      <button type="button" className={s.barFill} title={title} aria-label={`${title} Abrir datas${writable ? '; use as setas para mover um dia' : ''}`} onClick={() => choose(original)}
                        onPointerDown={event => beginDrag(event, original, 'move')} onPointerMove={movePointer} onPointerUp={event => endPointer(event)} onPointerCancel={event => endPointer(event, true)}
                        onKeyDown={event => { if (writable && ['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); update(row.id, moveCalendarDraft(original, drafts[row.id] ?? {}, event.key === 'ArrowRight' ? 1 : -1, calendarFor(original))); } }}>
                        {bar.clippedStart ? '← ' : ''}{formatGanttDay(bar.start, true)} — {formatGanttDay(bar.end, true)}{bar.clippedEnd ? ' →' : ''}
                      </button>
                      {writable && !bar.clippedStart && <button type="button" className={`${s.handle} ${s.handleStart}`} aria-label={`Ajustar início de ${rowLabel(row)}`} title="Arraste para ajustar o início; setas movem um dia" onPointerDown={event => beginDrag(event, original, 'start')} onPointerMove={movePointer} onPointerUp={event => endPointer(event)} onPointerCancel={event => endPointer(event, true)} onKeyDown={event => { if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); update(row.id, resizeCalendarDraft(original, drafts[row.id] ?? {}, 'start', event.key === 'ArrowRight' ? 1 : -1, calendarFor(original))); } }} />}
                      {writable && !bar.clippedEnd && <button type="button" className={`${s.handle} ${s.handleEnd}`} aria-label={`Ajustar prazo de ${rowLabel(row)}`} title="Arraste para ajustar o prazo; setas movem um dia" onPointerDown={event => beginDrag(event, original, 'end')} onPointerMove={movePointer} onPointerUp={event => endPointer(event)} onPointerCancel={event => endPointer(event, true)} onKeyDown={event => { if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); update(row.id, resizeCalendarDraft(original, drafts[row.id] ?? {}, 'end', event.key === 'ArrowRight' ? 1 : -1, calendarFor(original))); } }} />}
                    </div> : <span className={s.noDates}>{bar.kind === 'missing' ? 'Sem intervalo completo · abra para programar' : bar.kind === 'invalid' ? 'Datas inválidas · revisar' : 'Fora do período selecionado'}</span>}
                  </div>
                </div>;
              })}</div>;
            })}
            {showLinks && positions.height > 0 && <svg aria-hidden="true" className={s.dependencyLines} width={chartWidth} height={positions.height} style={{ top: 48 }}><defs><marker id={arrowId} markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6" fill="#7789a1" /></marker></defs>{links.map(link => {
              const from = rows.find(row => row.id === link.predecessor_id), to = rows.find(row => row.id === link.successor_id);
              if (!from || !to || !positions.rows.has(from.id) || !positions.rows.has(to.id)) return null;
              const end = planningDay(from.data_limite), start = planningDay(to.data_inicio);
              if (end === null || start === null || end < period.start || end > period.end || start < period.start || start > period.end) return null;
              const x1 = (end - period.start + 1) * daysWidth, x2 = (start - period.start) * daysWidth, y1 = positions.rows.get(from.id)!, y2 = positions.rows.get(to.id)!;
              return <path key={`${from.id}:${to.id}`} d={`M${x1},${y1} H${x1 + 8} V${y2 - 18} H${x2 - 8} V${y2} H${x2 - 1}`} fill="none" stroke="#7789a1" strokeWidth="1.2" markerEnd={`url(#${arrowId})`} />;
            })}</svg>}
          </div>
          {!filtered.length && <div className={s.noResults}>Nenhuma etapa corresponde aos filtros. Amplie o período, limpe a pesquisa ou consulte as etapas sem programação.</div>}
        </div></div>
        {selected && selectedDates && <aside className={s.detail} tabIndex={-1} ref={detail} aria-label="Planejamento da etapa selecionada">
          <div className={s.detailHead}><div><small>{selected.numero_projeto ? `OS ${selected.numero_projeto}` : 'Projeto sem OS'}</small><h3>{selected.celula_nome || 'Célula'}</h3></div><button type="button" className="button small secondary" onClick={() => { document.querySelector<HTMLButtonElement>(`[data-gantt-row-title="${selectedId}"]`)?.focus(); setSelectedId(''); }} aria-label="Fechar etapa"><Icon name="close" size={14} /></button></div>
          <p>{display(selected.status)} · {selected.visibilidade ? 'Visível no mobile' : 'Oculta no mobile'}</p>
          <p>Calendário: {calendarFor(selected).weekdays.length === 7 && !calendarFor(selected).exceptions.length ? 'todos os dias' : `${calendarFor(selected).weekdays.length} dia(s) por semana, com ${calendarFor(selected).exceptions.length} exceção(ões)`}. {(() => { const value = countWorkingDays(calendarFor(selected), selectedDates.data_inicio ?? '', selectedDates.data_limite ?? ''); return value === null ? '' : `Duração: ${value} dia(s) de trabalho.`; })()}</p>
          {selectedAnalysis && <GanttStageAnalysis node={selectedAnalysis} />}
          {selected.bloqueada === 'sim' && <p className="notice">Bloqueada: {selected.motivo_bloqueio || 'motivo não informado'}</p>}
          {!selected.can_edit && <p className="notice">{canManage ? 'Etapa ou projeto encerrado. Os prazos permanecem em consulta.' : 'Seu perfil permite consultar os prazos desta etapa.'}</p>}
          <fieldset disabled={!editable || !selected.can_edit}>
            <label>Início previsto<input type="date" aria-label="Início previsto da etapa" min={GANTT_EDIT_MIN_DATE} max={GANTT_EDIT_MAX_DATE} value={dateInput(selectedDates.data_inicio)} onChange={event => update(selected.id, changeDateDraft(selected, drafts[selected.id] ?? {}, 'data_inicio', event.target.value || null))} /></label>
            <label>Prazo da etapa<input type="date" aria-label="Prazo da etapa" min={GANTT_EDIT_MIN_DATE} max={GANTT_EDIT_MAX_DATE} value={dateInput(selectedDates.data_limite)} onChange={event => update(selected.id, changeDateDraft(selected, drafts[selected.id] ?? {}, 'data_limite', event.target.value || null))} /></label>
          </fieldset>
          <div className={s.inlineActions}><button type="button" className="button small secondary" disabled={!editable || !selected.can_edit} onClick={() => update(selected.id, moveCalendarDraft(selected, drafts[selected.id] ?? {}, -1, calendarFor(selected)))}>Antecipar 1 dia</button><button type="button" className="button small secondary" disabled={!editable || !selected.can_edit} onClick={() => update(selected.id, moveCalendarDraft(selected, drafts[selected.id] ?? {}, 1, calendarFor(selected)))}>Adiar 1 dia</button></div>
          {selectedBaseline && <p>Referência: {dayLabel(selectedBaseline.data_inicio)} a {dayLabel(selectedBaseline.data_limite)}. {(() => { const delta = baselineDelta(selected, selectedBaseline, drafts[selected.id]); return delta.endDays == null ? '' : `Variação do prazo em dias corridos: ${delta.endDays > 0 ? '+' : ''}${delta.endDays} dia(s).`; })()}</p>}
          <h4>Dependências término-início</h4>
          <p>A etapa começa no primeiro dia de trabalho após o término da predecessora, acrescido da espera em dias do calendário do projeto.</p>
          <ul className={s.links}>{links.filter(link => link.successor_id === selected.id).map(link => <li key={link.predecessor_id}><span>{snapshot.items.find(row => row.id === link.predecessor_id)?.celula_nome || 'Etapa anterior'} · espera {link.lag_days} dia(s)</span>{scope === 'project' && <button type="button" className="button small secondary" aria-label="Remover dependência" disabled={!editable} onClick={() => { setLinks(current => current.filter(item => item !== link)); setNotice(''); }}><Icon name="close" size={12} /></button>}</li>)}</ul>
          {scope === 'project' ? <fieldset disabled={!editable || !selected.can_edit}><label>Depende de<select aria-label="Etapa predecessora" value={predecessor} onChange={event => setPredecessor(event.target.value)}><option value="">Selecione uma etapa</option>{snapshot.items.filter(row => row.projeto_id === selected.projeto_id && row.id !== selected.id).map(row => <option value={row.id} key={row.id}>{row.celula_nome || 'Célula'}</option>)}</select></label><label>Espera em dias de trabalho<input type="number" aria-label="Espera após predecessora" value={lag} min={0} max={3650} onChange={event => setLag(event.target.value)} /></label><button type="button" className="button small secondary" disabled={!predecessor} onClick={addLink}>Adicionar dependência</button></fieldset> : canProjects && <p><a href={`/cronograma?view=gantt&scope=project&project=${selected.projeto_id}&allocation=${selected.id}`}>Abrir Gantt do projeto para trabalhar dependências</a></p>}
          {canProjects && <><h4>Etapas e registros</h4><div className={s.inlineActions}><a className="button small secondary" href={`/planejamento/capacidade?project=${selected.projeto_id}&allocation=${selected.id}`}>Pessoas, máquinas e reservas</a><a className="button small secondary" href={`/cronograma?view=project&project=${selected.projeto_id}&allocation=${selected.id}`}>Fotos, formulários e aprovações</a><a className="button small secondary" href={`/projetos/${selected.projeto_id}?tab=planejamento&allocation=${selected.id}#celula-${selected.id}`}>Responsável, status e bloqueios</a></div></>}
        </aside>}
      </div>
      <div className={s.footer}><p>{editable ? 'Selecione uma etapa para editar as datas ou arraste sua barra. As extremidades ajustam início e prazo. As setas do teclado também movem as datas. No celular, use os campos e os botões da etapa.' : 'Seu acesso permite consultar os prazos e os registros disponíveis.'} Datas em São Paulo, com início e término inclusivos. As reservas de pessoas e máquinas permanecem nas datas registradas; revise os impactos em Capacidade. Alterar prazos não altera a fila, libera aprovações ou calcula capacidade de pessoas e máquinas.</p></div>
      {project && !project.closed && canManage && <details className={s.baselineForm}><summary>Referência do plano {snapshot.baseline ? `· ${snapshot.baseline.label}` : '· registrar a primeira versão'}</summary><p className="form-note">Registre os prazos atuais de todas as etapas deste projeto para comparar mudanças. A comparação usa a referência mais recente. As referências anteriores são preservadas.</p><form data-gantt-local onSubmit={event => { event.preventDefault(); if (editable && !dirty && baselineLabel.trim()) void save.send(payload({ projeto_id: project.id, label: baselineLabel.trim() })); }}><label>Nome da referência<input value={baselineLabel} onChange={event => setBaselineLabel(event.target.value)} maxLength={120} placeholder="Ex.: Plano aprovado de novembro" required disabled={locked || dirty} /></label><button type="submit" className="button small secondary" disabled={locked || dirty || !baselineLabel.trim()}>Registrar referência atual</button></form>{dirty && <p className="form-note">Salve ou descarte a prévia antes de registrar uma referência.</p>}</details>}
    </section>
    {(issues.length > 0 || changedInvalid) && <div className={`notice ${blockingIssues.length || changedInvalid ? 'error' : ''}`} role={blockingIssues.length || changedInvalid ? 'alert' : 'status'}>{blockingIssues.length || changedInvalid ? 'Revise as datas e dependências antes de salvar.' : issues.every(issue => issue.code.startsWith('NON_WORKING_')) ? 'Há datas existentes em dias não úteis. Elas permanecem preservadas; corrija explicitamente para concluir a análise da rede.' : issues.every(issue => issue.code === 'MISSING_DATES') ? 'As dependências podem ser registradas sem datas. Informe os intervalos para validar os prazos e reprogramar dependentes.' : 'Há pendências em outras etapas. Ao salvar, serão validados os projetos incluídos nas alterações.'}{changedInvalid && <p>Há uma alteração com prazo anterior ao início.</p>}<ul className={s.issueList}>{issues.map((issue, index) => <li key={`${issue.code}:${index}`}>{issue.allocation_id && snapshot.items.find(row => row.id === issue.allocation_id)?.celula_nome ? `${snapshot.items.find(row => row.id === issue.allocation_id)!.celula_nome}: ` : ''}{issue.message}</li>)}</ul>{scope === 'project' && <button type="button" className="button small secondary" onClick={cascade} disabled={!editable}>Reprogramar dependentes na prévia</button>}</div>}
    {(dirty || save.uncertain) && <section className={s.saveBar} aria-label="Revisão das alterações do Gantt"><h3>Revisar alterações antes de salvar</h3><p>{items.length} etapa(s) com datas alteradas{linksDirty ? ' e dependências modificadas' : ''}. O plano oficial será atualizado somente após a confirmação abaixo.</p>
      <details><summary>Conferir datas anteriores e novas</summary><div className={s.review}><table><thead><tr><th>Etapa</th><th>Antes</th><th>Prévia</th></tr></thead><tbody>{items.map(item => { const row = snapshot.items.find(row => row.id === item.id)!; const proposed = draftDates(row, drafts[row.id]); return <tr key={item.id}><td>{rowLabel(row)}</td><td>{dayLabel(row.data_inicio)} a {dayLabel(row.data_limite)}</td><td>{dayLabel(proposed.data_inicio)} a {dayLabel(proposed.data_limite)}</td></tr>; })}</tbody></table></div></details>
      <label>Motivo do ajuste<textarea aria-label="Motivo do ajuste do Gantt" value={reason} onChange={event => setReason(event.target.value)} minLength={3} maxLength={2000} rows={2} placeholder="Explique a alteração de prazo ou sequência de etapas." disabled={locked} /></label>
      <div className={s.inlineActions}><button type="button" className="button secondary" disabled={locked} onClick={() => { setDrafts({}); setLinks(snapshot.links); setReason(''); setNotice('Prévia descartada. O plano oficial foi preservado.'); }}>Descartar prévia</button>{scope === 'project' && <button type="button" className="button secondary" disabled={!editable} onClick={cascade}>Reprogramar dependentes</button>}<button type="button" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!editable || !dirty || reason.trim().length < 3 || changedInvalid || blockingIssues.length > 0)} onClick={commit}>{save.busy ? 'Confirmando plano…' : save.uncertain ? 'Tentar confirmar envio' : 'Confirmar e salvar plano'}</button></div>
    </section>}
  </div>;
}
