import { redirect } from 'next/navigation';
import { AccessLayout } from '@/components/web/access';
import { pendingSsoMfa } from '@/server/web/sso-bridge';
import { CorporateAuthError } from '@/server/web/sso-policy';
import { SsoMfaForm } from './mfa-form';

export const dynamic = 'force-dynamic';
export const metadata = { referrer: 'same-origin' as const };
export default async function SsoMfaPage() {
  if (process.env.EM_SSO_ENABLED !== 'true') redirect('/login');
  let pending: Awaited<ReturnType<typeof pendingSsoMfa>>;
  try { pending = await pendingSsoMfa(); }
  catch (error) {
    redirect(error instanceof CorporateAuthError && error.code === 'CORP_FORBIDDEN' ? '/acesso?motivo=permissao'
      : error instanceof CorporateAuthError && error.code === 'CORP_UNAUTHORIZED' ? '/login?erro=sso' : '/login?erro=sso_indisponivel');
  }
  if (!pending.factors.length) redirect('/login?erro=sso');
  return <AccessLayout title="Confirme sua identidade" description={pending.provider === 'corporate'
    ? 'Digite o código do aplicativo autenticador vinculado à sua conta corporativa.'
    : 'Sua conta EM também possui uma verificação adicional. Digite o código do autenticador vinculado ao EM.'}>
    <SsoMfaForm factors={pending.factors} />
    <form action="/auth/logout" method="post" style={{ marginTop: 15 }}><button className="button secondary full" type="submit">Voltar ao login</button></form>
  </AccessLayout>;
}
