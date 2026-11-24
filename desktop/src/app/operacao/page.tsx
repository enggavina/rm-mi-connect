import { loadOperation } from '@/server/operation/session';
import { Icon } from '@/components/web/icons';
import { Empty, PageHeading } from '@/components/web/ui';
import { OperationScreen, operationIssue } from './operation-screen';
import styles from './operation.module.css';

export default async function OperationCellsPage() {
  const result = await loadOperation();
  if (result.status !== 'ok') return operationIssue(result.status);
  const { workshop, operatorName, data } = result;
  if (data.kind !== 'cells') return operationIssue('unavailable');
  return <OperationScreen workshop={workshop} operatorName={operatorName}>
    <PageHeading title="Escolha sua célula" description="Abra uma célula para consultar os projetos liberados na sua oficina." />
    {data.items.length > 0 ? <ul className={styles.cards} aria-label="Células permitidas">
      {data.items.map(cell => <li key={cell.id}>
        <a className={styles.card} href={`/operacao/celulas/${cell.id}`}>
          <h2>{cell.nome}</h2>
          <span className={styles.cardAction}>Ver projetos <Icon name="arrow" size={15} /></span>
        </a>
      </li>)}
    </ul> : <section className="panel">
      <Empty icon="board" title="Nenhuma célula disponível" detail="Consulte o responsável pela oficina para verificar suas permissões de célula." />
    </section>}
  </OperationScreen>;
}
