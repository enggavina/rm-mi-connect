'use client';
import { useActionState } from 'react';
import { verifyCorporateTotp } from './actions';

export function SsoMfaForm({ factors }: { factors: { id: string; name: string }[] }) {
  const [state, action, pending] = useActionState(verifyCorporateTotp, { error: '' });
  return <form action={action} className="login-form">
    {factors.length === 1 ? <input type="hidden" name="factor" value={factors[0].id} /> : <label className="field" htmlFor="factor">Autenticador<select id="factor" name="factor" required disabled={pending}>{factors.map(factor => <option key={factor.id} value={factor.id}>{factor.name}</option>)}</select></label>}
    <label className="field" htmlFor="code">Código de verificação<input id="code" name="code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" minLength={6} maxLength={6} required autoFocus disabled={pending} /></label>
    {state.error && <p className="notice error" role="alert">{state.error}</p>}
    <button type="submit" className="button" disabled={pending || !factors.length}>{pending ? 'Verificando…' : 'Confirmar acesso'}</button>
  </form>;
}
