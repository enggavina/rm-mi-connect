import { getPlanningLoad } from '@/server/web/pcp-data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { PcpNavigation } from '@/components/web/pcp-navigation';
import { estimatedHours } from '@/components/web/pcp-model';
import { PageHeading, Stat, Empty, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import s from '@/components/web/pcp.module.css';

export default async function CargaPlanejada() {
  const [session, data] = await Promise.all([requireWebUser('em.planning.read'), getPlanningLoad()]);
  const total = data.cells.reduce((sum, cell) => sum + cell.open_allocations, 0);
  const estimated = data.cells.reduce((sum, cell) => sum + cell.estimated_allocations, 0);
  const withoutEstimate = data.cells.reduce((sum, cell) => sum + cell.unestimated_allocations, 0);
  const hours = estimated ? data.cells.reduce((sum, cell) => sum + Number(cell.planned_hours || 0), 0) : null;
  return <><a className="back-link" href="/planejamento"><Icon name="back" size={15} />Voltar ao planejamento</a>
    <PageHeading eyebrow="PCP · CARGA DA OFICINA" title="Carga planejada" description="Confira as alocações abertas e as estimativas de horas informadas em cada célula. Os indicadores incluem trabalhos que ainda estão ocultos no mobile." />
    <PcpNavigation active="load" canProjects={hasWebCapability(session, 'em.projects.read')} />
    <div className="stats-grid"><Stat label="Alocações abertas" value={total} icon="board" /><Stat label="Células com trabalho" value={data.cells.filter(cell => cell.open_allocations > 0).length} icon="users" /><Stat label="Horas previstas informadas" value={hours == null ? '—' : estimatedHours(hours)} detail={hours == null ? 'Sem estimativas de horas' : `${estimated} alocações com estimativa`} icon="clock" /><Stat label="Sem estimativa" value={withoutEstimate} detail="A carga está incompleta enquanto faltarem horas" icon="alert" accent /></div>
    <div className="notice">As horas somam as estimativas das alocações abertas. Não representam capacidade disponível, ocupação percentual ou horas distribuídas por dia.</div>
    <section className="panel"><div className="panel-header"><h2>Carga por célula</h2><span className="panel-caption">Situação em {date(data.as_of, true)}</span></div>
      {data.cells.length ? <div className="table-scroll"><table className={`data-table ${s.loadTable}`}><thead><tr><th>Célula</th><th>Abertas</th><th>Horas previstas</th><th>Sem estimativa</th><th>Horas realizadas</th><th>Visibilidade</th><th>Bloqueadas</th><th>Com prazo vencido</th><th className="table-action">Consultar</th></tr></thead><tbody>{data.cells.map(cell => <tr key={cell.id}><td><a href={`/planejamento/fila?cell=${cell.id}`} className="table-title">{cell.nome || 'Célula'}</a></td><td className="table-number">{cell.open_allocations}</td><td className="table-number">{cell.open_allocations === 0 ? 'Sem trabalhos abertos' : estimatedHours(cell.planned_hours == null ? null : Number(cell.planned_hours))}{cell.estimated_allocations > 0 && <span className="table-subtitle">{cell.estimated_allocations} com estimativa</span>}</td><td className="table-number">{cell.unestimated_allocations}</td><td className="table-number">{cell.realized_hours == null ? 'Sem registro' : estimatedHours(Number(cell.realized_hours))}</td><td><span className="table-subtitle">{cell.visible_allocations} visíveis · {cell.hidden_allocations} ocultas</span></td><td className="table-number">{cell.blocked_allocations}</td><td className="table-number">{cell.overdue_allocations}</td><td className="table-action"><a href={`/planejamento/fila?cell=${cell.id}`} aria-label={`Consultar fila de ${cell.nome}`}><Icon name="arrow" size={15} /></a></td></tr>)}</tbody></table></div> : <Empty title="Nenhuma célula disponível" detail="Cadastre as células da oficina para acompanhar suas alocações e estimativas." icon="board" />}
    </section>
  </>;
}
