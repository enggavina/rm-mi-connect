'use client';
import { useEffect, useRef, useState } from 'react';
import { createFormTemplate, saveFormTemplate, publishFormTemplate } from '@/server/web/form-template-actions';
import type { TemplateContent } from './form-template-model';
import { catalogFailureState } from './catalog-model';
import { freezeEngineeringRequest } from './engineering-model';

export type TemplateAttempt = { action: 'create'; payload: { submissionId: string; id: string; source_form_id: string | null; kind: 'new' | 'copy' | 'version' } }
  | { action: 'save'; payload: { submissionId: string; id: string; expected_updated_at: string; content: TemplateContent } }
  | { action: 'publish'; payload: { submissionId: string; id: string; expected_updated_at: string } };
export function useTemplateSave() {
  const [busy, setBusy] = useState(false), [uncertain, setUncertain] = useState(false), [stale, setStale] = useState(false), [unauthorized, setUnauthorized] = useState(false), [error, setError] = useState('');
  const attempt = useRef<TemplateAttempt | null>(null), inFlight = useRef(false), navigationAllowed = useRef(false);
  useEffect(() => { if (!busy && !uncertain) return; const guard = (event: BeforeUnloadEvent) => { if (attempt.current) { event.preventDefault(); event.returnValue = ''; } }; window.addEventListener('beforeunload', guard); return () => window.removeEventListener('beforeunload', guard); }, [busy, uncertain]);
  async function send(value: TemplateAttempt) {
    if (inFlight.current || stale || unauthorized || (attempt.current && attempt.current.action !== value.action)) return;
    inFlight.current = true; setBusy(true); setError(''); attempt.current ??= freezeEngineeringRequest(value);
    try {
      const current = attempt.current;
      const result = await (current.action === 'create' ? createFormTemplate(current.payload) : current.action === 'save' ? saveFormTemplate(current.payload) : publishFormTemplate(current.payload));
      if (result.ok) { attempt.current = null; navigationAllowed.current = true; setUncertain(false); setBusy(false); setTimeout(() => window.location.assign(`/modelos-formularios/${current.payload.id}?resultado=${current.action === 'publish' ? 'publicado' : current.action === 'save' ? 'salvo' : 'criado'}`), 0); }
      else { const state = catalogFailureState(result); setError(result.error); setUncertain(state.uncertain); setStale(state.stale); setUnauthorized(state.unauthorized); if (!state.uncertain) attempt.current = null; }
    } catch { setUncertain(true); setError('Não foi possível confirmar o envio. Tente novamente com os mesmos dados para evitar duplicação.'); }
    finally { inFlight.current = false; setBusy(false); }
  }
  return { busy, uncertain, stale, unauthorized, error, setError, send, navigationAllowed, locked: busy || uncertain || stale || unauthorized, retry: () => { if (attempt.current) void send(attempt.current); } };
}
export function TemplateSaveNotice({ state, reload }: { state: ReturnType<typeof useTemplateSave>; reload: string }) {
  const alert = useRef<HTMLDivElement>(null); useEffect(() => { if (state.error) alert.current?.focus(); }, [state.error]);
  return <>{state.error && <div role="alert" tabIndex={-1} ref={alert} className="notice error">{state.error}</div>}{state.uncertain && <div className="notice">O envio está protegido. Confirme o mesmo envio antes de salvar ou publicar outra alteração.<p><button type="button" className="button secondary" disabled={state.busy} onClick={state.retry}>Tentar confirmar envio</button></p></div>}{state.stale && <div className="notice">O modelo foi alterado em outra sessão. <a href={reload} className="text-link">Recarregar modelo</a> antes de continuar.</div>}{state.unauthorized && <div className="notice">Seu acesso precisa ser confirmado novamente. <a href="/login" className="text-link">Voltar ao acesso</a></div>}</>;
}
