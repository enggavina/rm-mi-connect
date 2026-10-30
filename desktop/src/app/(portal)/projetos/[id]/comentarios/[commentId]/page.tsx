import { notFound } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { getProjectComment } from '@/server/web/project-comment-data';
import type { ProjectCommentSnapshot } from '@/server/web/project-comment-policy';
import { ProjectCommentCorrection } from '@/components/web/project-comment-editor';
import { commentHistoryPage } from '@/components/web/project-comment-model';
import { EngineeringReloadLink } from '@/components/web/engineering-save';
import { PageHeading, Pagination, Empty, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import s from '@/components/web/project-comment.module.css';

export default async function ComentarioProjeto({ params, searchParams }: {
  params: Promise<{ id: string; commentId: string }>; searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id: rawProjectId, commentId: rawCommentId }, query, session] = await Promise.all([params, searchParams, requireWebUser(['em.portal.read', 'em.projects.read', 'em.history.read'])]);
  const projectId = rawProjectId.toLowerCase(), commentId = rawCommentId.toLowerCase(), page = commentHistoryPage(query.page);
  const base = `/projetos/${projectId}/comentarios/${commentId}`;
  let snapshot: ProjectCommentSnapshot | null = null, unavailable = false;
  try { snapshot = await getProjectComment(projectId, commentId, page); } catch { unavailable = true; }
  if (!snapshot && !unavailable) notFound();
  const back = <a className="back-link" href={`/projetos/${projectId}?tab=historico`}><Icon name="back" size={15} />Voltar ao histórico do projeto</a>;
  if (!snapshot) return <>{back}<PageHeading eyebrow="HISTÓRICO DO PROJETO" title="Comentário indisponível" description="Não foi possível conferir o comentário e suas versões agora." /><section className="panel"><div className={s.unavailable}><p className="notice" role="status">A consulta não foi concluída. <EngineeringReloadLink href={`${base}?page=${page}`}>Recarregar comentário</EngineeringReloadLink> para tentar novamente.</p></div></section></>;
  const { project, comment, history } = snapshot;
  const manager = hasWebCapability(session, 'em.projects.manage') && (session.profile.perfil === 'administrador' || session.profile.perfil === 'padr_o' && session.profile.id === comment.cadastrado_por_id);
  const editable = manager && snapshot.can_edit && !project.closed && !!snapshot.allocation && !snapshot.allocation.retirada;
  const projectLabel = project.numero ? `OS ${project.numero.trim()}` : 'Projeto em recebimento';
  return <>{back}<PageHeading eyebrow="HISTÓRICO DO PROJETO" title="Comentário do projeto" description={projectLabel} />
    <section className="panel" id="comentario" data-project-comment-detail={comment.id}>
      <div className="panel-header"><h2>Comentário atual</h2>{history.total > 0 && <span className="panel-caption">{history.total} {history.total === 1 ? 'correção registrada' : 'correções registradas'}</span>}</div>
      <div className={s.body}><div className={s.meta}><span>Autor: {comment.author_name || (comment.cadastrado_por_id ? 'Autor registrado' : 'Não informado')}{comment.author_registration ? ` · ${comment.author_registration}` : ''}</span><span>{comment.cell_name || (comment.celula_id ? 'Célula histórica' : 'Projeto')}</span><span>Registrado em {date(comment.created_at, true)}</span></div>
        <p className={s.text}>{comment.evento || 'Sem texto registrado'}</p>{history.total > 0 && <p className={s.hint}>Última atualização: {date(comment.updated_at, true)}. O autor e a data original do comentário foram preservados.</p>}
      </div>
      {editable ? <ProjectCommentCorrection key={snapshot.context_version} snapshot={snapshot} /> : <div className={s.readonly}><p className="notice" role="status">{project.closed ? 'Projeto encerrado. O comentário e suas correções permanecem disponíveis para consulta.' : snapshot.reason || 'Comentário disponível para consulta conforme seu perfil de acesso.'}</p></div>}
    </section>
    <section className="panel" data-project-comment-history><div className="panel-header"><h2>Histórico de correções <span className="inline-count">{history.total}</span></h2></div>
      {!history.items.length ? <Empty title="Nenhuma correção registrada" detail="As correções feitas neste portal ficam registradas com o texto anterior, o novo texto, o responsável e o motivo." icon="users" />
        : <><p className={s.historyIntro}>O histórico conserva cada correção deste comentário. Autor, data original e célula de destino permanecem os mesmos.</p><div className={s.history}>{history.items.map(event => <article className={s.event} key={event.id} data-comment-revision={event.revision}>
          <h3>Correção {event.revision}</h3><div className={s.meta}><span>{event.editor_name || 'Responsável registrado'}{event.editor_registration ? ` · ${event.editor_registration}` : ''}</span><span>{date(event.created_at, true)}</span></div>
          <div className={s.comparison}><div><h5>Antes</h5><p>{event.evento_anterior || 'Sem texto registrado'}</p></div><div><h5>Após a correção</h5><p>{event.evento_novo || 'Sem texto registrado'}</p></div></div>
          <div className={s.reason}><strong>Motivo</strong><p>{event.motivo}</p></div>
        </article>)}</div></>}
      <Pagination page={history.page} pageSize={history.page_size} total={history.total} base={base} />
    </section>
  </>;
}
