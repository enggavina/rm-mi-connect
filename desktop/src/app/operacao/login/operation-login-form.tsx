'use client';

import { useEffect, useRef, useState, type FormEvent } from 'react';
import { LoginProgress } from '@/components/web/login-progress';
import styles from '../operation.module.css';

export function OperationLoginForm({ error }: { error?: string }) {
  const [pending, setPending] = useState(false);
  const submitting = useRef(false);

  useEffect(() => {
    function restore(event: PageTransitionEvent) {
      if (!event.persisted) return;
      submitting.current = false;
      setPending(false);
    }
    window.addEventListener('pageshow', restore);
    return () => window.removeEventListener('pageshow', restore);
  }, []);

  function submit(event: FormEvent<HTMLFormElement>) {
    if (submitting.current) { event.preventDefault(); return; }
    submitting.current = true;
    setPending(true);
  }

  return <>
    <form method="post" action="/operacao/login/entrar" className="login-form" onSubmit={submit} aria-busy={pending}>
      {error && <p className="notice error" role="alert">{error}</p>}
      <fieldset className={styles.formGroup}>
        <legend>Conta do dispositivo</legend>
        <label className="field" htmlFor="em-operacao-email">E-mail
          <input id="em-operacao-email" name="email" type="email" autoComplete="username" required maxLength={254} />
        </label>
        <label className="field" htmlFor="em-operacao-senha">Senha
          <input id="em-operacao-senha" name="password" type="password" autoComplete="current-password" required maxLength={1024} />
        </label>
      </fieldset>
      <fieldset className={styles.formGroup}>
        <legend>Identificação do operador</legend>
        <label className="field" htmlFor="em-operacao-matricula">Matrícula
          <input id="em-operacao-matricula" name="matricula" autoCapitalize="none" autoComplete="off" spellCheck={false} required maxLength={80} />
        </label>
        <label className="field" htmlFor="em-operacao-palavra">Palavra-chave
          <input id="em-operacao-palavra" name="palavra_chave" type="password" autoComplete="off" required maxLength={256} />
        </label>
      </fieldset>
      <button type="submit" className={`button ${styles.loginSubmit}`} disabled={pending}>{pending ? 'Entrando…' : 'Entrar na operação'}</button>
    </form>
    {pending && <LoginProgress />}
  </>;
}
