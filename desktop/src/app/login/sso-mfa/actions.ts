'use server';
import { redirect } from 'next/navigation';
import { verifySsoMfa } from '@/server/web/sso-bridge';
import { CorporateAuthError } from '@/server/web/sso-policy';

export async function verifyCorporateTotp(_previous: { error: string }, form: FormData): Promise<{ error: string }> {
  if (process.env.EM_SSO_ENABLED !== 'true') redirect('/login');
  const factor = form.get('factor'), code = form.get('code');
  if (typeof factor !== 'string' || !/^[0-9a-f-]{36}$/i.test(factor) || typeof code !== 'string' || !/^\d{6}$/.test(code.trim())) {
    return { error: 'Informe o código de seis dígitos do seu aplicativo autenticador.' };
  }
  let target: '/painel' | '/login/sso-mfa';
  try { target = await verifySsoMfa(factor, code.trim()); }
  catch (error) {
    if (error instanceof CorporateAuthError && error.code === 'CORP_FORBIDDEN') redirect('/acesso?motivo=permissao');
    return { error: error instanceof CorporateAuthError && error.code === 'CORP_UNAUTHORIZED'
      ? 'Não foi possível confirmar o código. Use o código atual ou volte ao login para iniciar novamente.'
      : 'Não foi possível confirmar o acesso agora. Volte ao login e tente novamente.' };
  }
  redirect(target);
}
