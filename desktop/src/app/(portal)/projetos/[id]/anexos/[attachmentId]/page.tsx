import { notFound } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { getProjectAttachment } from '@/server/web/project-attachment-version-data';
import type { ProjectAttachmentSnapshot } from '@/server/web/project-attachment-version-policy';
import { ProjectAttachmentVersionEditor } from '@/components/web/project-attachment-version-editor';
import { attachmentFileSize, attachmentHistoryPage, attachmentVersionEligible } from '@/components/web/project-attachment-version-model';
import { EngineeringReloadLink } from '@/components/web/engineering-save';
import { PageHeading, Pagination, Empty, Status, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import s from '@/components/web/project-attachment-version.module.css';

export default async function AnexoProjeto({ params, searchParams }: {
  params: Promise<{ id: string; attachmentId: string }>; searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id: rawProjectId, attachmentId: rawAttachmentId }, query, session] = await Promise.all([params, searchParams, requireWebUser(['em.portal.read', 'em.projects.read', 'em.documents.read'])]);
  const projectId = rawProjectId.toLowerCase(), attachmentId = rawAttachmentId.toLowerCase(), page = attachmentHistoryPage(query.page);
  const base = `/projetos/${projectId}/anexos/${attachmentId}`;
  let snapshot: ProjectAttachmentSnapshot | null = null, unavailable = false;
  try { snapshot = await getProjectAttachment(projectId, attachmentId, page); } catch { unavailable = true; }
  if (!snapshot && !unavailable) notFound();
  const back = <a className="back-link" href={`/projetos/${projectId}?tab=documentos`}><Icon name="back" size={15} />Voltar aos documentos do projeto</a>;
  if (!snapshot) return <>{back}<PageHeading eyebrow="DOCUMENTOS DO PROJETO" title="Anexo indisponível" description="Não foi possível conferir o anexo e suas versões agora." /><section className="panel"><div className={s.unavailable}><p className="notice" role="status">A consulta não foi concluída. <EngineeringReloadLink href={`${base}?page=${page}`}>Recarregar anexo</EngineeringReloadLink> para tentar novamente.</p></div></section></>;
  const { project, attachment, series, history } = snapshot;
  const manager = hasWebCapability(session, 'em.projects.manage') && ['administrador', 'padr_o'].includes(session.profile.perfil);
  const editable = manager && attachmentVersionEligible(snapshot), selectedCurrent = !!series && attachment.id === series.head_id;
  const projectLabel = project.numero ? `OS ${project.numero.trim()}` : 'Projeto em recebimento';
  return <>{back}<div className={s.heading}><PageHeading eyebrow="DOCUMENTOS DO PROJETO" title={attachment.nome || 'Anexo do projeto'} description={projectLabel} /></div>
    <section className="panel" id="anexo" data-project-attachment-detail={attachment.id}>
      <div className="panel-header"><h2>{series ? `Versão ${series.selected_revision}` : 'Arquivo do projeto'}</h2>{selectedCurrent && <span className={s.badge}>Versão atual</span>}</div>
      <div className={s.body}>
        {series && !selectedCurrent && <p className="notice">Você está consultando a versão {series.selected_revision}. <a className="text-link" href={`/projetos/${projectId}/anexos/${series.head_id}`}>Abrir versão atual ({series.head_revision})</a>.</p>}
        <div className={s.meta}><span>Por {attachment.author_name || (attachment.created_by ? 'Autor registrado' : 'Não informado')}{attachment.author_registration ? ` · ${attachment.author_registration}` : ''}</span><span>Registrado em {date(attachment.created_at, true)}</span>
          {attachment.tipo_arquivo && <span>{({ 'application/pdf': 'PDF', 'image/jpeg': 'JPEG', 'image/png': 'PNG' } as Record<string, string>)[attachment.tipo_arquivo] || attachment.tipo_arquivo}</span>}{attachment.byte_size !== null && <span>{attachmentFileSize(attachment.byte_size)}</span>}</div>
        {attachment.filename && <h3 className={s.text}>{attachment.filename}</h3>}{attachment.descricao && <p className={s.text}>{attachment.descricao}</p>}
        <div className={s.meta}>{attachment.status && <Status value={attachment.status === 'Vencido' ? 'atrasado' : attachment.status === 'No prazo' ? 'ativo' : attachment.status} label={attachment.status} />}{attachment.data_vencimento && <span>Vencimento: {date(attachment.data_vencimento)}</span>}</div>
        <div className={s.links}>{attachment.has_file ? <a className="button small secondary" href={`/api/web/documents/${attachment.id}?source=docs`} target="_blank" rel="noopener noreferrer"><Icon name="download" size={14} />Abrir esta versão</a> : <span className="panel-caption">Arquivo indisponível</span>}</div>
      </div>
      {editable ? <ProjectAttachmentVersionEditor key={snapshot.context_version} snapshot={snapshot} /> : <div className={s.readonly}><p className="notice" role="status">{project.closed ? 'Projeto encerrado. O anexo e suas versões permanecem disponíveis para consulta.' : !selectedCurrent && series ? 'Para enviar uma nova versão, abra a versão atual do anexo.' : snapshot.reason || 'Anexo disponível para consulta conforme seu perfil de acesso.'}</p></div>}
    </section>
    <section className="panel" data-project-attachment-history><div className="panel-header"><h2>Histórico de versões <span className="inline-count">{history.total}</span></h2></div>
      {!history.items.length ? <Empty title="Sem histórico de versões disponível" detail="O portal não possui uma sequência de versões comprovada para este arquivo. O registro existente permanece disponível para consulta." icon="file" />
        : <><p className={s.historyIntro}>Cada versão conserva seu arquivo, os dados de publicação e o motivo da substituição. Os downloads abrem a versão indicada.</p><div className={s.history}>{history.items.map(version => <article className={s.version} key={version.id} data-attachment-revision={version.revision}>
          <div className={s.versionHeading}><h3>Versão {version.revision} · {version.nome || 'Anexo do projeto'}</h3>{version.current && <span className={s.badge}>Atual</span>}</div>
          <div className={s.meta}><span>{version.author_name || (version.created_by ? 'Autor registrado' : 'Não informado')}{version.author_registration ? ` · ${version.author_registration}` : ''}</span><span>{date(version.created_at, true)}</span>{version.byte_size !== null && <span>{attachmentFileSize(version.byte_size)}</span>}</div>
          {version.filename && <p className={s.text}>{version.filename}</p>}{version.descricao && <p className={s.text}>{version.descricao}</p>}
          <div className={s.meta}>{version.status && <span>Situação: {version.status}</span>}{version.data_vencimento && <span>Vencimento: {date(version.data_vencimento)}</span>}</div>
          {version.motivo ? <div className={s.reason}><strong>Motivo da substituição</strong><p>{version.motivo}</p></div> : <p className={s.hint}>Arquivo base desta sequência de versões.</p>}
          <div className={s.links}><a className="text-link" href={`/projetos/${projectId}/anexos/${version.id}`} aria-current={version.id === attachment.id ? 'page' : undefined}>Consultar versão {version.revision}</a>{version.has_file && <a className="button small secondary" href={`/api/web/documents/${version.id}?source=docs`} target="_blank" rel="noopener noreferrer" aria-label={`Abrir arquivo da versão ${version.revision}`}><Icon name="download" size={14} />Abrir arquivo</a>}</div>
        </article>)}</div></>}
      <Pagination page={history.page} pageSize={history.page_size} total={history.total} base={base} />
    </section>
  </>;
}
