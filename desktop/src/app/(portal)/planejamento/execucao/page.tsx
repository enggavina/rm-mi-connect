import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { EXECUTION_READ_SCOPES } from '@/server/web/execution-policy';
import { createExecutionData } from '@/server/web/execution-data';
import { listGanttCells, listGanttProjects } from '@/server/web/gantt-data';
import { scheduleId } from '@/server/web/project-schedule-policy';
import { ExecutionBoard } from '@/components/web/execution-board';
import { PcpNavigation } from '@/components/web/pcp-navigation';
import { Empty, PageHeading, Pagination } from '@/components/web/ui';

export default async function Execucao({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams, session = await requireWebUser(EXECUTION_READ_SCOPES);
  const value = (key: string) => typeof params[key] === 'string' ? params[key] as string : undefined;
  const projectId = scheduleId(params.project) ?? null, cellId = scheduleId(params.cell) ?? null, selectedSession = scheduleId(params.session) ?? null;
  const filters = { project_id: projectId, cell_id: cellId, session_id: selectedSession, include_closed: !!projectId || value('closed') === 'yes' };
  const [snapshot, cells, projects] = await Promise.all([
    createExecutionData(session.client, session.sso?.capabilities).getExecutionSnapshot(filters), listGanttCells(),
    listGanttProjects(value('q'), value('page')),
  ]);
  const query = new URLSearchParams();
  if (projectId) query.set('project', projectId); if (cellId) query.set('cell', cellId); if (selectedSession) query.set('session', selectedSession); if (filters.include_closed) query.set('closed', 'yes');
  const destination = `/planejamento/execucao${query.size ? `?${query}` : ''}`;
  const canManage = ['administrador', 'padr_o'].includes(session.profile.perfil) && hasWebCapability(session, 'em.planning.manage');
  return <><PageHeading eyebrow="PCP · EXECUÇÃO INFORMADA" title="Apontamentos da oficina"
    description="Consulte o trabalho informado pelos operadores, as pausas e os apontamentos que precisam de revisão. Horários do aplicativo e de recebimento ficam registrados separadamente."
    actions={<><a className="button secondary" href="/cronograma?view=gantt">Gantt e prazos</a><a className="button secondary" href="/planejamento/capacidade">Pessoas e máquinas</a></>} />
    <PcpNavigation active="execution" />
    {(['project', 'cell', 'session'] as const).some(field => value(field) && !scheduleId(params[field])) && <p className="notice">Algum identificador informado é inválido. Use os filtros para selecionar o contexto desejado.</p>}
    <section className="panel"><div className="panel-header"><div><h2>Contexto da oficina</h2><p>As situações sem apontamento recebido continuam como informação a confirmar. O servidor não conhece os registros que ainda estão offline em um aparelho.</p></div></div>
      <form className="filters" action="/planejamento/execucao"><select name="cell" aria-label="Célula dos apontamentos" defaultValue={cellId ?? ''}><option value="">Todas as células</option>{cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome || 'Célula'}</option>)}</select>
        {projectId && <input type="hidden" name="project" value={projectId} />}
        <label><input type="checkbox" name="closed" value="yes" defaultChecked={filters.include_closed} disabled={!!projectId} /> Incluir projetos encerrados e etapas retiradas</label>
        <button className="button secondary">Filtrar apontamentos</button><a className="button secondary" href="/planejamento/execucao">Limpar filtros</a>
        {projectId && <a className="button secondary" href={`/cronograma?view=gantt&scope=project&project=${projectId}`}>Gantt do projeto</a>}
      </form>
    </section>
    <details className="panel" open={!!value('q') || !!value('page')}><summary style={{ padding: 18, cursor: 'pointer' }}>{projectId ? 'Trocar projeto dos apontamentos' : 'Selecionar projeto dos apontamentos'}</summary>
      <form action="/planejamento/execucao" className="filters">{cellId && <input type="hidden" name="cell" value={cellId} />}<input name="q" aria-label="Pesquisar projeto dos apontamentos" defaultValue={value('q')} maxLength={100} placeholder="Pesquisar OS ou nome do projeto" /><button className="button secondary">Pesquisar</button></form>
      {projects.items.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Projeto / OS</th><th>Nome</th><th>Consultar</th></tr></thead><tbody>{projects.items.map(item => <tr key={item.id}><td>{item.numero ? `OS ${item.numero}` : 'Projeto sem OS'}</td><td>{item.nome || 'Não informado'}</td><td><a className="text-link" href={`/planejamento/execucao?project=${item.id}${cellId ? `&cell=${cellId}` : ''}`}>Ver apontamentos</a></td></tr>)}</tbody></table></div> : <Empty title="Nenhum projeto encontrado" detail="Ajuste a pesquisa para consultar os apontamentos do projeto." icon="search" />}
      <Pagination page={projects.page} pageSize={projects.page_size} total={projects.total} base="/planejamento/execucao" filters={{ cell: cellId ?? undefined, q: value('q') }} />
    </details>
    <ExecutionBoard key={`${snapshot.as_of}:${destination}`} snapshot={snapshot} canManage={canManage} destination={destination} />
  </>;
}
