import { notFound } from 'next/navigation';
import { getStageApproval } from '@/server/web/stage-approval-data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { PageHeading, Status, Details, date, display } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { StageApprovalDecision } from '@/components/web/stage-approval-decision';
import { stageActionLabels } from '@/components/web/stage-approval-model';
import s from '@/components/web/stage-approval.module.css';

export default async function AprovacaoEtapa({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [session, data] = await Promise.all([requireWebUser('em.approvals.read'), getStageApproval(id)]);
  if (!data) notFound();
  const { stage, allocation, project, origin, destination } = data;
  const canProject = !!project && hasWebCapability(session, 'em.projects.read');
  const projectLabel = project?.numero ? `OS ${project.numero}` : project?.nome || 'Projeto sem OS';
  return <><a className="back-link" href="/aprovacoes"><Icon name="back" size={15} />Todas as aprovações</a>
    <PageHeading eyebrow="PCP · APROVAÇÃO DE ETAPA" title={stage.status_cel_proj === 'retornado' ? 'Etapa de retorno' : 'Liberação de etapa'} description={`${projectLabel}${project?.cliente_nome || project?.cliente_nome_exportacao ? ` · ${project.cliente_nome || project.cliente_nome_exportacao}` : ''}`} actions={canProject && <a className="button secondary" href={`/projetos/${project!.id}?tab=aprovacoes`}><Icon name="folder" size={15} />Ver projeto</a>} />
    <section className="panel"><div className="panel-header"><div className={s.route}><strong>{origin?.nome || 'Origem não disponível'}</strong><Icon name="arrow" size={17} /><strong>{destination?.nome || 'Destino não definido'}</strong></div><Status value={stage.status ?? 'nulo'} /></div><div className="panel-content"><Details values={[
      ['Status previsto para a etapa', display(stage.status_cel_proj)], ['Estado atual da célula de origem', allocation ? display(allocation.status) : 'Sem alocação de origem'], ['Aguardar aprovações bloqueadoras', stage.bloquear_avanco_sem_aprov ? 'Sim' : 'Não'],
      ['Aprovadores', data.approvers.map(user => user.nome).join(' · ') || 'Nenhum definido'], ['Aprovadores de retorno', data.return_approvers.map(user => user.nome).join(' · ') || 'Nenhum definido'], ['Decisão registrada por', data.decided_by?.nome],
      ['Data da decisão', date(stage.data_aprovacao, true)], ['Última atualização da etapa', date(stage.updated_at, true)], ['Execução da origem', allocation ? allocation.bloqueada === 'sim' ? `Bloqueada${allocation.motivo_bloqueio ? ` · ${allocation.motivo_bloqueio}` : ''}` : 'Sem bloqueio' : 'Não disponível'],
    ]} />{project?.descricao_equipamento && <p className={s.note} style={{ marginTop: 24, marginBottom: 0 }}>{project.descricao_equipamento}</p>}</div></section>
    {canProject && <div className="catalog-tabs" aria-label="Registros do projeto">{hasWebCapability(session, 'em.forms.read') && <a href={`/projetos/${project!.id}?tab=formularios`}>Formulários do projeto</a>}{hasWebCapability(session, 'em.photos.read') && <a href={`/projetos/${project!.id}?tab=fotos`}>Galeria de fotos</a>}{hasWebCapability(session, 'em.documents.read') && <a href={`/projetos/${project!.id}?tab=documentos`}>Documentos</a>}</div>}
    {!data.available_actions.length && data.action_reason && <div className="notice">{data.action_reason}</div>}
    {allocation && <StageApprovalDecision key={`${stage.id}:${stage.updated_at}:${allocation.updated_at}`} stageId={stage.id} stageVersion={stage.updated_at} cellVersion={allocation.updated_at} triggerStatus={stage.status_cel_proj} actions={data.available_actions} />}
    <section className="panel"><div className="panel-header"><h2>Decisões desta etapa <span className="inline-count">{data.history.length}</span></h2></div>{data.history.length ? <div className={s.history}>{data.history.map(event => <article key={event.id} className={s.event}><h3>{stageActionLabels[event.acao]} · {event.actor_nome || 'Responsável não disponível'}</h3><Status value={event.status_novo} /><p>{date(event.created_at, true)}</p>{event.observacao && <p className={s.comment}>{event.observacao}</p>}</article>)}</div> : <p className={s.emptyHistory}>Ainda não há decisões com vínculo direto a esta etapa.</p>}</section>
    <section className="panel"><div className="panel-header"><h2>Outras decisões da célula <span className="inline-count">{data.legacy_history.length}</span></h2></div><p className={s.sectionNote}>Estes registros informam a célula, mas não identificam uma etapa específica. Consulte-os como contexto do projeto.</p>{data.legacy_history.length ? <div className={s.history}>{data.legacy_history.map(event => <article key={event.id} className={s.event}><h3>{event.aprovador_nome || 'Responsável não disponível'}<span className={s.tag}>Sem vínculo com etapa</span></h3><Status value={event.status_aprovacao} /><p>{date(event.data_aprovacao || event.created_at, true)}</p></article>)}</div> : <p className={s.emptyHistory}>Nenhum outro registro de decisão encontrado nesta célula.</p>}</section>
  </>;
}
