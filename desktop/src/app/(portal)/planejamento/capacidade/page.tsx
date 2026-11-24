import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { CAPACITY_READ_SCOPES, capacityFiltersSchema } from '@/server/web/capacity-policy';
import { createCapacityData } from '@/server/web/capacity-data';
import { listGanttProjects } from '@/server/web/gantt-data';
import { calendarDay, isoCalendarDay, saoPauloDay } from '@/server/web/gantt';
import { scheduleId } from '@/server/web/project-schedule-policy';
import { CapacityPlanner } from '@/components/web/capacity-planner';
import { PcpNavigation } from '@/components/web/pcp-navigation';
import { Empty, PageHeading, Pagination } from '@/components/web/ui';

export default async function Capacidade({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams, session = await requireWebUser(CAPACITY_READ_SCOPES);
  const value = (key: string) => typeof params[key] === 'string' ? params[key] as string : undefined;
  const projectId = scheduleId(params.project) ?? null;
  const today = isoCalendarDay(saoPauloDay(new Date())!);
  const checked = capacityFiltersSchema.safeParse({ start: value('start') ?? today, days: value('days') ? Number(value('days')) : 14, project_id: projectId });
  const filters = checked.success ? checked.data : { start: today, days: 14 as const, project_id: projectId };
  const [snapshot, projects] = await Promise.all([
    createCapacityData(session.client, session.sso?.capabilities).getCapacitySnapshot(filters),
    listGanttProjects(value('q'), value('page')),
  ]);
  const query = new URLSearchParams({ start: filters.start, days: String(filters.days) });
  if (projectId) query.set('project', projectId);
  const initialAllocation = scheduleId(params.allocation);
  if (initialAllocation) query.set('allocation', initialAllocation);
  const destination = `/planejamento/capacidade?${query}`;
  const project = snapshot.project_plan?.projects.find(item => item.id === projectId);
  const canManage = ['administrador', 'padr_o'].includes(session.profile.perfil) && hasWebCapability(session, 'em.planning.manage');
  return <><PageHeading eyebrow="PCP · RECURSOS DA OFICINA" title="Capacidade de pessoas e máquinas"
    description="Cadastre os recursos da oficina e distribua as horas de cada etapa por dia. O mapa reúne as reservas de todos os projetos e células para mostrar a carga compartilhada."
    actions={<a className="button secondary" href="/cronograma?view=gantt">Gantt e prazos</a>} />
    <PcpNavigation active="capacity" />
    {(!checked.success || params.project && !projectId) && <p className="notice" role="status">Algum filtro informado é inválido. Usando um período válido; selecione o projeto desejado abaixo.</p>}
    <section className="panel"><div className="panel-header"><div><h2>Período de capacidade</h2><p>Escolher um projeto define as etapas que você pode reservar. O mapa mantém as reservas dos demais projetos.</p></div></div>
      <form className="filters" action="/planejamento/capacidade"><label>Primeiro dia<input type="date" name="start" aria-label="Primeiro dia da capacidade" min="1900-01-01" max={isoCalendarDay(calendarDay('2200-12-31')! - filters.days + 1)} required defaultValue={filters.start} /></label>
        <label>Período<select name="days" aria-label="Período da capacidade" defaultValue={filters.days}><option value={7}>7 dias</option><option value={14}>14 dias</option><option value={28}>28 dias</option></select></label>
        {projectId && <input type="hidden" name="project" value={projectId} />}<button className="button secondary">Consultar período</button><a className="button secondary" href={`/planejamento/capacidade?days=${filters.days}${projectId ? `&project=${projectId}` : ''}`}>Hoje</a>
      </form>
    </section>
    {project && <div className="heading-actions" style={{ marginBlock: 16 }}><strong>{project.numero ? `OS ${project.numero}` : project.nome || 'Projeto sem OS'}</strong><a className="button small secondary" href={`/cronograma?view=gantt&scope=project&project=${project.id}`}>Gantt do projeto</a><a className="button small secondary" href={`/projetos/${project.id}?tab=planejamento`}>Planejamento do projeto</a></div>}
    <details className="panel" open={!!value('q') || !!value('page')}><summary style={{ padding: 18, cursor: 'pointer' }}>{project ? 'Trocar projeto para planejar reservas' : 'Selecionar projeto para planejar reservas'}</summary>
      <form action="/planejamento/capacidade" className="filters"><input type="hidden" name="start" value={filters.start} /><input type="hidden" name="days" value={filters.days} /><input name="q" aria-label="Pesquisar projeto para capacidade" defaultValue={value('q')} maxLength={100} placeholder="Pesquisar OS ou nome do projeto" /><button className="button secondary">Pesquisar</button></form>
      {projects.items.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Projeto / OS</th><th>Nome</th><th>Selecionar</th></tr></thead><tbody>{projects.items.map(item => <tr key={item.id}><td>{item.numero ? `OS ${item.numero}` : 'Projeto sem OS'}</td><td>{item.nome || 'Não informado'}</td><td><a className="text-link" href={`/planejamento/capacidade?start=${filters.start}&days=${filters.days}&project=${item.id}`}>Planejar reservas</a></td></tr>)}</tbody></table></div> : <Empty title="Nenhum projeto encontrado" detail="Ajuste a pesquisa para escolher as etapas que receberão as reservas." icon="search" />}
      <Pagination page={projects.page} pageSize={projects.page_size} total={projects.total} base="/planejamento/capacidade" filters={{ start: filters.start, days: String(filters.days), q: value('q') }} />
    </details>
    <CapacityPlanner key={`${snapshot.as_of}:${destination}`} snapshot={snapshot} canManage={canManage} destination={destination} initialAllocation={initialAllocation} />
  </>;
}
