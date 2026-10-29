import { redirect } from 'next/navigation';
import { getWebAuthState } from '@/server/web/auth';
import { LoginForm } from './login-form';
import { AccessLayout } from '@/components/web/access';

export const dynamic = 'force-dynamic';
export default async function LoginPage() {
  const access = await getWebAuthState();
  if (access.state === 'authenticated') redirect('/painel');
  if (access.state === 'mfa') redirect('/login/mfa');
  return <AccessLayout title="Acesse sua operação" description="Entre com sua conta para acompanhar os projetos e organizar o trabalho da oficina.">
    <LoginForm configured={access.state !== 'unconfigured'} />
  </AccessLayout>;
}
