'use client';

import { useEffect, useRef, useState } from 'react';
import { saveCellQueue } from '@/server/web/pcp-actions';
import type { PcpCellQueue } from '@/server/web/pcp-data';
import { catalogFailureState } from './catalog-model';
import { estimatedHours, freezeCellQueueRequest, moveQueueItem, planningPriorities, planningPriorityLabels, priorityLabel, queueOrderChanged, queuePrioritiesChanged, type CellQueueRequest, type PlanningPriority } from './pcp-model';
import { Empty, Status, date } from './ui';
import { Icon } from './icons';
import s from './pcp.module.css';

function QueuePosition({ index, total, label, disabled, move }: { index: number; total: number; label: string; disabled: boolean; move: (target: number) => void }) {
  const [target, setTarget] = useState(String(index + 1));
  useEffect(() => setTarget(String(index + 1)), [index]);
  const go = () => { const value = Number(target); if (Number.isInteger(value) && value >= 1 && value <= total) move(value - 1); else setTarget(String(index + 1)); };
  return <div className={s.controls}>
    <button className="button small secondary" type="button" disabled={disabled || index === 0} aria-label={`Mover ${label} para cima`} onClick={() => move(index - 1)}><Icon name="chevron" size={12} style={{ transform: 'rotate(-90deg)' }} />Subir</button>
    <button className="button small secondary" type="button" disabled={disabled || index === total - 1} aria-label={`Mover ${label} para baixo`} onClick={() => move(index + 1)}><Icon name="chevron" size={12} style={{ transform: 'rotate(90deg)' }} />Descer</button>
    <input className={s.positionInput} type="number" min={1} max={total} value={target} disabled={disabled} aria-label={`Posição de ${label}`} onChange={event => setTarget(event.target.value)} onKeyDown={event => { if (event.key === 'Enter') { event.preventDefault(); go(); } }} />
    <button className="button small secondary" type="button" disabled={disabled} aria-label={`Mover ${label} para a posição informada`} onClick={go}>Ir</button>
  </div>;
}

