'use server';
import { redirect } from 'next/navigation';
import { getWebAuthState } from '@/server/web/auth';
import { resolveWebAccess } from '@/server/web/auth-policy';

export async function verifyTotp(_previous: { error: string }, form: FormData): Promise<{ error: string }> {
  const access = await getWebAuthState();
  if (access.state === 'authenticated') redirect('/painel');
  if (access.state !== 'mfa') redirect('/login');
  const code = form.get('code'), factorId = form.get('factor');
  if (typeof code !== 'string' || !/^\d{6}$/.test(code.trim()) || typeof factorId !== 'string' || !access.factors.some(factor => factor.id === factorId)) return { error: 'Informe o código de seis dígitos do seu aplicativo autenticador.' };
  const { error } = await access.client.auth.mfa.challengeAndVerify({ factorId, code: code.trim() });
  if (error) return { error: error.status === 429 ? 'Muitas tentativas. Aguarde um momento antes de tentar novamente.' : 'Código inválido ou expirado. Use o código atual do aplicativo.' };
  const verified = await resolveWebAccess(access.client);
  if (verified.state !== 'authenticated') return { error: 'Não foi possível confirmar o acesso. Tente novamente.' };
  redirect('/painel');
}
