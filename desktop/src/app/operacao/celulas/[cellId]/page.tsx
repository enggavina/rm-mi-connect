import { loadOperation } from '@/server/operation/session';
import { Icon } from '@/components/web/icons';
import { Empty, PageHeading, Pagination, Status } from '@/components/web/ui';
import { OperationBack, OperationScreen, operationIssue, projectTitle } from '../../operation-screen';
import styles from '../../operation.module.css';

export default async function OperationProjectsPage({ params, searchParams }: {
  params: Promise<{ cellId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const [{ cellId }, search] = await Promise.all([params, searchParams]);
  const value = search.page === undefined ? undefined : typeof search.page === 'string' && /^[1-9][0-9]{0,4}$/.test(search.page) ? Number(search.page) : Number.NaN;
  const result = await loadOperation({ cellId, page: value });
  if (result.status !== 'ok') return operationIssue(result.status);
  const { workshop, operatorName, data } = result;
  if (data.kind !== 'projects') return operationIssue('unavailable');
  const base = `/operacao/celulas/${data.cell.id}`;
  return <OperationScreen workshop={workshop} operatorName={operatorName}>
    <OperationBack href="/operacao">Voltar às células</OperationBack>
    <PageHeading eyebrow={data.cell.nome} title="Projetos da célula" />
    {data.items.length > 0 ? <ul className={styles.cards} aria-label="Projetos liberados">
      {data.items.map(project => <li key={project.id}>
        <a className={styles.card} href={`${base}/projetos/${project.id}`}>
          <div>
            <h2>{projectTitle(project)}</h2>
            {project.cliente && <p>{project.cliente}</p>}
            {project.numero && project.nome && <p>{project.nome}</p>}
            {project.status && <div className={styles.status}><Status value={project.status} /></div>}
          </div>
          <span className={styles.cardAction}>Abrir projeto <Icon name="arrow" size={15} /></span>
        </a>
      </li>)}
    </ul> : <section className="panel">
      <Empty title={data.total ? 'Página sem projetos' : 'Nenhum projeto liberado'} detail={data.total ? 'Volte para o início da lista.' : 'Os projetos aparecem aqui quando são liberados para esta célula.'}>
        {data.total > 0 && <a href={base} className="button secondary">Ir à primeira página</a>}
      </Empty>
    </section>}
    {data.items.length > 0 && data.total > data.page_size && <div className={`panel ${styles.pagination}`}>
      <Pagination page={data.page} pageSize={data.page_size} total={data.total} base={base} />
    </div>}
  </OperationScreen>;
}
