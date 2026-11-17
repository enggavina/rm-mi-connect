'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import type { ExecutionSnapshot } from '@/server/web/execution-data';
import type { ReviewExecutionSessionInput } from '@/server/web/execution-policy';
import { reviewExecutionSession } from '@/server/web/execution-actions';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { allocationExecutionState, confirmedExecutionEffort, executionEventLabel, executionEvidenceAge, executionInputInstant, executionNeedsReview, executionPauseLabel, executionReviewReasonLabel, executionSaoPauloInput, executionSearchMatches, executionStateLabel, parseExecutionMinutes, type ExecutionCardState } from './execution-model';
import { date, display } from './ui';
import { Icon } from './icons';
import s from './execution-board.module.css';

export type ExecutionBoardProps = { snapshot: ExecutionSnapshot; canManage: boolean; destination: string };
const minutesLabel = (value: number | null) => value === null ? 'Não informado' : `${value.toLocaleString('pt-BR')} min`;
const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const stateClass: Record<ExecutionCardState | 'void', string> = { running: 'running', paused: 'paused', finished: 'finished', unknown: 'unknown', review: 'reviewState', void: 'unknown' };

export function ExecutionBoard({ snapshot, canManage, destination }: ExecutionBoardProps) {
  const [search, setSearch] = useState(''), [stateFilter, setStateFilter] = useState<ExecutionCardState | ''>('');
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState(false), [action, setAction] = useState<ReviewExecutionSessionInput['action']>('confirm_finished');
  const [finishedAt, setFinishedAt] = useState(''), [effort, setEffort] = useState(''), [note, setNote] = useState(''), [reason, setReason] = useState(''), [reviewing, setReviewing] = useState(false), [saved, setSaved] = useState(false);
  const leaving = useRef(false), initial = useRef(''), formRef = useRef<HTMLElement>(null), reviewRef = useRef<HTMLElement>(null);
  const save = useEngineeringSave<ReviewExecutionSessionInput>(async input => { const result = await reviewExecutionSession(input); if (result.ok) { leaving.current = true; setSaved(true); } return result; }, destination);
  const locked = save.locked || saved, detail = snapshot.detail, selected = detail?.session;
  const fields = useMemo(() => ({ action, finishedAt, effort, note, reason }), [action, finishedAt, effort, note, reason]);
  const dirty = editing && JSON.stringify(fields) !== initial.current;
  const editable = canManage && snapshot.complete && !!selected && !locked;
  const reportedAt = action === 'confirm_finished' ? executionInputInstant(finishedAt) : null;
  const effortMinutes = action === 'confirm_finished' ? parseExecutionMinutes(effort) : null;
  const validFields = action === 'void' || reportedAt !== null && effortMinutes !== undefined;
  const byAllocation = useMemo(() => {
    const result = new Map<string, ExecutionSnapshot['sessions']>();
    for (const session of snapshot.sessions) { const rows = result.get(session.allocation_id) ?? []; rows.push(session); result.set(session.allocation_id, rows); }
    return result;
  }, [snapshot.sessions]);
  const cards = useMemo(() => snapshot.allocations.map(allocation => {
    const sessions = byAllocation.get(allocation.id) ?? [];
    return { allocation, sessions, state: allocationExecutionState(sessions), effort: confirmedExecutionEffort(sessions) };
  }), [snapshot.allocations, byAllocation]);
  const stats = useMemo(() => cards.reduce((counts, card) => ({ ...counts, [card.state]: counts[card.state] + 1 }), { running: 0, paused: 0, finished: 0, unknown: 0, review: 0 }), [cards]);
  const filtered = useMemo(() => cards.filter(card => (!stateFilter || card.state === stateFilter) && executionSearchMatches(search, [card.allocation.numero_projeto, card.allocation.cliente_nome, card.allocation.cell_name, ...card.sessions.map(session => session.operator_name)]))
    .sort((a, b) => normalize(a.allocation.cell_name || '').localeCompare(normalize(b.allocation.cell_name || '')) || (a.allocation.numero_projeto || '').localeCompare(b.allocation.numero_projeto || '') || a.allocation.id.localeCompare(b.allocation.id)), [cards, search, stateFilter]);
  const pages = Math.max(1, Math.ceil(filtered.length / 100)), currentPage = Math.min(page, pages);
  const pageCards = useMemo(() => filtered.slice((currentPage - 1) * 100, currentPage * 100), [filtered, currentPage]);
  const groups = useMemo(() => {
    const result = new Map<string, { label: string; cards: typeof pageCards }>();
    for (const card of pageCards) { const group = result.get(card.allocation.cell_id) ?? { label: card.allocation.cell_name || 'Célula', cards: [] }; group.cards.push(card); result.set(card.allocation.cell_id, group); }
    return [...result.entries()];
  }, [pageCards]);
  function sessionHref(session: ExecutionSnapshot['sessions'][number]) {
    const query = new URLSearchParams({ session: session.id });
    if (snapshot.filters.project_id) query.set('project', snapshot.filters.project_id);
    if (snapshot.filters.cell_id) query.set('cell', snapshot.filters.cell_id);
    if (!snapshot.filters.project_id && !snapshot.filters.cell_id) query.set('project', session.project_id);
    if (snapshot.filters.include_closed) query.set('closed', 'yes');
    return `/planejamento/execucao?${query}#apontamento`;
  }
  const closeQuery = new URLSearchParams();
  if (snapshot.filters.project_id) closeQuery.set('project', snapshot.filters.project_id);
  if (snapshot.filters.cell_id) closeQuery.set('cell', snapshot.filters.cell_id);
  if (snapshot.filters.include_closed) closeQuery.set('closed', 'yes');
  const closeHref = `/planejamento/execucao${closeQuery.size ? `?${closeQuery}` : ''}`;

  useEffect(() => {
    if (!dirty && !save.busy && !save.uncertain) return;
    const message = () => save.uncertain ? 'O envio ainda não foi confirmado. Sair dos apontamentos?' : 'Há uma reconciliação não salva. Sair sem salvar?';
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && save.stale && !save.uncertain && !save.busy) { leaving.current = true; return; }
      if (!window.confirm(message())) { event.preventDefault(); event.stopPropagation(); } else leaving.current = true;
    };
    const submit = (event: Event) => {
      if (leaving.current || !(event.target instanceof HTMLFormElement) || event.target.hasAttribute('data-execution-local')) return;
      if (!window.confirm(message())) { event.preventDefault(); event.stopPropagation(); } else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true); document.addEventListener('submit', submit, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); document.removeEventListener('submit', submit, true); };
  }, [dirty, save.busy, save.uncertain, save.stale]);

  function edit() {
    if (!editable) return;
    const lastReview = [...(detail?.reviews ?? [])].reverse().find(row => row.action === 'confirm_finished');
    const lastFinish = [...(detail?.events ?? [])].reverse().find(row => row.kind === 'finish' && row.disposition === 'accepted');
    const start = selected?.state === 'finished' ? executionSaoPauloInput(lastReview?.reported_finished_at ?? lastFinish?.occurred_at ?? null) : '';
    const next = { action: 'confirm_finished' as const, finishedAt: start, effort: selected?.confirmed_minutes == null ? '' : String(selected.confirmed_minutes), note: '', reason: '' };
    initial.current = JSON.stringify(next); setAction(next.action); setFinishedAt(next.finishedAt); setEffort(next.effort); setNote(''); setReason(''); setReviewing(false); setEditing(true);
    setTimeout(() => { formRef.current?.focus({ preventScroll: true }); formRef.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }, 0);
  }
  function discard() { if (locked) return; setEditing(false); setReviewing(false); setReason(''); setNote(''); setFinishedAt(''); setEffort(''); }
  function fieldChanged() { setReviewing(false); }
  function review() {
    if (!editable || !validFields || reason.trim().length < 3) return;
    if (reportedAt && Date.parse(reportedAt) > Date.now() + 15 * 60000) { save.setError('O término informado deve estar no passado ou até 15 minutos à frente do momento atual.'); return; }
    save.setError(''); setReviewing(true); setTimeout(() => { reviewRef.current?.focus({ preventScroll: true }); reviewRef.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }, 0);
  }
  function commit() {
    if (save.uncertain) { save.retry(); return; }
    if (!editable || !selected || !reviewing || !validFields || reason.trim().length < 3 || reportedAt && Date.parse(reportedAt) > Date.now() + 15 * 60000) return;
    void save.send({ submissionId: crypto.randomUUID(), session_id: selected.id, expected_version: selected.version, action,
      reported_finished_at: action === 'confirm_finished' ? reportedAt : null, effort_minutes: action === 'confirm_finished' ? effortMinutes ?? null : null, note: note.trim(), reason: reason.trim() });
  }

  if (!snapshot.complete) return <div className="notice" role="status">O conjunto de execução excede o limite de consulta completa. Selecione um projeto ou uma célula para reduzir o escopo. Os dados parciais não serão usados para indicadores ou reconciliação.</div>;

  return <div className={s.workspace} data-execution-board>
    <EngineeringSaveNotice state={save} reload={destination} />
    {saved && <p className="notice success" role="status">Reconciliação confirmada. Atualizando os apontamentos…</p>}
    <p className={s.note}>Dados recebidos até {date(snapshot.as_of, true)}. As situações refletem os últimos apontamentos recebidos. Eventos preservados em aparelhos offline ainda podem chegar; ausência de apontamento significa situação a confirmar.</p>
    <div className={s.metrics}>{([['running', 'Trabalho informado'], ['paused', 'Pausas informadas'], ['finished', 'Término informado'], ['unknown', 'Situação a confirmar'], ['review', 'Requer revisão']] as const).map(([state, label]) => <div className={`panel ${s.metric}`} key={state}><span>{label}</span><strong>{stats[state]}</strong><small>etapa(s) neste escopo</small></div>)}</div>
    <section className="panel"><div className={s.sectionHead}><div><h2>Apontamentos por célula</h2><p>{pageCards.length} etapa(s) nesta página · {filtered.length} correspondem aos filtros · {snapshot.total} no escopo completo. Mais de um operador pode apontar trabalho na mesma etapa.</p></div><div className={s.filters}><label>Pesquisar nesta visão<input aria-label="Pesquisar apontamentos de execução" value={search} onChange={event => { setSearch(event.target.value); setPage(1); }} placeholder="OS, cliente, célula ou operador" /></label><label>Situação informada<select aria-label="Filtrar situação da execução" value={stateFilter} onChange={event => { setStateFilter(event.target.value as typeof stateFilter); setPage(1); }}><option value="">Todas</option>{(['running', 'paused', 'finished', 'unknown', 'review'] as const).map(value => <option value={value} key={value}>{executionStateLabel[value]}</option>)}</select></label></div></div>
      {!filtered.length && <div className={s.empty}><Icon name="clipboard" size={24} /><h3>Nenhuma etapa corresponde à consulta</h3><p>Ajuste a pesquisa ou os filtros para consultar os apontamentos recebidos.</p></div>}
      {groups.map(([cellId, group]) => <div className={s.group} key={cellId}><h3>{group.label}<small>{group.cards.length} etapa(s)</small></h3><div className={s.cards}>{group.cards.map(({ allocation, sessions, state, effort: effortSummary }) => <article className={s.card} key={allocation.id} data-execution-allocation={allocation.id}>
        <div className={s.cardHead}><div><strong>{allocation.numero_projeto ? `OS ${allocation.numero_projeto}` : 'Projeto sem OS'}</strong><small>{allocation.cliente_nome || 'Cliente não informado'}</small></div><span className={`${s.badge} ${s[stateClass[state]]}`}>{executionStateLabel[state]}</span></div>
        <p className={s.metadata}>Status do planejamento: {display(allocation.status)}{allocation.retired ? ' · Célula retirada' : allocation.project_closed ? ' · Projeto encerrado' : ''}{!allocation.visible ? ' · Oculta no mobile' : ''}</p>
        {allocation.blocked && <p className={s.warning}>Bloqueio informado no planejamento.</p>}
        <p className={s.metadata}>Previsto: {date(allocation.planned_start)} a {date(allocation.planned_end)}</p>
        {!sessions.length ? <p className={s.unknownMessage}>Sem apontamento recebido. Confirme a situação com a equipe.</p> : <ul className={s.sessions}>{sessions.map(session => <li key={session.id}><div><strong>{session.operator_name || 'Operador não identificado'}</strong><span>{executionStateLabel[session.state]}{executionNeedsReview(session) && session.state !== 'review' ? ' · requer revisão' : ''}</span><small>Capturado: {date(session.last_captured_at, true)}</small><small>Recebido: {date(session.last_received_at, true)} · {executionEvidenceAge(session.last_received_at, snapshot.as_of)}</small>{session.clock_warning && <small className={s.warning}>Alerta de relógio preservado{session.has_review ? ' · revisão da gestão registrada' : ''}</small>}</div><a href={sessionHref(session)} className="text-link" aria-label={`Consultar apontamento de ${session.operator_name || 'operador'} em ${allocation.numero_projeto || 'projeto sem OS'}`}>Consultar<Icon name="chevron" size={13} /></a></li>)}</ul>}
        {sessions.length > 0 && <p className={s.effort}>Esforço informado nos apontamentos exibidos: {minutesLabel(effortSummary.minutes)}{effortSummary.missing ? ` · ${effortSummary.missing} apontamento(s) com esforço ausente ou pendente de revisão` : ''}</p>}
        <div className={s.cardLinks}><a href={`/projetos/${allocation.project_id}?tab=planejamento&allocation=${allocation.id}#celula-${allocation.id}`}>Projeto e planejamento</a><a href={`/cronograma?view=gantt&scope=project&project=${allocation.project_id}&allocation=${allocation.id}`}>Gantt</a></div>
      </article>)}</div></div>)}
      {pages > 1 && <nav className={s.pagination} aria-label="Páginas das etapas de execução"><button type="button" className="button small secondary" disabled={currentPage === 1} onClick={() => setPage(currentPage - 1)}>Etapas anteriores</button><span>Página {currentPage} de {pages} · 100 etapas por página</span><button type="button" className="button small secondary" disabled={currentPage === pages} onClick={() => setPage(currentPage + 1)}>Próximas etapas</button></nav>}
    </section>

    {detail && selected && <section id="apontamento" tabIndex={-1} className={`panel ${s.detail}`} aria-label="Detalhes do apontamento"><div className={s.sectionHead}><div><h2>Apontamento de {selected.operator_name || 'operador não identificado'}</h2><p>OS {selected.numero_projeto || 'não atribuída'} · {selected.cell_name || 'Célula'} · <span className={`${s.badge} ${s[stateClass[selected.state]]}`}>{executionStateLabel[selected.state]}</span></p></div><a className="button small secondary" href={closeHref}>Fechar apontamento</a></div>
      <div className={s.detailContent}><div className={s.evidence}><span>Última captura<strong>{date(selected.last_captured_at, true)}</strong></span><span>Último recebimento<strong>{date(selected.last_received_at, true)}</strong></span><span>Esforço declarado no histórico<strong>{minutesLabel(selected.confirmed_minutes)}</strong><small>{selected.effort_source === 'operator' ? 'Informado pelo operador' : selected.effort_source === 'manager' ? 'Confirmado pela gestão' : 'Sem declaração de esforço'}</small></span></div>
        <p className={s.note}>Início, pausa, retomada e término descrevem a execução informada pelo operador. O esforço exibido foi declarado explicitamente; os intervalos do relógio não são convertidos em horas realizadas. Formulários, aprovações, prazos e reservas de recursos mantêm seus próprios controles.</p>
        {executionNeedsReview(selected) && <p className="notice error" role="alert">Este apontamento requer revisão. Confira a sequência, os horários capturados e o recebimento antes de confirmar sua situação.</p>}
        {executionNeedsReview(selected) && selected.confirmed_minutes !== null && <p className={s.note}>O esforço declarado permanece no histórico. Esse valor não compõe o agregado dos apontamentos enquanto aguarda revisão.</p>}
        {selected.clock_warning && <p className="notice" role="status">Há evidência de divergência de relógio. Os horários originais permanecem no histórico{selected.has_review ? ', mesmo após a reconciliação registrada pela gestão' : ''}.</p>}
        <details className={s.timeline} open><summary>Eventos recebidos · {detail.events.length} de {detail.events_total}</summary>{!detail.events_complete && <p className="notice" role="status">Exibindo os {detail.events.length} eventos mais recentes de {detail.events_total}. O início do histórico pode estar fora desta consulta; a situação acima vem da projeção completa do servidor.</p>}
          {detail.events.length ? <ol>{detail.events.map(event => <li key={event.id}><div className={s.eventHeading}><strong>{executionEventLabel[event.kind]}</strong><span className={`${s.badge} ${event.disposition === 'review' ? s.reviewState : s.unknown}`}>{event.disposition === 'review' ? 'Recebido para revisão' : 'Aceito no recebimento'}</span></div><p>{event.operator_name || 'Operador não identificado'} · aplicativo mobile</p><div className={s.eventTimes}><span>Capturado no aparelho<strong>{date(event.occurred_at, true)}</strong></span><span>Recebido no sistema<strong>{date(event.received_at, true)}</strong></span></div>{event.pause_reason && <p>Motivo da pausa: {executionPauseLabel[event.pause_reason] || event.pause_reason}</p>}{event.note && <p className={s.rawNote}>{event.note}</p>}{event.effort_minutes !== null && <p>Esforço informado: {minutesLabel(event.effort_minutes)}</p>}{event.disposition === 'review' && <p className={s.warning}>O evento foi preservado para revisão e não foi aplicado à situação aceita{event.review_reason ? ` · ${executionReviewReasonLabel[event.review_reason] || 'A evidência recebida precisa ser conferida com a equipe.'}` : ''}.</p>}</li>)}</ol> : <p className={s.empty}>Nenhum evento recebido neste apontamento.</p>}
        </details>
        <details className={s.timeline} open={detail.reviews.length > 0}><summary>Reconciliações da gestão · {detail.reviews.length} de {detail.reviews_total}</summary>{!detail.reviews_complete && <p className="notice">Exibindo as {detail.reviews.length} reconciliações mais recentes de {detail.reviews_total}. Os registros anteriores continuam preservados.</p>}{detail.reviews.length ? <ol>{detail.reviews.map(row => <li key={row.id}><div className={s.eventHeading}><strong>{row.action === 'confirm_finished' ? 'Término confirmado pela gestão' : 'Apontamento desconsiderado pela gestão'}</strong><span>{date(row.created_at, true)}</span></div><p>{row.actor_name || 'Gestão'} · motivo: {row.reason}</p>{row.reported_finished_at && <p>Término declarado: {date(row.reported_finished_at, true)}</p>}{row.effort_minutes !== null && <p>{minutesLabel(row.effort_minutes)}</p>}{row.note && <p className={s.rawNote}>{row.note}</p>}</li>)}</ol> : <p className={s.empty}>Nenhuma reconciliação registrada.</p>}</details>
        {canManage && !editing && <button type="button" className="button secondary" disabled={!editable} onClick={edit}>Reconciliar apontamento</button>}
        {!canManage && <p className={s.note}>Seu perfil permite consultar os apontamentos e as reconciliações recebidas.</p>}
        {editing && <section className={s.editor} ref={formRef} tabIndex={-1} aria-label="Reconciliação do apontamento"><div className={s.sectionHead}><div><h3>Registrar reconciliação</h3><p>O registro da gestão conserva os eventos originais e identifica quem confirmou a situação.</p></div><button type="button" className="button small secondary" disabled={locked} onClick={discard}>{dirty ? 'Descartar reconciliação' : 'Fechar reconciliação'}</button></div><form data-execution-local onSubmit={event => { event.preventDefault(); commit(); }}><fieldset disabled={!editable}><label>Ação<select aria-label="Ação da reconciliação" value={action} onChange={event => { setAction(event.target.value as typeof action); fieldChanged(); }}><option value="confirm_finished">Confirmar término informado</option><option value="void">Desconsiderar apontamento</option></select></label>
          {action === 'confirm_finished' && <div className={s.formGrid}><label>Término declarado · horário de São Paulo<input type="datetime-local" aria-label="Término declarado em São Paulo" min="1900-01-01T00:00" max="2200-12-31T23:59" value={finishedAt} onChange={event => { setFinishedAt(event.target.value); fieldChanged(); }} /></label><label>Esforço confirmado em minutos · opcional<input type="number" aria-label="Esforço confirmado em minutos" min={0} max={1_000_000} step={1} value={effort} onChange={event => { setEffort(event.target.value); fieldChanged(); }} placeholder="Deixe vazio se não foi confirmado" /></label></div>}
          <label>Observação · opcional<textarea aria-label="Observação da reconciliação" rows={2} maxLength={1000} value={note} onChange={event => { setNote(event.target.value); fieldChanged(); }} /></label><label>Motivo da reconciliação<textarea aria-label="Motivo da reconciliação" rows={2} minLength={3} maxLength={2000} value={reason} onChange={event => { setReason(event.target.value); fieldChanged(); }} placeholder="Registre o que foi conferido com a equipe." /></label></fieldset>
          {action === 'confirm_finished' && finishedAt && !reportedAt && <p className="notice error" role="alert">Informe um horário válido de São Paulo entre 1900 e 2200. Horários inexistentes ou repetidos na mudança de horário de verão precisam ser substituídos por outro minuto explícito.</p>}{effortMinutes === undefined && <p className="notice error" role="alert">Informe minutos inteiros entre 0 e 1.000.000 ou deixe o esforço vazio.</p>}
          <div className={s.actions}><button type="button" className="button secondary" disabled={!editable || !validFields || reason.trim().length < 3} onClick={review}>Revisar reconciliação</button></div>
          {(reviewing || save.uncertain) && <section className={s.review} ref={reviewRef} tabIndex={-1} aria-label="Revisão da reconciliação"><h3>Revisar antes de confirmar</h3><div className={s.compare}><div><h4>Situação recebida</h4><p>{executionStateLabel[selected.state]}</p><p>{minutesLabel(selected.confirmed_minutes)}</p></div><div><h4>Confirmação da gestão</h4><p>{action === 'confirm_finished' ? 'Término informado confirmado' : 'Apontamento desconsiderado'}</p>{action === 'confirm_finished' && <><p>{date(reportedAt, true)} · São Paulo</p><p>{minutesLabel(effortMinutes ?? null)}</p></>}</div></div><p className={s.note}>A confirmação acrescenta uma reconciliação ao histórico. Eventos originais, status do planejamento, aprovações, formulários e reservas de recursos permanecem preservados. Um evento offline recebido depois poderá exigir nova revisão.</p><p><strong>Motivo:</strong> {reason.trim()}</p>{note.trim() && <p className={s.rawNote}>{note.trim()}</p>}<div className={s.actions}><button className="button" type="submit" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!editable || !reviewing || !validFields || reason.trim().length < 3)}>{save.busy ? 'Confirmando reconciliação…' : save.uncertain ? 'Tentar confirmar reconciliação' : 'Confirmar reconciliação'}</button></div></section>}
        </form></section>}
      </div>
    </section>}
  </div>;
}
