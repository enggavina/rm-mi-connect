import Link from 'next/link';
import { AccessLayout } from '@/components/web/access';
import { OperationLoginForm } from './operation-login-form';

const errors = {
  invalid: 'Confira os dados de acesso do dispositivo e a identificação do operador.',
  forbidden: 'A operação exige vínculos ativos do dispositivo e do operador na mesma oficina. Consulte o responsável pelos acessos.',
  unavailable: 'O acesso à operação está indisponível. Tente novamente em alguns instantes.',
} as const;

export default async function OperationLoginPage({ searchParams }: { searchParams: Promise<{ erro?: string | string[] }> }) {
  const { erro } = await searchParams;
  const error = typeof erro === 'string' && Object.hasOwn(errors, erro) ? errors[erro as keyof typeof errors] : undefined;
  return <AccessLayout title="Acesse o EM Operacional" description="Informe a conta do dispositivo e seus dados de operador para consultar os projetos da sua oficina.">
    <OperationLoginForm error={error} />
    <Link className="text-link" href="/login">Acesso à gestão da oficina</Link>
    <Link className="text-link" href="/operacao/validacao">Validação com conta Microsoft</Link>
  </AccessLayout>;
}
