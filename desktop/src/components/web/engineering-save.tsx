'use client';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { WebActionResult } from '@/server/web/actions';
import { catalogFailureState } from './catalog-model';
import { freezeEngineeringRequest } from './engineering-model';
import { handleEngineeringReload, navigateAfterEngineeringSave } from './engineering-save-navigation';

export function useEngineeringSave<T>(action: (input: T) => Promise<WebActionResult>, destination: string | ((input: T) => string)) {
  const [busy, setBusy] = useState(false), [uncertain, setUncertain] = useState(false), [stale, setStale] = useState(false), [unauthorized, setUnauthorized] = useState(false), [error, setError] = useState('');
  const attempt = useRef<T | null>(null), inFlight = useRef(false);
  useEffect(() => {
    if (!busy && !uncertain) return;
    const protect = (event: BeforeUnloadEvent) => { if (attempt.current) { event.preventDefault(); event.returnValue = ''; } };
    window.addEventListener('beforeunload', protect); return () => window.removeEventListener('beforeunload', protect);
  }, [busy, uncertain]);
  async function send(payload: T) {
    if (inFlight.current || stale || unauthorized) return;
    inFlight.current = true; setBusy(true); setError(''); attempt.current ??= freezeEngineeringRequest(payload);
    try {
      const result = await action(attempt.current);
      if (result.ok) { const target = typeof destination === 'function' ? destination(attempt.current ?? payload) : destination; attempt.current = null; setUncertain(false); setBusy(false); setTimeout(() => navigateAfterEngineeringSave(target), 0); }
      else { const state = catalogFailureState(result); setError(result.error); setUncertain(state.uncertain); setStale(state.stale); setUnauthorized(state.unauthorized); if (!state.uncertain) attempt.current = null; }
    } catch { setUncertain(true); setError('A conexão foi interrompida. Tente confirmar o envio novamente; os mesmos dados serão usados para evitar duplicação.'); }
    finally { inFlight.current = false; setBusy(false); }
  }
  return { busy, uncertain, stale, unauthorized, error, setError, locked: busy || uncertain || stale || unauthorized, send, retry: () => { if (attempt.current) void send(attempt.current); } };
}
export function EngineeringReloadLink({ href, children }: { href: string; children: ReactNode }) {
  return <a className="text-link" href={href} data-engineering-reload onClick={event => handleEngineeringReload(event, href)}>{children}</a>;
}
export function EngineeringSaveNotice({ state, reload }: { state: Pick<ReturnType<typeof useEngineeringSave>, 'error' | 'uncertain' | 'stale' | 'unauthorized'>; reload: string }) {
  const alert = useRef<HTMLDivElement>(null);
  useEffect(() => { if (state.error) alert.current?.focus(); }, [state.error]);
  return <>{state.error && <div tabIndex={-1} ref={alert} role="alert" className="notice error">{state.error}</div>}
    {state.uncertain && <div className="notice">Os dados deste envio permanecem protegidos até a confirmação. Use “Tentar confirmar envio” antes de iniciar outra alteração.</div>}
    {state.stale && <div className="notice">O roteiro ou cadastro mudou desde que a página foi aberta. <EngineeringReloadLink href={reload}>Recarregar dados</EngineeringReloadLink> antes de editar novamente.</div>}
    {state.unauthorized && <div className="notice">Seu acesso precisa ser confirmado novamente. <a className="text-link" href="/login">Voltar ao acesso</a></div>}</>;
}
