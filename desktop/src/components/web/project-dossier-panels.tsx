import type { WebRow } from '@/server/web/data';
import type { ProjectCommentFilters, ProjectCommentPage, ProjectDocumentFilters, ProjectDocumentPage } from '@/server/web/project-dossier-search-policy';
import { Empty, Status, date, display } from './ui';
import { Icon } from './icons';
import { ProjectAttachmentEditor, ProjectCommentEditor } from './project-dossier-editors';
import { ProjectDossierFilters, ProjectDossierPagination } from './project-dossier-search-filters';
import { dossierSearchActive } from './project-dossier-search-model';
import type { DossierCommentAllocation } from './project-dossier-model';
import s from './project-dossier.module.css';

export function ProjectDocumentsPanel({ projectId, projectVersion, data, filters, error, canAdd, closed }: {
  projectId: string; projectVersion: string; data: ProjectDocumentPage | null; filters: ProjectDocumentFilters; error?: string; canAdd: boolean; closed: boolean;
}) {
  const currentFilters = data?.filters ?? filters, filtered = dossierSearchActive(currentFilters);
  return <section className="panel" data-project-documents><div className="panel-header"><h2>Documentos e anexos {data && <span className="inline-count">{data.unfiltered_total}</span>}</h2></div>
    {closed && <div className={s.readonly}><p className="notice">Este projeto está encerrado. Os documentos permanecem disponíveis para consulta.</p></div>}
    {canAdd && !closed && <ProjectAttachmentEditor projectId={projectId} projectVersion={projectVersion} />}
    <ProjectDossierFilters projectId={projectId} kind="documents" filters={currentFilters} facets={data?.facets ?? { authors: [], statuses: [] }} error={error} />
    {!data ? <div className={s.readonly}><p className="notice" role="status">Não foi possível carregar a consulta de documentos. Confira os filtros ou recarregue a página para tentar novamente.</p></div>
      : !data.items.length ? <Empty title={filtered ? 'Nenhum documento encontrado com esses filtros' : 'Nenhum documento vinculado'} detail={filtered ? 'Altere ou limpe os filtros para consultar os documentos e anexos preservados no projeto.' : 'Os documentos e anexos disponíveis neste projeto serão exibidos aqui.'} icon="file" />
      : data.items.map(document => <div className="document-row" key={`${document.source}:${document.id}`} data-project-document={document.id} data-document-source={document.source}>
        <span className="document-icon"><Icon name="file" size={20} /></span><div className="document-copy"><h3 className={s.documentTitle}>{document.nome || (document.tipo_documento ? display(document.tipo_documento) : 'Documento do projeto')}</h3>
          <p>{document.source === 'docs' ? document.visivel_cliente === false ? 'Anexo interno' : 'Anexo' : 'Documento'} · {date(document.created_at)}{document.descricao ? ` · ${document.descricao}` : ''}</p>
          <div className={s.documentMeta}>{document.status && <Status value={document.status === 'Vencido' ? 'atrasado' : document.status === 'No prazo' ? 'ativo' : document.status} label={document.status} />}
            {document.data_vencimento && <span>Vencimento: {date(document.data_vencimento)}</span>}{document.created_by && <span>Por {document.author_name || 'Autor registrado'}{document.author_registration ? ` · ${document.author_registration}` : ''}</span>}
            {document.tipo_arquivo && <span>{({ 'application/pdf': 'PDF', 'image/jpeg': 'JPEG', 'image/png': 'PNG' } as Record<string, string>)[document.tipo_arquivo] || document.tipo_arquivo}</span>}</div>
        </div>{document.has_file ? <a className="button small secondary" href={`/api/web/documents/${document.id}${document.source === 'docs' ? '?source=docs' : ''}`} target="_blank" rel="noopener noreferrer" aria-label={`Abrir ${document.nome || 'documento do projeto'}`}><Icon name="download" size={14} />Abrir</a> : <span className="panel-caption">Arquivo indisponível</span>}
      </div>)}
    {data && <ProjectDossierPagination projectId={projectId} kind="documents" page={data.page} pageSize={data.page_size} total={data.total} unfilteredTotal={data.unfiltered_total} filters={data.filters} />}
  </section>;
}

