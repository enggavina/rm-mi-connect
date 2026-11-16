'use client';

import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react';
import { LoginProgress } from '@/components/web/login-progress';

export function SsoLoginForm({ error }: { error?: string }) {
  const [pending, setPending] = useState(false);
  const submitting = useRef(false);

  const cancel = useCallback(() => {
    if (!submitting.current) return;
    window.stop();
    submitting.current = false;
    setPending(false);
  }, []);

  useEffect(() => {
    // A native navigation can restore this document from the back/forward
    // cache without remounting React. Its old pending state is no longer valid.
    function ready(event: PageTransitionEvent) {
      if (!event.persisted) return;
      submitting.current = false;
      setPending(false);
    }
    function escape(event: KeyboardEvent) {
      if (event.key === 'Escape' && submitting.current) { event.preventDefault(); cancel(); }
    }
    window.addEventListener('pageshow', ready);
    window.addEventListener('keydown', escape);
    return () => { window.removeEventListener('pageshow', ready); window.removeEventListener('keydown', escape); };
  }, [cancel]);

  function submit(event: FormEvent<HTMLFormElement>) {
    if (submitting.current) { event.preventDefault(); return; }
    submitting.current = true;
    setPending(true);
    // Preserve native POST navigation, its first-party Origin and redirect
    // handling. Fetch/router navigation would change the SSO security contract.
  }

  return <>
    <form method="post" action="/auth/sso/start" className="login-form" onSubmit={submit} aria-busy={pending}>
      {error && !pending && <p className="notice error" role="alert">{error}</p>}
      <button type="submit" className="button" disabled={pending}>{pending ? 'Entrando…' : 'Entrar com Microsoft'}</button>
    </form>
    {pending && <LoginProgress label="Conectando à sua conta Microsoft…" onCancel={cancel} />}
  </>;
}
