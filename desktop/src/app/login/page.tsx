import { redirect } from 'next/navigation';
import { getWebAuthState } from '@/server/web/auth';
import { LoginForm } from './login-form';
import { AccessLayout } from '@/components/web/access';
import { CorporateAuthError } from '@/server/web/sso-policy';

export const dynamic = 'force-dynamic';
export const metadata = { referrer: 'no-referrer' as const };
const ssoErrors: Record<string, string> = {
  sso: 'Não foi possível concluir o acesso corporativo. Tente novamente.',
  sso_indisponivel: 'O acesso corporativo está temporariamente indisponível. Tente novamente em instantes.',
  sso_permissao: 'Sua conta não tem acesso autorizado ao EM. Consulte o responsável pelos acessos.',
};
export default async function LoginPage({ searchParams }: { searchParams: Promise<{ erro?: string | string[] }> }) {
  const corporate = process.env.EM_SSO_ENABLED === 'true';
  const query = await searchParams;
  let error = typeof query.erro === 'string' && Object.hasOwn(ssoErrors, query.erro) ? ssoErrors[query.erro] : undefined;
  let access: Awaited<ReturnType<typeof getWebAuthState>> | undefined;
  try { access = await getWebAuthState(); }
  catch (failure) {
    if (!corporate) throw failure;
    error = failure instanceof CorporateAuthError && failure.code === 'CORP_FORBIDDEN' ? ssoErrors.sso_permissao : ssoErrors.sso_indisponivel;
  }
  if (access?.state === 'authenticated') redirect('/painel');
  if (access?.state === 'mfa') redirect('/login/mfa');
  if (corporate) return <AccessLayout title="Acesse com sua conta corporativa" description="Use sua conta Microsoft da MI Electric Brasil para entrar no EM.">
    <form method="post" action="/auth/sso/start" className="login-form">
      {error && <p className="notice error" role="alert">{error}</p>}
      <button type="submit" className="button">Entrar com Microsoft</button>
    </form>
  </AccessLayout>;
  return <AccessLayout title="Acesse sua operação" description="Entre com sua conta para acompanhar os projetos e organizar o trabalho da oficina.">
    <LoginForm configured={access !== undefined && access.state !== 'unconfigured'} />
  </AccessLayout>;
}
