'use client';

import { useEffect, useRef, useState } from 'react';
import { transitionStageApproval } from '@/server/web/stage-approval-actions';
import { catalogFailureState } from './catalog-model';
import { Icon } from './icons';
import { freezeStageApprovalRequest, stageActionDescriptions, stageActionLabels, visibleStageActions, type StageAction, type StageApprovalRequest } from './stage-approval-model';
import s from './stage-approval.module.css';

export function StageApprovalDecision({ stageId, stageVersion, cellVersion, triggerStatus, actions }: {
  stageId: string; stageVersion: string; cellVersion: string; triggerStatus: string | null; actions: StageAction[];
}) {
  const [selected, setSelected] = useState<StageAction | ''>(''), [note, setNote] = useState(''), [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false), [uncertain, setUncertain] = useState(false), [stale, setStale] = useState(false), [unauthorized, setUnauthorized] = useState(false), [success, setSuccess] = useState(false), [error, setError] = useState('');
  const inFlight = useRef(false), attempt = useRef<Readonly<StageApprovalRequest> | null>(null), alert = useRef<HTMLDivElement>(null);
  const available = visibleStageActions(triggerStatus, actions);
  const locked = busy || uncertain || stale || unauthorized || success;
  useEffect(() => { if (error) alert.current?.focus(); }, [error]);
  useEffect(() => {
    if (!busy && !uncertain) return;
    const protect = (event: BeforeUnloadEvent) => { if (attempt.current) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', protect); return () => window.removeEventListener('beforeunload', protect);
  }, [busy, uncertain]);
  async function submit() {
    if (inFlight.current || stale || unauthorized || success) return;
    if (!attempt.current) {
      if (!selected || !available.includes(selected) || !confirmed) { setError('Escolha uma decisão e confirme que conferiu as informações da etapa.'); return; }
      if (selected === 'retornar' && !note.trim()) { setError('Informe o motivo do retorno antes de confirmar.'); return; }
      attempt.current = freezeStageApprovalRequest({ submissionId: crypto.randomUUID(), aprovacao_etapa_id: stageId,
        expected_updated_at: stageVersion, expected_cell_updated_at: cellVersion, acao: selected, observacao: note.trim() });
    }
    inFlight.current = true; setBusy(true); setError('');
    try {
      const result = await transitionStageApproval(attempt.current);
      if (result.ok) {
        attempt.current = null; setUncertain(false); setSuccess(true); window.location.reload();
      } else {
        const failure = catalogFailureState(result); setError(result.error); setUncertain(failure.uncertain); setStale(failure.stale); setUnauthorized(failure.unauthorized);
        if (!failure.uncertain) attempt.current = null;
      }
    } catch { setUncertain(true); setError('A conexão foi interrompida. Tente confirmar novamente para verificar o resultado do mesmo envio.'); }
    finally { inFlight.current = false; setBusy(false); }
  }
  if (!available.length) return null;
  return <section className="panel"><div className="panel-content"><form className={s.decision} onSubmit={event => { event.preventDefault(); void submit(); }}>
    <h2>Decidir esta etapa</h2><p className="form-note">Confira o estado da célula e os registros do projeto antes de confirmar. A decisão será registrada em seu nome.</p>
    {error && <div tabIndex={-1} ref={alert} role="alert" className="notice error">{error}</div>}
    {uncertain && <div className="notice">A decisão, a observação e a identificação deste envio estão protegidas. Use “Tentar confirmar o mesmo envio” para consultar o resultado sem duplicar a decisão.</div>}
    {stale && <div className="notice">A etapa ou a célula mudou desde que esta página foi aberta. Atualize os dados para conferir a situação antes de decidir novamente.</div>}
    {unauthorized && <div className="notice">Seu acesso precisa ser confirmado novamente. <a href="/login" className="text-link">Voltar ao acesso</a></div>}
    {success && <div role="status" className="notice success">Decisão registrada. Atualizando a etapa…</div>}
    <fieldset className={s.fieldset} disabled={locked}><legend className="field-label">Decisão</legend><div className={s.choices}>{available.map(action => <label className={s.choice} key={action}><input type="radio" name="stage-decision" value={action} checked={selected === action} onChange={() => { setSelected(action); setConfirmed(false); setError(''); }} />{stageActionLabels[action]}</label>)}</div>
      {selected && <div className={s.effect}>{stageActionDescriptions[selected]}</div>}
      <div className="field"><label htmlFor="stage-observation">{selected === 'retornar' ? 'Motivo do retorno (obrigatório)' : 'Observação (opcional)'}</label><textarea id="stage-observation" value={note} maxLength={10000} required={selected === 'retornar'} onChange={event => setNote(event.target.value)} placeholder="Registre o contexto da sua decisão…" /></div>
      {selected && <label className={`check-label ${s.confirm}`}><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Conferi as informações desta etapa e desejo {stageActionLabels[selected].toLocaleLowerCase('pt-BR')}.</label>}
    </fieldset>
    <div className="form-actions">{stale ? <button className="button secondary" type="button" onClick={() => window.location.reload()}><Icon name="refresh" size={15} />Atualizar etapa</button> : !unauthorized && <button className="button" type="submit" disabled={busy || success || (!uncertain && (!selected || !confirmed))}>{busy ? 'Confirmando…' : uncertain ? 'Tentar confirmar o mesmo envio' : selected ? `Confirmar: ${stageActionLabels[selected]}` : 'Confirmar decisão'}</button>}</div>
  </form></div></section>;
}