export function ProjectHistoryPanel({ projectId, projectVersion, data, filters, error, stages, cells, users, allocations, canAdd, closed }: {
  projectId: string; projectVersion: string; data: ProjectCommentPage | null; filters: ProjectCommentFilters; error?: string; stages: WebRow[]; cells: WebRow[]; users: WebRow[];
  allocations: WebRow[]; canAdd: boolean; closed: boolean;
}) {
  const cellNames = new Map(cells.map(cell => [cell.id, cell.nome])), userNames = new Map(users.map(user => [user.id, user.nome]));
  const currentFilters = data?.filters ?? filters, filtered = dossierSearchActive(currentFilters);
  const choices: DossierCommentAllocation[] = allocations.filter(allocation => allocation.projeto_id === projectId && !allocation.retirada).map(allocation => ({
    id: allocation.id, projeto_id: allocation.projeto_id, celula_id: allocation.celula_id, updated_at: allocation.updated_at,
    retirada: allocation.retirada, visibilidade: allocation.visibilidade, name: cellNames.get(allocation.celula_id) || 'Célula do projeto',
  }));
  return <div className="two-columns"><section className="panel" data-project-comments><div className="panel-header"><h2>Comentários do projeto {data && <span className="inline-count">{data.unfiltered_total}</span>}</h2></div>
    {closed && <div className={s.readonly}><p className="notice">Este projeto está encerrado. Os comentários permanecem disponíveis para consulta.</p></div>}
    {canAdd && !closed && <ProjectCommentEditor projectId={projectId} projectVersion={projectVersion} allocations={choices} />}
    <ProjectDossierFilters projectId={projectId} kind="comments" filters={currentFilters} facets={data?.facets ?? { authors: [], cells: [] }} error={error} />
    {!data ? <div className={s.readonly}><p className="notice" role="status">Não foi possível carregar a consulta de comentários. Confira os filtros ou recarregue a página para tentar novamente.</p></div>
      : !data.items.length ? <Empty title={filtered ? 'Nenhum comentário encontrado com esses filtros' : 'Sem comentários'} detail={filtered ? 'Altere ou limpe os filtros para consultar o histórico preservado no projeto.' : 'Os comentários registrados pela equipe serão reunidos aqui.'} icon="users" />
      : <div className="activity-list">{data.items.map(comment => <div className="activity-item" key={comment.id} data-project-comment={comment.id}><span className="activity-icon"><Icon name="users" size={16} /></span><div><h3>{comment.author_name || 'Autor registrado'}{comment.author_registration ? ` · ${comment.author_registration}` : ''} · {comment.cell_name || (comment.celula_id ? 'Célula histórica' : 'Projeto')}</h3><p className={s.commentText}>{comment.evento}</p><p>{date(comment.created_at, true)}</p><a className="text-link" href={`/projetos/${projectId}/comentarios/${comment.id}`} aria-label={`Consultar comentário de ${comment.author_name || 'autor registrado'}`}>Consultar comentário</a></div></div>)}</div>}
    {data && <ProjectDossierPagination projectId={projectId} kind="comments" page={data.page} pageSize={data.page_size} total={data.total} unfilteredTotal={data.unfiltered_total} filters={data.filters} />}
  </section><section className="panel"><div className="panel-header"><h2>Aprovações das etapas</h2></div>{stages.length ? <div className="activity-list">{stages.map(stage => <div className="activity-item" key={stage.id}><span className="activity-icon"><Icon name="check" size={16} /></span><div><h3>{cellNames.get(stage.celula_origem_id) || 'Etapa da célula'}</h3><Status value={stage.status} /><p style={{ marginTop: 7 }}>{userNames.get(stage.aprovado_por_id) || userNames.get(stage.aprovador_id) || 'Aprovador não definido'}{stage.data_aprovacao ? ` · ${date(stage.data_aprovacao)}` : ''}</p></div></div>)}</div> : <Empty title="Nenhuma etapa definida" detail="As aprovações são definidas nos modelos do roteiro de execução." icon="check" />}</section></div>;
}
