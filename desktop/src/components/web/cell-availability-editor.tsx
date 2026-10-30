'use client';

import { useEffect, useRef, useState } from 'react';
import { manageCellAvailability } from '@/server/web/cell-availability-actions';
import type { ManageCellAvailabilityInput } from '@/server/web/cell-availability-policy';
import type { CellAvailabilitySnapshot } from '@/server/web/cell-availability-data';
import { cellAvailabilityAllowed, cellAvailabilityRequest, type CellAvailabilityMode } from './cell-availability-model';
import { EngineeringReloadLink, EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { projectRouteDestination } from './project-route-model';
import { priorityLabel } from './pcp-model';
import { Status } from './ui';
import s from './cell-availability.module.css';

export function CellAvailabilityEditor({ snapshot, canManage, destination, disabled = false, onInteractionChange }: {
  snapshot: CellAvailabilitySnapshot; canManage: boolean; destination: string; disabled?: boolean; onInteractionChange?: (active: boolean) => void;
}) {
  const [mode, setMode] = useState<CellAvailabilityMode | null>(null), [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false);
  const leaving = useRef(false), heading = useRef<HTMLHeadingElement>(null);
  const target = projectRouteDestination(destination, snapshot.project.id);
  const save = useEngineeringSave<ManageCellAvailabilityInput>(async input => {
    const result = await manageCellAvailability(input); if (result.ok) { leaving.current = true; setSaved(true); } return result;
  }, target);
  const locked = save.locked || saved, allocation = snapshot.allocation;
  const visibilityMode: CellAvailabilityMode = { action: 'set_visibility', visibilidade: !allocation.visibilidade };
  const canVisibility = cellAvailabilityAllowed(snapshot, visibilityMode, canManage), canRetire = cellAvailabilityAllowed(snapshot, { action: 'retire' }, canManage);
  const canRestore = cellAvailabilityAllowed(snapshot, { action: 'restore' }, canManage);
  useEffect(() => { onInteractionChange?.(mode !== null || locked); }, [mode, locked, onInteractionChange]);
  useEffect(() => { if (mode) heading.current?.focus(); }, [mode]);
  useEffect(() => {
    if (!confirmed && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && save.stale && !save.busy && !save.uncertain) {
        if (event.button === 0 && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) leaving.current = true;
        return;
      }
      if (!window.confirm(save.uncertain ? 'A alteração de disponibilidade ainda não foi confirmada. Sair desta tela?' : 'Há uma alteração de disponibilidade não salva. Sair sem salvar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [confirmed, save.busy, save.uncertain, save.stale]);
  function open(next: CellAvailabilityMode) {
    if (disabled || locked || mode || !cellAvailabilityAllowed(snapshot, next, canManage)) return;
    setMode(next); setConfirmed(false); save.setError('');
  }
  function cancel() { if (save.busy || save.uncertain) return; setMode(null); setConfirmed(false); save.setError(''); }
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (!mode || disabled || locked) return;
    try { void save.send(cellAvailabilityRequest(snapshot, mode, confirmed, crypto.randomUUID())); }
    catch (error) { save.setError(error instanceof Error ? error.message : 'Confira a alteração de disponibilidade.'); }
  }
  const actionLabel = mode?.action === 'retire' ? 'Confirmar retirada da célula' : mode?.action === 'restore' ? 'Confirmar restauração da célula'
    : mode?.action === 'set_visibility' && mode.visibilidade ? 'Confirmar disponibilidade no mobile' : 'Confirmar ocultação no mobile';
  return <section className={s.availability} data-cell-availability={allocation.id}>
    <div className={s.heading}><h3>Disponibilidade da célula</h3><Status value={allocation.retirada ? 'inativo' : allocation.visibilidade ? 'ativo' : 'pendente'} label={allocation.retirada ? 'Retirada do planejamento' : allocation.visibilidade ? 'Disponível no mobile' : 'Oculta no mobile'} /></div>
    <p className={s.note}>{allocation.retirada ? 'A alocação e seu histórico permanecem preservados para consulta. Restaure esta mesma alocação para voltar a planejar.' : 'Ocultar muda apenas a disponibilidade no mobile. Envios offline já iniciados continuam preservados, e a fila mantém a mesma ordem.'}</p>
    <dl className={s.summary}><div><dt>Fila de trabalhos abertos</dt><dd>{snapshot.in_queue ? 'Participa da fila, mesmo quando oculta' : allocation.retirada ? 'Fora da fila enquanto retirada' : 'Não integra o conjunto de trabalhos abertos'}</dd></div><div><dt>Posição preservada na fila</dt><dd>{allocation.posicao ?? 'Não definida'}</dd></div><div><dt>Índice preservado do roteiro</dt><dd>{allocation.indice ?? 'Não definido'}</dd></div><div><dt>Prioridade</dt><dd>{priorityLabel(allocation.prioridade)}</dd></div></dl>
    <EngineeringSaveNotice state={{ ...save, stale: false }} reload={target} />
    {save.stale && <p className="notice">A célula, o projeto ou suas condições de retirada mudaram. <EngineeringReloadLink href={target}>Recarregar disponibilidade da célula</EngineeringReloadLink> antes de tentar novamente.</p>}
    {save.busy && <p className="notice" role="status">Salvando disponibilidade da célula…</p>}{saved && <p className="notice success" role="status">Alteração confirmada. Atualizando a célula…</p>}
    {canManage && <div className={s.controls}>
      {!allocation.retirada ? <><button type="button" className="button small secondary" disabled={!canVisibility || disabled || locked || !!mode} onClick={() => open(visibilityMode)}>{allocation.visibilidade ? 'Ocultar no mobile' : 'Disponibilizar no mobile'}</button>
        <button type="button" className="button small secondary" disabled={!canRetire || disabled || locked || !!mode} onClick={() => open({ action: 'retire' })}>Retirar célula do planejamento</button></>
        : <button type="button" className="button small secondary" disabled={!canRestore || disabled || locked || !!mode} onClick={() => open({ action: 'restore' })}>Restaurar célula no planejamento</button>}
    </div>}
    {!allocation.retirada && snapshot.visibility_reason && <p className={s.note}>{snapshot.visibility_reason}</p>}
    {!allocation.retirada && snapshot.retire_reason && <p className={s.note}>{snapshot.retire_reason}</p>}
    {allocation.retirada && snapshot.restore_reason && <p className={s.note}>{snapshot.restore_reason}</p>}
    {mode && <form className={s.form} onSubmit={event => { event.preventDefault(); submit(); }}>
      <h4 tabIndex={-1} ref={heading}>{mode.action === 'retire' ? 'Retirar esta célula do planejamento' : mode.action === 'restore' ? 'Restaurar esta alocação' : mode.visibilidade ? 'Disponibilizar esta célula no mobile' : 'Ocultar esta célula no mobile'}</h4>
      <p>{mode.action === 'retire' ? 'A célula sairá do roteiro ativo, da fila e da carga planejada. Nenhuma alocação, modelo ou histórico será excluído. Um envio offline pendente poderá precisar da restauração desta mesma alocação ou de reconciliação.'
        : mode.action === 'restore' ? 'A alocação voltará com o mesmo identificador, posição, índice e prioridade, sem copiar novamente formulários, fotos ou regras. Ela começará oculta no mobile; disponibilize-a depois, quando necessário.'
          : mode.visibilidade ? 'Os operadores autorizados voltarão a encontrar este projeto nesta célula. As posições da fila e do roteiro e as prioridades permanecerão iguais.'
            : 'O projeto deixará de aparecer na seleção desta célula no mobile. Isso não cancela envios offline iniciados nem retira a alocação da fila de planejamento.'}</p>
      <fieldset className={s.fieldSet} disabled={locked}><label className="check-label"><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Conferi o efeito desta alteração e desejo confirmar.</label></fieldset>
      <div className={s.actions}><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={cancel}>Cancelar disponibilidade</button><button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && !confirmed}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : actionLabel}</button></div>
    </form>}
  </section>;
}
