import { AccessLayout } from '@/components/web/access';

export const dynamic = 'force-dynamic';
export default async function Acesso({ searchParams }: { searchParams: Promise<{ motivo?: string }> }) {
  const unavailable = (await searchParams).motivo === 'indisponivel';
  return <AccessLayout title={unavailable ? 'Acesso temporariamente indisponível' : 'Permissão necessária'}
    description={unavailable ? 'Não foi possível consultar a Central de Acessos. Tente novamente em instantes.' : 'Sua conta não possui a permissão necessária para abrir esta área do EM.'}>
    <a className="button primary" href="/painel">Voltar ao painel</a>
    <form action="/auth/logout" method="post" style={{ marginTop: 16 }}><button className="button secondary" type="submit">Sair e trocar de conta</button></form>
  </AccessLayout>;
}
