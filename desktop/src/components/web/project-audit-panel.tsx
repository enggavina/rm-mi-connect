import type { ProjectAuditEvent, ProjectAuditKind, ProjectAuditPage } from '../../server/web/project-audit-data';
import type { WebRow } from '../../server/web/data';
import { date, display, Empty } from './ui';
import { Icon } from './icons';
import s from './project-audit.module.css';

const actions: Record<string, string> = {
  allocation_created: 'Célula alocada no projeto', allocation_changed: 'Planejamento da célula alterado', route_initialized: 'Roteiro próprio criado a partir do tipo de equipamento',
  queue_changed: 'Fila da célula atualizada', route_order_changed: 'Ordem do roteiro alterada',
  allocation_set_visibility: 'Disponibilidade da célula alterada', allocation_retire: 'Célula retirada do planejamento',
  allocation_restore: 'Célula restaurada no planejamento', allocation_status_changed: 'Status da célula alterado',
  form_links_changed: 'Vínculos de formulários alterados', photo_selection_changed: 'Seleção de foto para relatório alterada',
  photo_add: 'Foto obrigatória adicionada ao planejamento', photo_tag: 'Tag da foto alterada',
  photo_retire: 'Foto obrigatória retirada do planejamento', photo_restore: 'Foto obrigatória restaurada', photo_captured: 'Foto registrada', receiving_photos_recorded: 'Fotos registradas no recebimento',
  form_submitted: 'Formulário enviado', form_corrected: 'Correções de formulário enviadas', form_reviewed: 'Formulário avaliado',
  form_reviewer_changed: 'Avaliador padrão do formulário alterado', form_record_reviewer_changed: 'Avaliador do registro de formulário alterado', stage_rule_create: 'Regra de aprovação criada',
  stage_rule_replace: 'Regra de aprovação substituída', stage_rule_retire: 'Regra de aprovação retirada', stage_rule_restore: 'Regra de aprovação restaurada',
  stage_liberar: 'Etapa liberada', stage_retornar: 'Etapa retornada', stage_aprovar: 'Etapa aprovada',
  stage_aprovado: 'Aprovação de etapa registrada', stage_reprovado: 'Retorno de etapa registrado', stage_nulo: 'Liberação de etapa registrada',
};
const labels: Record<string, string> = {
  data_inicio: 'Início previsto', data_limite: 'Prazo da célula', bloqueada: 'Bloqueio de execução', motivo_bloqueio: 'Motivo do bloqueio',
  motivo_atraso: 'Motivo do atraso', observacao: 'Observação', visibilidade: 'Visível no mobile', prioridade: 'Prioridade',
  indice: 'Ordem no roteiro', posicao: 'Posição na fila', horas_previstas: 'Horas previstas', horas_realizadas: 'Horas realizadas',
  responsavel_id: 'Responsável', status: 'Status', forms_ids: 'Formulários vinculados', retirada: 'Retirada do planejamento',
  selecao_relatorio: 'Selecionada para relatório', titulo: 'Título da foto', categoria_foto: 'Tipo de foto', tag: 'Tag', lixeira: 'Foto retirada',
  captured: 'Foto registrada', form_id: 'Formulário', avaliador_user_id: 'Avaliador', celula_destino_id: 'Célula de destino',
  status_cel_proj: 'Status de liberação', bloquear_avanco_sem_aprov: 'Exige aprovação para avançar',
  aprovadores_ids: 'Aprovadores da origem', aprovadores_retorno_ids: 'Aprovadores do destino', ativo: 'Regra ativa',
  tipo_equipamento_id: 'Tipo de equipamento de origem', route_cell_count: 'Células copiadas do modelo', captured_photo_count: 'Fotos registradas',
};
type Names = { users?: WebRow[]; cells?: WebRow[]; forms?: WebRow[] };
export function projectAuditValue(field: string, value: unknown, names: Names = {}): string {
  if (value == null || value === '') return 'Não informado';
  if (typeof value === 'boolean') return value ? 'Sim' : 'Não';
  if (Array.isArray(value)) return value.length ? value.map(item => projectAuditValue(field, item, names)).join(', ') : 'Nenhum';
  if (field === 'data_inicio' || field === 'data_limite') return date(value, true);
  const source = ['forms_ids', 'form_id'].includes(field) ? names.forms
    : field === 'celula_destino_id' ? names.cells : ['responsavel_id', 'avaliador_user_id', 'aprovadores_ids', 'aprovadores_retorno_ids'].includes(field) ? names.users : undefined;
  if (source) {
    const row = source.find(item => item.id === value);
    if (row) return row.nome || row.titulo || row.title || String(value);
  }
  return display(value);
}

