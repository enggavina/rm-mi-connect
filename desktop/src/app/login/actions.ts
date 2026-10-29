'use server';
import { redirect } from 'next/navigation';
import { serverSupabase } from '@/server/web/auth';
import { resolveWebAccess } from '@/server/web/auth-policy';

export type LoginState = { error: string };
export async function signIn(_previous: LoginState, form: FormData): Promise<LoginState> {
  const email = form.get('email'), password = form.get('password');
  if (typeof email !== 'string' || typeof password !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())
    || email.length > 254 || !password || password.length > 1024) return { error: 'Informe seu e-mail e sua senha.' };
  const client = await serverSupabase();
  const { error } = await client.auth.signInWithPassword({ email: email.trim(), password });
  if (error) return { error: error.status === 429 ? 'Muitas tentativas. Aguarde um momento e tente novamente.' : 'Não foi possível entrar. Confira o e-mail e a senha.' };
  const access = await resolveWebAccess(client);
  if (access.state === 'mfa') redirect('/login/mfa');
  if (access.state !== 'authenticated') {
    await client.auth.signOut({ scope: 'local' });
    return { error: 'Esta conta não tem acesso ativo ao EM. Consulte o responsável pelo cadastro.' };
  }
  redirect('/painel');
}
