import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { AccessLayout } from '@/components/web/access';
import { openDeviceLogin, OPERATION_DEVICE_COOKIE } from '@/server/operation/policy';
import { OperationLoginForm } from '../operation-login-form';
import styles from '../../operation.module.css';

const errors = {
  invalid: 'Confira a matrícula e a palavra-chave do operador.',
  forbidden: 'Confirme com o responsável pelos acessos se o dispositivo e o operador estão vinculados à mesma oficina ativa.',
  unavailable: 'A identificação do operador está indisponível. Tente novamente em alguns instantes.',
} as const;

export default async function OperatorLoginPage({ searchParams }: { searchParams: Promise<{ erro?: string | string[] }> }) {
  const device = (await cookies()).get(OPERATION_DEVICE_COOKIE)?.value;
  if (!openDeviceLogin(device)) redirect('/operacao/login?erro=session');

  const { erro } = await searchParams;
  const error = typeof erro === 'string' && Object.hasOwn(errors, erro) ? errors[erro as keyof typeof errors] : undefined;
  return <AccessLayout title="Identifique o operador" description="Informe sua matrícula e sua palavra-chave para acessar as células da sua oficina.">
    <OperationLoginForm step="operator" error={error} />
    <form action="/operacao/login/cancelar" method="post" className={styles.changeDevice}>
      <button className="button secondary" type="submit">Trocar conta do dispositivo</button>
    </form>
  </AccessLayout>;
}
