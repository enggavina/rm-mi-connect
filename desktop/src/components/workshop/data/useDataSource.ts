import { useCallback, useEffect, useRef, useState } from 'react';
import { snapshotSchema } from '../domain/schema';
import type { WorkshopSnapshot } from '../domain/types';

/** The portal session and its current capabilities protect this same-origin API. */
export function useDataSource() {
  const [snapshot, setSnapshot] = useState<WorkshopSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null), [loading, setLoading] = useState(true);
  const controller = useRef<AbortController | null>(null);
  const refresh = useCallback(async () => {
    controller.current?.abort();
    const abort = new AbortController(); controller.current = abort;
    setLoading(true);
    const timeout = window.setTimeout(() => abort.abort('timeout'), 60_000);
    try {
      const response = await fetch('/api/web/workshop', { signal: abort.signal, credentials: 'same-origin', headers: { Accept: 'application/json' }, cache: 'no-store' });
      if (!response.ok) {
        if (response.status === 401) throw new Error('Sua sessão expirou. Entre novamente no EM para consultar a oficina.');
        if (response.status === 403) throw new Error('Seu acesso não permite consultar os projetos e o planejamento da oficina.');
        throw new Error('Não foi possível atualizar os dados da oficina. Tente novamente.');
      }
      const data = snapshotSchema.parse(await response.json());
      if (controller.current === abort) { setSnapshot(data); setError(null); }
    } catch (failure) {
      if (controller.current !== abort || abort.signal.aborted && abort.signal.reason !== 'timeout') return;
      setSnapshot(null);
      setError(abort.signal.reason === 'timeout' ? 'A consulta excedeu o tempo limite. Os dados não foram atualizados.' : failure instanceof Error && !('issues' in failure) ? failure.message : 'A leitura recebida não atende ao contrato da oficina. Atualize novamente.');
    } finally { clearTimeout(timeout); if (controller.current === abort) setLoading(false); }
  }, []);
  useEffect(() => {
    void refresh();
    const interval = window.setInterval(() => { if (!document.hidden) void refresh(); }, 120_000);
    return () => { controller.current?.abort(); clearInterval(interval); };
  }, [refresh]);
  return { source: 'supabase' as const, snapshot, loading, error, refresh };
}
