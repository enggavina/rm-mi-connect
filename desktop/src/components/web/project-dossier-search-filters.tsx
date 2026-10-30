import type { ProjectCommentFilters, ProjectCommentPage, ProjectDocumentFilters, ProjectDocumentPage } from '@/server/web/project-dossier-search-policy';
import { dossierSearchHref, dossierSearchNames, type DossierSearchKind } from './project-dossier-search-model';
import { Icon } from './icons';
import s from './project-dossier.module.css';

type Filters = Omit<ProjectCommentFilters, 'page'> | Omit<ProjectDocumentFilters, 'page'>;
type Facets = ProjectCommentPage['facets'] | ProjectDocumentPage['facets'];
const authorLabel = (person: { nome: string | null; matricula?: string | null }) => `${person.nome || 'Autor registrado'}${person.matricula ? ` · ${person.matricula}` : ''}`;

export function ProjectDossierFilters({ projectId, kind, filters, facets, error }: { projectId: string; kind: DossierSearchKind; filters: Filters; facets: Facets; error?: string }) {
  const names = dossierSearchNames(kind), comment = kind === 'comments';
  const typed = filters as Record<string, string | null>, author = typed.author_id ?? '', cell = typed.cell_id ?? '';
  const cells = 'cells' in facets ? facets.cells : [], statuses = 'statuses' in facets ? facets.statuses : [];
  return <div className={s.searchArea} data-dossier-filters={kind}>
    {error && <p className="notice error" role="alert">{error}</p>}
    <form action={`/projetos/${projectId}`} method="get" className={s.searchForm}>
      <input type="hidden" name="tab" value={comment ? 'historico' : 'documentos'} />
      <div className={`field ${s.searchWide}`}><label htmlFor={`${kind}-query`}>{comment ? 'Buscar nos comentários' : 'Buscar nos documentos'}<input id={`${kind}-query`} name={names.search} type="search" defaultValue={typed.search ?? ''} maxLength={200} placeholder={comment ? 'Texto do comentário' : 'Título ou observação'} /></label></div>
      <div className="field"><label htmlFor={`${kind}-author`}>Autor<select id={`${kind}-author`} name={names.author_id} defaultValue={author}><option value="">Todos os autores</option>{author && !facets.authors.some(item => item.id === author) && <option value={author}>Autor não localizado neste projeto</option>}{facets.authors.map(item => <option value={item.id} key={item.id}>{authorLabel(item)}</option>)}</select></label></div>
      {comment ? <div className="field"><label htmlFor="comments-cell">Célula destinatária<select id="comments-cell" name={dossierSearchNames('comments').cell_id} defaultValue={cell}><option value="">Todas as células</option>{cell && !cells.some(item => item.id === cell) && <option value={cell}>Célula não localizada neste projeto</option>}{cells.map(item => <option value={item.id} key={item.id}>{item.nome || 'Célula histórica'}</option>)}</select></label></div> : <>
        <div className="field"><label htmlFor="documents-source">Origem<select id="documents-source" name={dossierSearchNames('documents').source} defaultValue={typed.source ?? 'all'}><option value="all">Documentos e anexos</option>{typed.source && !['all', 'documents', 'docs'].includes(typed.source) && <option value={typed.source}>Origem inválida no endereço</option>}<option value="documents">Documentos gerados</option><option value="docs">Anexos do projeto</option></select></label></div>
        <div className="field"><label htmlFor="documents-status">Situação documental<select id="documents-status" name={dossierSearchNames('documents').status} defaultValue={typed.status ?? 'all'}><option value="all">Todas as situações</option>{typed.status && typed.status !== 'all' && !statuses.some(item => item.value === typed.status) && <option value={typed.status}>Situação sem registros neste projeto</option>}{statuses.map(item => <option value={item.value} key={item.value}>{item.label}</option>)}</select></label></div>
      </>}
      <div className="field"><label htmlFor={`${kind}-from`}>Registrado de<input id={`${kind}-from`} name={names.from_date} type="date" defaultValue={typed.from_date ?? ''} /></label></div>
      <div className="field"><label htmlFor={`${kind}-to`}>Registrado até<input id={`${kind}-to`} name={names.to_date} type="date" defaultValue={typed.to_date ?? ''} /></label></div>
      <p className={s.searchHint}>O período considera a data de registro, inclusive os dias inicial e final, no horário de Brasília.</p>
      <div className={s.searchActions}><a className="button small secondary" href={dossierSearchHref(projectId, kind, comment ? { search: '', author_id: null, cell_id: null, from_date: null, to_date: null } : { search: '', author_id: null, source: 'all', status: 'all', from_date: null, to_date: null })}>Limpar filtros</a><button className="button small secondary" type="submit"><Icon name="search" size={14} />{comment ? 'Filtrar comentários' : 'Filtrar documentos'}</button></div>
    </form>
  </div>;
}

export function ProjectDossierPagination({ projectId, kind, page, pageSize, total, unfilteredTotal, filters }: {
  projectId: string; kind: DossierSearchKind; page: number; pageSize: number; total: number; unfilteredTotal: number; filters: Filters;
}) {
  const pages = Math.max(1, Math.ceil(total / pageSize)), label = kind === 'comments' ? 'comentários' : 'documentos';
  return <nav className={`pagination ${s.searchPagination}`} aria-label={`Paginação de ${label}`}>
    <span>{total ? `${((page - 1) * pageSize + 1).toLocaleString('pt-BR')}–${Math.min(page * pageSize, total).toLocaleString('pt-BR')} de ${total.toLocaleString('pt-BR')}` : 'Nenhum resultado'}{unfilteredTotal !== total ? ` · ${unfilteredTotal.toLocaleString('pt-BR')} no projeto` : ''}</span>
    <div>{page > 1 ? <a className="button small secondary" href={dossierSearchHref(projectId, kind, filters, page - 1)} aria-label={`Página anterior de ${label}`}>Anterior</a> : <span className="button small secondary disabled" aria-disabled="true">Anterior</span>}<span className="page-number">{page} / {pages}</span>{page < pages ? <a className="button small secondary" href={dossierSearchHref(projectId, kind, filters, page + 1)} aria-label={`Página seguinte de ${label}`}>Próxima<Icon name="chevron" size={14} /></a> : <span className="button small secondary disabled" aria-disabled="true">Próxima</span>}</div>
  </nav>;
}
