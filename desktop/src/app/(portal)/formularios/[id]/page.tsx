import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createWebData } from '@/server/web/data';
import { requireWebUser } from '@/server/web/auth';
import { PageHeading, Status, Details, Empty, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { RecordReview } from '@/components/web/review';
import { mayReview, recordSections } from '@/components/web/review-model';

export default async function RegistroFormulario({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const session = await requireWebUser();
  const data = await createWebData(session.client).getRecord(id);
  if (!data) notFound();
  const { record, project, form, answers, questions, items, users } = data;
  const names = new Map(users.map(user => [user.id, user.nome]));
  const eligible = mayReview(record, session.profile);
  const sections = recordSections(answers, questions, items);
  const historicalCount = sections.flatMap(section => section.answers).filter(answer => answer.historical).length;
  const title = form?.titulo || form?.title || record.descricao || 'Registro de formulário';
  const projectLabel = project?.numero || record.numero_projeto_rm;
  return <>
    <Link className="back-link" href="/formularios"><Icon name="back" size={15} />Todos os formulários</Link>
    <PageHeading eyebrow="CONSULTA E REVISÃO" title={title} description={`${record.codigo_text || (record.codigo != null ? `Registro ${record.codigo}` : 'Registro de formulário')}${projectLabel ? ` · OS ${projectLabel}` : ''}`} actions={project && <Link className="button secondary" href={`/projetos/${project.id}?tab=formularios`}><Icon name="folder" size={15} />Ver projeto</Link>} />
    <section className="panel"><div className="panel-header"><h2>Dados do registro</h2><Status value={record.status} /></div><div className="panel-content"><Details values={[
      ['Projeto', projectLabel || project?.nome], ['Responsável pelo preenchimento', names.get(record.identidade_user_id) || names.get(record.responsavel_user_id) || names.get(record.created_by_user_id)],
      ['Avaliador', names.get(record.avaliador_user_id)], ['Concluído em', date(record.data_conclusao, true)], ['Revisado em', date(record.data_revisao, true)],
      ['Última atualização', date(record.updated_at, true)], ['Respostas registradas', answers.length], ['Parecer registrado', record.parecer],
    ]} /></div></section>
    {!!historicalCount && <div className="notice">{historicalCount} respostas históricas não têm uma questão atual vinculada. O conteúdo original permanece disponível para consulta.</div>}
    {!eligible && record.status === 'em_an_lise' && <div className="notice">A revisão está disponível ao avaliador designado ou a um administrador quando o formulário está preenchido.</div>}
    {record.status === 'direcionado' && <div className="notice">Este formulário está com a equipe para correção. Uma nova decisão ficará disponível quando as respostas forem reenviadas para análise.</div>}
    {answers.length ? <RecordReview key={`${record.id}:${record.updated_at}`} recordId={record.id} version={record.updated_at} sections={sections} canReview={eligible} mediaOrigin={process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || ''} />
      : <section className="panel"><Empty title="Nenhuma resposta disponível" detail="Este registro permanece disponível para consulta. A revisão exige respostas enviadas pela equipe." icon="clipboard" /></section>}
  </>;
}