export function CellQueueEditor({ snapshot, canEdit, canProjects }: { snapshot: PcpCellQueue; canEdit: boolean; canProjects: boolean }) {
  const original = snapshot.items;
  const [items, setItems] = useState(original), [normalize, setNormalize] = useState(false), [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false), [uncertain, setUncertain] = useState(false), [stale, setStale] = useState(false), [unauthorized, setUnauthorized] = useState(false), [success, setSuccess] = useState(false), [error, setError] = useState('');
  const attempt = useRef<CellQueueRequest | null>(null), inFlight = useRef(false), leaving = useRef(false), alert = useRef<HTMLDivElement>(null);
  const reordered = queueOrderChanged(items, original), applyOrder = normalize || reordered;
  const changed = applyOrder || queuePrioritiesChanged(items, original);
  const locked = busy || uncertain || stale || unauthorized || success;
  useEffect(() => { if (error) alert.current?.focus(); }, [error]);
  useEffect(() => {
    if (!changed && !busy && !uncertain) return;
    const protect = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', protect); return () => window.removeEventListener('beforeunload', protect);
  }, [changed, busy, uncertain]);
  function move(id: string, target: number) { setItems(current => moveQueueItem(current, id, target)); setConfirmed(false); setError(''); }
  function priority(id: string, value: string) { setItems(current => current.map(item => item.id === id ? { ...item, prioridade: (value || null) as PlanningPriority | null } : item)); setConfirmed(false); setError(''); }
  function reset() { setItems(original); setNormalize(false); setConfirmed(false); setError(''); }
  async function submit() {
    if (inFlight.current || stale || unauthorized || success || !canEdit || !snapshot.complete) return;
    if (!attempt.current) {
      if (!changed || !confirmed) { setError('Confira as alterações e confirme a fila antes de salvar.'); return; }
      attempt.current = freezeCellQueueRequest({ submissionId: crypto.randomUUID(), celula_id: snapshot.cell.id,
        expected_queue_version: snapshot.queue_version, apply_order: applyOrder,
        items: items.map(item => ({ id: item.id, expected_updated_at: item.updated_at, prioridade: item.prioridade })) });
    }
    inFlight.current = true; setBusy(true); setError('');
    try {
      const result = await saveCellQueue(attempt.current);
      if (result.ok) { attempt.current = null; leaving.current = true; setSuccess(true); setUncertain(false); window.location.reload(); }
      else {
        const failure = catalogFailureState(result); setError(result.error); setUncertain(failure.uncertain); setStale(failure.stale); setUnauthorized(failure.unauthorized);
        if (!failure.uncertain) attempt.current = null;
      }
    } catch { setUncertain(true); setError('A conexão foi interrompida. Tente confirmar novamente para consultar o resultado do mesmo envio.'); }
    finally { inFlight.current = false; setBusy(false); }
  }
  if (!snapshot.complete) return <Empty title="Esta fila excede o limite de edição" detail="A fila completa precisa ser conferida antes de alterar a ordem. Consulte as alocações no planejamento; nenhum conjunto parcial será salvo." icon="board"><a className="button secondary" href={`/planejamento?cell=${snapshot.cell.id}`}>Consultar alocações</a></Empty>;
  if (!items.length) return <Empty title="Nenhum trabalho aberto nesta célula" detail="As alocações abertas de projetos ativos aparecerão aqui, incluindo as que ainda estão ocultas no mobile." icon="board" />;
  return <form onSubmit={event => { event.preventDefault(); void submit(); }}>
    {canEdit && <div className={s.normalization}><p className={s.note}>A prioridade classifica o trabalho. Use os controles de posição para mudar a sequência da célula.</p><button className="button small secondary" type="button" disabled={locked || normalize} onClick={() => { setNormalize(true); setConfirmed(false); }}>{normalize ? 'Sequência selecionada' : 'Confirmar sequência exibida'}</button></div>}
    <div className={s.queue}>{items.map((item, index) => {
      const label = item.numero_projeto ? `OS ${item.numero_projeto}` : `Projeto sem OS, posição ${index + 1}`;
      return <article key={item.id} className={s.item} data-queue-item={item.id}>
        <span className={s.position} aria-label={`Posição ${index + 1}`}>{index + 1}</span>
        <div>{canProjects ? <a href={`/projetos/${item.projeto_id}?tab=planejamento`} className={s.title}>{label}</a> : <span className={s.title}>{label}</span>}<p className={s.description}>{item.cliente_nome_export || 'Cliente não informado'}{item.tipo_equipamento_nome_export ? ` · ${item.tipo_equipamento_nome_export}` : ''}</p><div className={s.meta}><Status value={item.status} /><Status value={item.visibilidade ? 'ativo' : 'pendente'} label={item.visibilidade ? 'Visível no mobile' : 'Oculta no mobile'} />{item.bloqueada === 'sim' && <Status value="inativo" label="Bloqueada" />}</div><p className={s.description}>Prazo: {date(item.data_limite)} · {item.responsavel_nome || 'Responsável não definido'} · {estimatedHours(item.horas_previstas == null ? null : Number(item.horas_previstas))}</p>{item.bloqueada === 'sim' && item.motivo_bloqueio && <p className={s.description}>{item.motivo_bloqueio}</p>}</div>
        <div className={s.priority}>{canEdit ? <><label htmlFor={`queue-priority-${item.id}`}>Prioridade</label><select id={`queue-priority-${item.id}`} aria-label={`Prioridade de ${label}`} value={item.prioridade || ''} disabled={locked} onChange={event => priority(item.id, event.target.value)}><option value="">Sem prioridade</option>{planningPriorities.map(value => <option key={value} value={value}>{planningPriorityLabels[value]}</option>)}</select></> : <span className={s.note}>{priorityLabel(item.prioridade)}</span>}</div>
        {canEdit && <QueuePosition index={index} total={items.length} label={label} disabled={locked} move={target => move(item.id, target)} />}
      </article>;
    })}</div>
    {canEdit && <div className={s.saveBar}>
      {error && <div role="alert" tabIndex={-1} ref={alert} className="notice error">{error}</div>}
      {uncertain && <div className="notice">As prioridades, a sequência e o protocolo deste envio estão protegidos. Confirme o mesmo envio para verificar seu resultado.</div>}
      {stale && <div className="notice">A fila mudou desde que a tela foi aberta. Atualize os dados para conferir os trabalhos antes de planejar novamente.</div>}
      {unauthorized && <div className="notice">Seu acesso precisa ser confirmado novamente. <a className="text-link" href="/login">Voltar ao acesso</a></div>}
      {success && <div role="status" className="notice success">Planejamento salvo. Atualizando a fila…</div>}
      <p className={s.note}>{applyOrder ? 'Ao salvar, a sequência exibida será definida como a ordem dos trabalhos desta célula. As prioridades também serão salvas.' : 'Ao salvar, somente as prioridades alteradas serão atualizadas. A ordem atual será preservada.'}</p>
      {changed && <label className="check-label"><input type="checkbox" checked={confirmed} disabled={locked} onChange={event => setConfirmed(event.target.checked)} />Conferi a fila completa e desejo salvar {applyOrder ? 'as prioridades e esta sequência' : 'as prioridades, preservando a ordem'}.</label>}
      <div className={s.actions}>{changed && !locked && <button className="button secondary" type="button" onClick={reset}>Descartar alterações</button>}{stale ? <button className="button secondary" type="button" onClick={() => { leaving.current = true; window.location.reload(); }}><Icon name="refresh" size={15} />Atualizar fila</button> : !unauthorized && <button className="button" type="submit" disabled={busy || success || (!uncertain && (!changed || !confirmed))}>{busy ? 'Salvando…' : uncertain ? 'Tentar confirmar o mesmo envio' : 'Salvar prioridades e ordem'}</button>}</div>
    </div>}
  </form>;
}
