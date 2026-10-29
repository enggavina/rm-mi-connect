import { redirect } from 'next/navigation';
import { getWebAuthState } from '@/server/web/auth';
import { MfaForm } from './mfa-form';
import { AccessLayout } from '@/components/web/access';

export const dynamic = 'force-dynamic';
export default async function MfaPage() {
  const access = await getWebAuthState();
  if (access.state === 'authenticated') redirect('/painel');
  if (access.state !== 'mfa') redirect('/login');
  return <AccessLayout title="Confirme sua identidade" description="Digite o código do aplicativo autenticador já vinculado à sua conta.">
    <MfaForm factors={access.factors} />
    <form action="/auth/logout" method="post" style={{ marginTop: 15 }}><button className="button secondary full" type="submit">Voltar ao login</button></form>
  </AccessLayout>;
}
