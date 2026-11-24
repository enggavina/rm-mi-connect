import { loadOperation } from '@/server/operation/session';
import { Details, Empty, PageHeading, Status } from '@/components/web/ui';
import { OperationBack, OperationScreen, operationIssue, projectTitle } from '../../../../operation-screen';
import styles from '../../../../operation.module.css';

export default async function OperationProjectPage({ params }: { params: Promise<{ cellId: string; projectId: string }> }) {
  const { cellId, projectId } = await params;
  const result = await loadOperation({ cellId, projectId });
  if (result.status !== 'ok') return operationIssue(result.status);
  const { workshop, operatorName, data } = result;
  if (data.kind !== 'project') return operationIssue('unavailable');
  const { project } = data;
  return <OperationScreen workshop={workshop} operatorName={operatorName}>
    <OperationBack href={`/operacao/celulas/${data.cell.id}`}>Voltar aos projetos da célula</OperationBack>
    <PageHeading eyebrow={data.cell.nome} title={projectTitle(project)} description={project.numero ? project.nome ?? undefined : undefined}
      actions={project.status && <Status value={project.status} />} />
    <section className={`panel panel-content ${styles.projectInfo}`} aria-label="Informações do projeto">
      <Details values={[["Cliente", project.cliente], ["Descrição", project.descricao]]} />
    </section>
    <section aria-labelledby="formularios-projeto">
      <h2 id="formularios-projeto" className={styles.heading}>Formulários vinculados</h2>
      {data.forms.length > 0 ? <ul className={styles.cards}>
        {data.forms.map(form => <li key={form.id} className={styles.card}><p>{form.titulo || 'Formulário sem título'}</p></li>)}
      </ul> : <div className="panel">
        <Empty icon="clipboard" title="Nenhum formulário vinculado" detail="Os formulários atribuídos ao projeto nesta célula aparecem aqui." />
      </div>}
    </section>
  </OperationScreen>;
}
