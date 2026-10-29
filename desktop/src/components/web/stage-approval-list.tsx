import type { StageApprovalListItem } from '@/server/web/stage-approval-data';
import { Icon } from './icons';
import { Empty, Status, date, display } from './ui';
import { stageActionLabels } from './stage-approval-model';
import s from './stage-approval.module.css';

export function StageApprovalTable({ items, canProjects, hideProject = false }: {
  items: StageApprovalListItem[]; canProjects: boolean; hideProject?: boolean;
}) {
  if (!items.length) return <Empty title="Nenhuma etapa encontrada" detail="Ajuste os filtros ou consulte outro projeto. As etapas são definidas pelo roteiro de execução." icon="check" />;
  return <div className="table-scroll"><table className="data-table"><thead><tr>{!hideProject && <th>Projeto / cliente</th>}<th>Origem e destino</th><th>Etapa</th><th>Estado da célula</th><th>Decisão</th><th className="table-action">Consultar</th></tr></thead><tbody>{items.map(item => <tr key={item.stage.id}>
    {!hideProject && <td>{canProjects && item.project ? <a href={`/projetos/${item.project.id}?tab=aprovacoes`} className="table-title">{item.project.numero ? `OS ${item.project.numero}` : item.project.nome || 'Projeto sem OS'}</a> : <span className="table-title">{item.project?.numero ? `OS ${item.project.numero}` : item.project?.nome || 'Projeto não disponível'}</span>}<span className="table-subtitle">{item.project?.cliente_nome || item.project?.cliente_nome_exportacao || 'Cliente não informado'}</span></td>}
    <td><span className="table-title">{item.origin?.nome || 'Origem não disponível'}</span><span className="table-subtitle">Para {item.destination?.nome || 'destino não definido'}</span></td>
    <td><span className="table-title">{item.stage.status_cel_proj === 'retornado' ? 'Retorno' : 'Liberação'}</span><span className="table-subtitle">{display(item.stage.status_cel_proj)}</span></td>
    <td><Status value={item.allocation?.status} label={!item.allocation ? 'Sem alocação de origem' : undefined} /></td>
    <td><Status value={item.stage.status ?? 'nulo'} />{item.available_actions.length ? <div className={s.tableNote}>{item.available_actions.map(action => stageActionLabels[action]).join(' ou ')} disponível</div> : item.action_reason ? <div className={s.tableNote}>{item.action_reason}</div> : item.stage.data_aprovacao ? <div className={s.tableNote}>{date(item.stage.data_aprovacao, true)}</div> : null}</td>
    <td className="table-action"><a href={`/aprovacoes/${item.stage.id}`} aria-label={`Consultar etapa de ${item.origin?.nome || 'célula'}`}><Icon name="arrow" size={15} /></a></td>
  </tr>)}</tbody></table></div>;
}
