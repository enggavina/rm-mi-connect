import { Empty, PageHeading } from '@/components/web/ui';
import { OperationScreen } from './operation-screen';

export default function OperationNotFound() {
  return <OperationScreen>
    <PageHeading title="Consulta indisponível" />
    <section className="panel">
      <Empty title="Seleção indisponível" detail="Volte às células para consultar os projetos permitidos.">
        <a href="/operacao" className="button secondary">Voltar às células</a>
      </Empty>
    </section>
  </OperationScreen>;
}
