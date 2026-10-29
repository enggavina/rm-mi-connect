'use client';
import { useActionState } from 'react';
import { signIn } from './actions';

export function LoginForm({ configured }: { configured: boolean }) {
  const [state, action, pending] = useActionState(signIn, { error: '' });
  return <form action={action} className="login-form">
    <label className="field" htmlFor="email">E-mail<input id="email" name="email" type="email" autoComplete="username" required maxLength={254} disabled={pending || !configured} /></label>
    <label className="field" htmlFor="password">Senha<input id="password" name="password" type="password" autoComplete="current-password" required maxLength={1024} disabled={pending || !configured} /></label>
    {state.error && <p className="notice error" role="alert">{state.error}</p>}
    {!configured && <p className="notice" role="alert">O acesso web ainda não está configurado. Consulte o responsável pelo sistema.</p>}
    <button type="submit" className="button" disabled={pending || !configured}>{pending ? 'Entrando…' : 'Entrar no EM'}</button>
  </form>;
}
