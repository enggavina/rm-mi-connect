import type { OperationData } from '@/server/operation/policy';
import type { OperationResult } from '@/server/operation/service';
import { templateSections } from '@/components/web/form-template-model';
import { Icon } from '@/components/web/icons';
import { Details, Empty, PageHeading, Pagination, Status } from '@/components/web/ui';
import { OperationBack, OperationScreen, operationIssue, projectTitle, type OperationRoute } from './operation-screen';
import styles from './operation.module.css';

export function operationPageNumber(page?: string | string[]) {
  if (page === undefined) return undefined;
  return typeof page === 'string' && /^[1-9][0-9]{0,4}$/.test(page) ? Number(page) : Number.NaN;
}

function OperationCells({ items, base }: { items: Extract<OperationData, { kind: 'cells' }>['items']; base: OperationRoute }) {
  return <>
    <PageHeading eyebrow={base === '/operacao/validacao' ? 'VALIDAÇÃO OPERACIONAL' : undefined}
      title="Escolha sua célula" description="Abra uma célula para consultar os projetos liberados na sua oficina." />
    {items.length > 0 ? <ul className={styles.cards} aria-label="Células permitidas">
      {items.map(cell => <li key={cell.id}>
        <a className={styles.card} href={`${base}/celulas/${cell.id}`}>
          <h2>{cell.nome}</h2>
          <span className={styles.cardAction}>Ver projetos <Icon name="arrow" size={15} /></span>
        </a>
      </li>)}
    </ul> : <section className="panel">
      <Empty icon="board" title="Nenhuma célula disponível" detail="Consulte o responsável pela oficina para verificar suas permissões de célula." />
    </section>}
  </>;
}

function OperationProjects({ data, base }: { data: Extract<OperationData, { kind: 'projects' }>; base: OperationRoute }) {
  const cellPath = `${base}/celulas/${data.cell.id}`;
  return <>
    <OperationBack href={base}>Voltar às células</OperationBack>
    <PageHeading eyebrow={data.cell.nome} title="Projetos da célula" />
    {data.items.length > 0 ? <ul className={styles.cards} aria-label="Projetos liberados">
      {data.items.map(project => <li key={project.id}>
        <a className={styles.card} href={`${cellPath}/projetos/${project.id}`}>
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
        {data.total > 0 && <a href={cellPath} className="button secondary">Ir à primeira página</a>}
      </Empty>
    </section>}
    {data.items.length > 0 && data.total > data.page_size && <div className={`panel ${styles.pagination}`}>
      <Pagination page={data.page} pageSize={data.page_size} total={data.total} base={cellPath} />
    </div>}
  </>;
}

function OperationProject({ data, base }: { data: Extract<OperationData, { kind: 'project' }>; base: OperationRoute }) {
  const { project } = data;
  return <>
    <OperationBack href={`${base}/celulas/${data.cell.id}`}>Voltar aos projetos da célula</OperationBack>
    <PageHeading eyebrow={data.cell.nome} title={projectTitle(project)} description={project.numero ? project.nome ?? undefined : undefined}
      actions={project.status && <Status value={project.status} />} />
    <section className={`panel panel-content ${styles.projectInfo}`} aria-label="Informações do projeto">
      <Details values={[["Cliente", project.cliente], ["Descrição", project.descricao]]} />
    </section>
    <section aria-labelledby="formularios-projeto">
      <h2 id="formularios-projeto" className={styles.heading}>Formulários vinculados</h2>
      {data.forms.length > 0 ? <ul className={styles.cards}>
        {data.forms.map(form => <li key={form.id}>
          <a className={styles.card} href={`${base}/celulas/${data.cell.id}/projetos/${project.id}/formularios/${form.id}`}>
            <h3>{form.titulo || 'Formulário sem título'}</h3>
            <span className={styles.cardAction}>Abrir formulário <Icon name="arrow" size={15} /></span>
          </a>
        </li>)}
      </ul> : <div className="panel">
        <Empty icon="clipboard" title="Nenhum formulário vinculado" detail="Os formulários atribuídos ao projeto nesta célula aparecem aqui." />
      </div>}
    </section>
  </>;
}

function OperationForm({ data, base }: { data: Extract<OperationData, { kind: 'form' }>; base: OperationRoute }) {
  const { cell, project, form, questions } = data;
  const sections = templateSections(questions);
  return <>
    <OperationBack href={`${base}/celulas/${cell.id}/projetos/${project.id}`}>Voltar ao projeto</OperationBack>
    <PageHeading eyebrow={`${cell.nome} · ${projectTitle(project)}`}
      title={form.titulo || 'Formulário sem título'} description={form.descricao ?? undefined} />
    <p className={styles.readOnly}>Somente leitura</p>
    {sections.length ? <div className={styles.sections}>
      {sections.map(section => <details key={section.id} className={`panel ${styles.section}`}>
        <summary>{section.title}</summary>
        <div className={styles.sectionContent}>
          {section.description && <p className={styles.questionNote}>{section.description}</p>}
          {section.questions.length ? <ul className={styles.questions}>
            {section.questions.map(question => <li key={question.id}>
              <strong>{question.enunciado || 'Questão sem enunciado'}</strong>
              {question.obrigatorio && <span className={styles.questionNote}>Obrigatória</span>}
              {question.subtitulo && <p className={styles.questionNote}>{question.subtitulo}</p>}
              {question.items.length > 0 && <ul className={styles.choices}>
                {question.items.map(item => <li key={item.id}>{item.descricao}</li>)}
              </ul>}
            </li>)}
          </ul> : <p className={styles.questionNote}>Nenhuma pergunta nesta seção.</p>}
        </div>
      </details>)}
    </div> : <section className="panel">
      <Empty icon="clipboard" title="Formulário sem perguntas" />
    </section>}
  </>;
}

export function OperationView({ result, kind, base = '/operacao' }: { result: OperationResult; kind: OperationData['kind']; base?: OperationRoute }) {
  if (result.status !== 'ok') return operationIssue(result.status, base);
  const { workshop, operatorName, data } = result;
  if (data.kind !== kind) return operationIssue('unavailable', base);
  return <OperationScreen base={base} workshop={workshop} operatorName={operatorName}>
    {data.kind === 'cells' && <OperationCells items={data.items} base={base} />}
    {data.kind === 'projects' && <OperationProjects data={data} base={base} />}
    {data.kind === 'project' && <OperationProject data={data} base={base} />}
    {data.kind === 'form' && <OperationForm data={data} base={base} />}
  </OperationScreen>;
}