function AuditItem({ item, names }: { item: ProjectAuditEvent; names: Names }) {
  const links: Record<string, string | undefined> = {
    form_submitted: `/formularios/${item.entity_id}`, form_corrected: `/formularios/${item.entity_id}`, form_reviewed: `/formularios/${item.entity_id}`, form_record_reviewer_changed: `/formularios/${item.entity_id}`,
  };
  return <article className={s.item} data-project-audit-event={item.id}>
    <div className={s.heading}><span className={s.icon}><Icon name={item.topic === 'photos' ? 'image' : item.topic === 'forms' ? 'clipboard' : 'clock'} size={17} /></span>
      <div><h3>{actions[item.action] || display(item.action)}</h3><p>{item.cell_name || (item.celula_id ? 'Célula histórica' : 'Projeto')} · {date(item.occurred_at, true)}</p></div></div>
    <p className={s.meta}>{item.actor_name || 'Autor não identificado no registro'} · {item.source === 'mobile' ? 'Aplicativo mobile' : item.source === 'web' ? 'Portal web' : 'Registro preservado'}</p>
    <dl className={s.changes}>{item.changes.map(change => <div key={change.field}><dt>{labels[change.field] || display(change.field)}</dt><dd>
      <span><small>Anterior</small>{item.prior_evidence ? projectAuditValue(change.field, change.before, names) : 'Sem evidência anterior neste registro'}</span>
      <span><small>Novo</small>{projectAuditValue(change.field, change.after, names)}</span>
    </dd></div>)}</dl>
    {item.reason && <p className={s.reason}><strong>Justificativa:</strong> {item.reason}</p>}
    {links[item.action] && <a className="text-link" href={links[item.action]}>Consultar formulário</a>}
  </article>;
}

export function ProjectAuditPanel({ projectId, kind, data, names = {} }: {
  projectId: string; kind: ProjectAuditKind; data: ProjectAuditPage | null; names?: Names;
}) {
  const title = kind === 'cells' ? 'Histórico de alterações das células' : 'Histórico operacional';
  const pageCount = data ? Math.max(1, Math.ceil(data.total / 25)) : 1;
  const href = (page: number) => `/projetos/${projectId}?${new URLSearchParams({ tab: kind === 'cells' ? 'planejamento' : 'historico', [kind === 'cells' ? 'cellAuditPage' : 'auditPage']: String(page) })}#${kind === 'cells' ? 'historico-celulas' : 'historico-operacional'}`;
  return <section className="panel" id={kind === 'cells' ? 'historico-celulas' : 'historico-operacional'} aria-label={title} data-project-audit={kind}>
    <div className="panel-header"><div><h2>{title}</h2><p>{kind === 'cells' ? 'Alterações no vínculo entre este projeto e suas células, incluindo a fila de planejamento.' : 'Ações registradas em fotos, formulários e aprovações deste projeto.'}</p></div><span className="count">{data?.total ?? '—'}</span></div>
    <p className={s.note}>Consulta dos registros já preservados pelo sistema. Alterações antigas sem comprovante detalhado podem não aparecer; valores e autores ausentes não são reconstruídos. Os nomes exibidos são os cadastros atuais.</p>
    {!data ? <p className={`notice ${s.error}`} role="status">Não foi possível carregar este histórico. Recarregue a página para tentar novamente.</p>
      : !data.items.length ? <Empty title="Nenhuma ação registrada para esta consulta" detail="Os comentários da equipe permanecem na aba Comentários." icon="clock" />
        : <div className={s.list}>{data.items.map(item => <AuditItem key={item.id} item={item} names={names} />)}</div>}
    {data && data.total > 0 && <nav className={s.pagination} aria-label={`Paginação de ${title.toLowerCase()}`}><span>{data.total.toLocaleString('pt-BR')} ações · Página {data.page} de {pageCount}</span><div>{data.page > 1 && <a className="button small secondary" href={href(data.page - 1)}>Anterior</a>}{data.page < pageCount && <a className="button small secondary" href={href(data.page + 1)}>Próxima</a>}</div></nav>}
  </section>;
}
