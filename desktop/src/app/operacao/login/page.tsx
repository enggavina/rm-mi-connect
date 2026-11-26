import { AccessLayout } from '@/components/web/access';
import { OperationLoginForm } from './operation-login-form';

const errors = {
  invalid: 'Confira o e-mail e a senha do dispositivo.',
  forbidden: 'Consulte o responsável pelos acessos para revisar os vínculos da oficina.',
  session: 'O prazo para identificar o operador expirou. Entre novamente com a conta do dispositivo.',
  unavailable: 'O acesso à operação está indisponível. Tente novamente em alguns instantes.',
} as const;

export default async function OperationLoginPage({ searchParams }: { searchParams: Promise<{ erro?: string | string[] }> }) {
  const { erro } = await searchParams;
  const error = typeof erro === 'string' && Object.hasOwn(errors, erro) ? errors[erro as keyof typeof errors] : undefined;
  return <AccessLayout title="Acesse o EM Operacional" description="Entre com o e-mail e a senha do dispositivo.">
    <OperationLoginForm step="device" error={error} />
  </AccessLayout>;
}
