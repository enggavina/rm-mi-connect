import type { WebRow } from '@/server/web/data';
import { Empty, Status, date, display } from './ui';
import { Icon } from './icons';
import { ProjectAttachmentEditor, ProjectCommentEditor } from './project-dossier-editors';
import type { DossierCommentAllocation } from './project-dossier-model';
import s from './project-dossier.module.css';

export function ProjectDocumentsPanel({ projectId, projectVersion, documents, attachments, users, canAdd, closed }: {
  projectId: string; projectVersion: string; documents: WebRow[]; attachments: WebRow[]; users: WebRow[]; canAdd: boolean; closed: boolean;
}) {
  const names = new Map(users.map(user => [user.id, user.nome]));
  const rows = [...documents.map(document => ({ ...document, source: 'documents' })), ...attachments.map(document => ({ ...document, source: 'docs' }))] as WebRow[];
  return <section className="panel" data-project-documents><div className="panel-header"><h2>Documentos e anexos <span className="inline-count">{rows.length}</span></h2></div>
    {closed && <div className={s.readonly}><p className="notice">Este projeto está encerrado. Os documentos permanecem disponíveis para consulta.</p></div>}
    {canAdd && !closed && <ProjectAttachmentEditor projectId={projectId} projectVersion={projectVersion} />}
    {!rows.length ? <Empty title="Nenhum documento vinculado" detail="Os documentos e anexos disponíveis neste projeto serão exibidos aqui." icon="file" />
      : rows.map(document => <div className="document-row" key={`${document.source}:${document.id}`} data-project-document={document.id}>
        <span className="document-icon"><Icon name="file" size={20} /></span><div className="document-copy"><h3 className={s.documentTitle}>{document.nome || display(document.tipo_documento) || 'Documento do projeto'}</h3>
          <p>{document.source === 'docs' ? document.visivel_cliente === false ? 'Anexo interno' : 'Anexo' : 'Documento'} · {date(document.created_at)}{document.descricao ? ` · ${document.descricao}` : ''}</p>
          {document.source === 'docs' && <div className={s.documentMeta}>{document.status && <Status value={document.status === 'Vencido' ? 'atrasado' : document.status === 'No prazo' ? 'ativo' : document.status} label={document.status} />}
            {document.data_vencimento && <span>Vencimento: {date(document.data_vencimento)}</span>}{document.created_by && <span>Por {names.get(document.created_by) || 'Autor registrado'}</span>}
            {document.tipo_arquivo && <span>{({ 'application/pdf': 'PDF', 'image/jpeg': 'JPEG', 'image/png': 'PNG' } as Record<string, string>)[document.tipo_arquivo] || document.tipo_arquivo}</span>}</div>}
        </div>{document.arquivo_url ? <a className="button small secondary" href={`/api/web/documents/${document.id}${document.source === 'docs' ? '?source=docs' : ''}`} target="_blank" rel="noopener noreferrer" aria-label={`Abrir ${document.nome || 'documento do projeto'}`}><Icon name="download" size={14} />Abrir</a> : <span className="panel-caption">Arquivo indisponível</span>}
      </div>)}
  </section>;
}

export function ProjectHistoryPanel({ projectId, projectVersion, comments, stages, cells, users, allocations, canAdd, closed }: {
  projectId: string; projectVersion: string; comments: WebRow[]; stages: WebRow[]; cells: WebRow[]; users: WebRow[];
  allocations: WebRow[]; canAdd: boolean; closed: boolean;
}) {
  const cellNames = new Map(cells.map(cell => [cell.id, cell.nome])), userNames = new Map(users.map(user => [user.id, user.nome]));
  const choices: DossierCommentAllocation[] = allocations.filter(allocation => allocation.projeto_id === projectId && !allocation.retirada).map(allocation => ({
    id: allocation.id, projeto_id: allocation.projeto_id, celula_id: allocation.celula_id, updated_at: allocation.updated_at,
    retirada: allocation.retirada, visibilidade: allocation.visibilidade, name: cellNames.get(allocation.celula_id) || 'Célula do projeto',
  }));
  return <div className="two-columns"><section className="panel" data-project-comments><div className="panel-header"><h2>Comentários do projeto <span className="inline-count">{comments.length}</span></h2></div>
    {closed && <div className={s.readonly}><p className="notice">Este projeto está encerrado. Os comentários permanecem disponíveis para consulta.</p></div>}
    {canAdd && !closed && <ProjectCommentEditor projectId={projectId} projectVersion={projectVersion} allocations={choices} />}
    {comments.length ? <div className="activity-list">{[...comments].reverse().map(comment => <div className="activity-item" key={comment.id} data-project-comment={comment.id}><span className="activity-icon"><Icon name="users" size={16} /></span><div><h3>{userNames.get(comment.cadastrado_por_id) || 'Autor registrado'} · {cellNames.get(comment.celula_id) || 'Projeto'}</h3><p className={s.commentText}>{comment.evento}</p><p>{date(comment.created_at, true)}</p></div></div>)}</div>
      : <Empty title="Sem comentários" detail="Os comentários registrados pela equipe serão reunidos aqui." icon="users" />}
  </section><section className="panel"><div className="panel-header"><h2>Aprovações das etapas</h2></div>{stages.length ? <div className="activity-list">{stages.map(stage => <div className="activity-item" key={stage.id}><span className="activity-icon"><Icon name="check" size={16} /></span><div><h3>{cellNames.get(stage.celula_origem_id) || 'Etapa da célula'}</h3><Status value={stage.status} /><p style={{ marginTop: 7 }}>{userNames.get(stage.aprovado_por_id) || userNames.get(stage.aprovador_id) || 'Aprovador não definido'}{stage.data_aprovacao ? ` · ${date(stage.data_aprovacao)}` : ''}</p></div></div>)}</div> : <Empty title="Nenhuma etapa definida" detail="As aprovações são definidas nos modelos do roteiro de execução." icon="check" />}</section></div>;
}
