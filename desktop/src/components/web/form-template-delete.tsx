'use client';
import { useState } from 'react';
import { TemplateSaveNotice, useTemplateSave } from './form-template-save';

/** A shared frozen-attempt hook handles uncertainty, stale data and fresh auth. */
export function FormTemplateDelete({ id, kind, title, version, state }: {
  id: string; kind: 'draft' | 'form'; title: string; version: string; state?: ReturnType<typeof useTemplateSave>;
}) {
  const ownState = useTemplateSave(), save = state ?? ownState;
  const [confirming, setConfirming] = useState(false), [confirmed, setConfirmed] = useState(false);
  return <section style={{ marginTop: 24 }} aria-label="Excluir modelo">
    {!state && <TemplateSaveNotice state={save} reload={kind === 'draft' ? `/modelos-formularios/${id}` : `/modelos-formularios/publicados/${id}`} />}
    {!confirming ? <button type="button" className="button secondary" disabled={save.locked} onClick={() => setConfirming(true)}>Excluir modelo</button> :
      <div className="notice"><strong>Excluir “{title || 'Modelo sem título'}”?</strong>
        <p>Esta ação remove o modelo e suas definições exclusivas. Vínculos, respostas e histórico de uso impedem a exclusão. Alterações ainda não salvas neste rascunho serão descartadas.</p>
        <label className="check-label"><input type="checkbox" checked={confirmed} disabled={save.locked} onChange={event => setConfirmed(event.target.checked)} />Confirmo a exclusão deste modelo.</label>
        <div className="form-actions"><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={() => { setConfirming(false); setConfirmed(false); }}>Manter modelo</button>
          <button type="button" className="button" disabled={save.locked || !confirmed} onClick={() => void save.send({ action: 'delete', payload: { submissionId: crypto.randomUUID(), id, kind, expected_updated_at: version, confirmed: true } })}>{save.busy ? 'Excluindo…' : 'Confirmar exclusão'}</button></div>
      </div>}
  </section>;
}
