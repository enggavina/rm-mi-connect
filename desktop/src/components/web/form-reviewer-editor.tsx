'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';
import { assignFormReviewer } from '@/server/web/form-reviewer-actions';
import type { AssignFormReviewerInput } from '@/server/web/form-reviewer-policy';
import type { FormReviewerAssignmentSnapshot } from '@/server/web/form-reviewer-data';
import { assignFormReviewerRequest, canManageFormReviewers, formReviewerAssignedLabel, formReviewerChange, formReviewerChoiceLabel, formReviewerHasDivergence } from './form-reviewer-model';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { projectRouteDestination } from './project-route-model';
import { Empty } from './ui';
import { Icon } from './icons';
import s from './form-reviewer.module.css';

export function FormReviewerEditor({ snapshot, canManage, destination, recordPanels }: {
  snapshot: FormReviewerAssignmentSnapshot; canManage: boolean; destination: string; recordPanels: Record<string, ReactNode>;
}) {
  const [formId, setFormId] = useState<string | null>(null), [reviewerId, setReviewerId] = useState('');
  const [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false);
  const initialReviewer = useRef(''), leaving = useRef(false);
  const target = projectRouteDestination(destination, snapshot.project.id);
  const save = useEngineeringSave<AssignFormReviewerInput>(async input => {
    const result = await assignFormReviewer(input);
    if (result.ok) { leaving.current = true; setSaved(true); }
    return result;
  }, target);
  const editable = canManageFormReviewers(snapshot, canManage), locked = save.locked || saved;
  const current = snapshot.forms.find(form => form.id === formId);
  const candidate = snapshot.eligible_users.find(user => user.id === reviewerId);
  const change = current ? formReviewerChange(current, reviewerId) : null;
  const dirty = formId !== null && (reviewerId !== initialReviewer.current || confirmed);
  useEffect(() => {
    if (!dirty && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]');
      if (!link || link.getAttribute('target') === '_blank') return;
      if (!window.confirm(save.uncertain ? 'A atribuição ainda não foi confirmada. Sair desta tela?' : 'Há uma atribuição de avaliador não salva. Sair sem salvar?')) {
        event.preventDefault(); event.stopPropagation();
      } else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [dirty, save.busy, save.uncertain]);
  function open(id: string) {
    const form = snapshot.forms.find(item => item.id === id);
    if (!editable || locked || formId || !form?.can_assign) return;
    initialReviewer.current = form.assignment?.eligible ? form.assignment.avaliador_user_id : '';
    setFormId(id); setReviewerId(initialReviewer.current); setConfirmed(false); save.setError('');
  }
  function cancel() {
    if (save.busy || save.uncertain) return;
    setFormId(null); setReviewerId(''); setConfirmed(false); save.setError('');
  }
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (!current || !editable || locked) return;
    try { void save.send(assignFormReviewerRequest(snapshot, current.id, reviewerId, confirmed, crypto.randomUUID())); }
    catch (error) { save.setError(error instanceof Error ? error.message : 'Confira o avaliador selecionado.'); }
  }
  const incomplete = !snapshot.complete || !snapshot.records_complete;
  const historicalPanels = Object.entries(recordPanels).filter(([id]) => !snapshot.forms.some(form => form.id === id));
  return <>
    <div className={s.notice}><EngineeringSaveNotice state={{ ...save, stale: false }} reload={target} />
      {save.stale && <div className="notice">O projeto, a célula, os registros ou os avaliadores elegíveis foram alterados. <a className="text-link" href={target} onClick={() => { leaving.current = true; }}>Recarregar formulários da célula</a> antes de atribuir novamente.</div>}
      {save.busy && <p className="notice" role="status">Salvando atribuição do avaliador…</p>}
      {saved && <p className="notice success" role="status">Avaliador confirmado. Atualizando os formulários…</p>}
      {incomplete && <p className="notice" role="status">O conjunto de formulários ou registros excede o limite desta tela. A atribuição está bloqueada; os registros existentes continuam disponíveis para consulta.</p>}
      {canManage && !snapshot.eligible_complete && <p className="notice" role="status">A lista de avaliadores desta célula excede o limite desta tela. A atribuição está bloqueada até que o conjunto completo esteja disponível.</p>}
      {(snapshot.project.closed || ['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '')) && <p className="notice">O projeto ou a célula está encerrado. As atribuições e os registros permanecem disponíveis para consulta.</p>}
    </div>
    {snapshot.forms.map(form => {
      const title = form.titulo || 'Formulário não disponível';
      const active = current?.id === form.id;
      const divergence = formReviewerHasDivergence(form);
      const assignedLabel = formReviewerAssignedLabel(form, snapshot.eligible_users);
      const hasAssignmentsInRecords = form.records.some(record => record.avaliador_user_id !== null);
      const buttonLabel = form.assignment ? divergence ? 'Trocar ou reaplicar avaliador' : 'Trocar avaliador' : 'Definir avaliador';
      const submitLabel = change?.reapply ? 'Reaplicar avaliador' : form.assignment || (change?.requiresConfirmation && hasAssignmentsInRecords) ? 'Confirmar troca de avaliador' : 'Definir avaliador';
      return <article className={s.item} key={form.id} data-form-reviewer={form.id}>
        <div className={s.heading}><div><h3>{title}</h3>{!form.linked && <p className="form-note">Registro ou atribuição histórica de formulário que não está no vínculo atual.</p>}</div>
          {editable && form.can_assign && <button type="button" className="button small secondary" aria-label={`${buttonLabel} de ${title}`} disabled={locked || formId !== null} onClick={() => open(form.id)}><Icon name="edit" size={14} />{buttonLabel}</button>}
        </div>
        <div className={s.assignment}><p><strong>Avaliador atribuído:</strong> {assignedLabel ?? 'Ainda não definido'}</p>
          {form.assignment && !form.assignment.eligible && <p className="notice">O avaliador atribuído não está entre os elegíveis atuais da célula. Novos envios não herdarão essa atribuição enquanto ele não estiver ativo e vinculado à célula; os registros existentes permanecem preservados.</p>}
          {divergence && <p className="form-note">Os avaliadores dos registros existentes divergem da atribuição atual ou entre si. As informações dos registros permanecem identificadas abaixo.</p>}
          {!form.assignment && hasAssignmentsInRecords && <p className="form-note">Os avaliadores dos registros existentes não definem automaticamente o avaliador dos próximos envios.</p>}
          {form.action_reason && <p className="form-note">{form.action_reason}</p>}
        </div>
        {active && current && <form className={s.form} onSubmit={event => { event.preventDefault(); submit(); }}>
          <h4>{change?.reapply ? 'Reaplicar avaliador aos registros' : form.assignment ? 'Trocar avaliador atribuído' : 'Definir avaliador atribuído'}</h4>
          <fieldset className={s.fieldSet} disabled={locked}>
            <div className="field"><label htmlFor={`reviewer-${form.id}`}>Avaliador elegível para {title}</label>
              <select id={`reviewer-${form.id}`} value={reviewerId} onChange={event => { setReviewerId(event.target.value); setConfirmed(false); }}>
                <option value="">Selecione um avaliador</option>{snapshot.eligible_users.map(user => <option key={user.id} value={user.id}>{formReviewerChoiceLabel(user, snapshot.eligible_users)}</option>)}
              </select>
            </div>
            {!snapshot.eligible_users.length && <p className="notice">Nenhuma identidade ativa está vinculada a esta célula para receber a atribuição.</p>}
            <p>{form.records.length ? `A atribuição será aplicada aos ${form.records.length} registros existentes e aos próximos envios deste formulário nesta célula.` : 'A atribuição será aplicada aos próximos envios deste formulário nesta célula.'}</p>
            {candidate && change && <>
              <p className={s.transition}><strong>{assignedLabel ?? 'Sem atribuição prévia'}</strong><span aria-hidden="true"> → </span><strong>{formReviewerChoiceLabel(candidate, snapshot.eligible_users)}</strong></p>
              {change.differentRecords > 0 && <p>{change.differentRecords} registros serão atualizados para o avaliador selecionado{change.unassignedRecords ? `; ${change.unassignedRecords} estão sem avaliador` : ''}.</p>}
              {!change.needsChange && <p className="form-note">Este avaliador já está aplicado aos registros e aos próximos envios.</p>}
              {change.needsChange && change.requiresConfirmation && <label className="check-label"><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Confirmo a troca ou reaplicação do avaliador nos registros existentes e nos próximos envios.</label>}
            </>}
          </fieldset>
          <div className={s.actions}><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={cancel}>Cancelar atribuição</button>
            <button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || (!save.uncertain && (!candidate || !change?.needsChange || change.requiresConfirmation && !confirmed))}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : submitLabel}</button>
          </div>
        </form>}
        <div className={s.records}>{recordPanels[form.id] ?? <p className="form-note">Aguardando preenchimento pela equipe.</p>}</div>
      </article>;
    })}
    {!snapshot.forms.length && !incomplete && <Empty title="Nenhum formulário vinculado" detail="O planejamento pode vincular os formulários publicados para esta célula." icon="clipboard" />}
    {historicalPanels.map(([id, panel]) => <article className={s.item} key={id} data-form-reviewer-history={id}><h3>Registros existentes do formulário</h3><div className={s.records}>{panel}</div></article>)}
  </>;
}
