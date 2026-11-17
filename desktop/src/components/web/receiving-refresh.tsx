'use client';

import { useCallback, useEffect, useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import styles from './receiving-refresh.module.css';

/** Refresh the authenticated server view without replacing its filters or browser position. */
export function ReceivingRefresh() {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [online, setOnline] = useState(true);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const [announcement, setAnnouncement] = useState('');
  const inFlight = useRef(false), manual = useRef(false), lastRequest = useRef(0);

  const refresh = useCallback((requested = false) => {
    if (inFlight.current || !navigator.onLine || document.visibilityState !== 'visible') return;
    // Focus, visibility and online can arrive together when returning to this tab.
    if (!requested && Date.now() - lastRequest.current < 1_000) return;
    inFlight.current = true; manual.current = requested; lastRequest.current = Date.now();
    if (requested) setAnnouncement('Atualizando recebimentos…');
    startTransition(() => router.refresh());
  }, [router]);

  useEffect(() => {
    if (pending || !inFlight.current) return;
    inFlight.current = false; setUpdatedAt(new Date());
    if (manual.current) setAnnouncement('Recebimentos atualizados.');
    manual.current = false;
  }, [pending]);

  useEffect(() => {
    setOnline(navigator.onLine);
    const connection = () => { setOnline(navigator.onLine); if (navigator.onLine) refresh(); };
    const resume = () => refresh();
    const timer = window.setInterval(resume, 5_000);
    window.addEventListener('online', connection); window.addEventListener('offline', connection);
    window.addEventListener('focus', resume); document.addEventListener('visibilitychange', resume);
    return () => {
      window.clearInterval(timer); window.removeEventListener('online', connection); window.removeEventListener('offline', connection);
      window.removeEventListener('focus', resume); document.removeEventListener('visibilitychange', resume);
    };
  }, [refresh]);

  return <div className={styles.refresh} data-receiving-refresh>
    <div className={styles.description}>
      <span>{online ? 'Atualização automática a cada 5 s enquanto esta aba estiver visível.' : 'Sem conexão. A consulta será atualizada quando a conexão retornar.'}</span>
      <small>{updatedAt ? <>Última consulta atualizada às <time dateTime={updatedAt.toISOString()}>{updatedAt.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo' })}</time>.</> : 'Consulta carregada. Aguardando atualização automática.'}</small>
    </div>
    <button type="button" className="button secondary" disabled={pending || !online} aria-busy={pending} onClick={() => refresh(true)}>{pending ? 'Atualizando…' : 'Atualizar agora'}</button>
    <span className={styles.srOnly} role="status" aria-live="polite">{announcement}</span>
  </div>;
}
