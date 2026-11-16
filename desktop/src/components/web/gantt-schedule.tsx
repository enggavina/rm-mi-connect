import { getGanttSnapshot, listGanttProjects } from '@/server/web/gantt-data';
import { getPcpChoices } from '@/server/web/pcp-data';
import { scheduleId } from '@/server/web/project-schedule-policy';
import { Pagination, Empty } from './ui';
import { GanttPlanner, type GanttScope } from './gantt-planner';
import s from './gantt-planner.module.css';

export async function GanttSchedule({ params, canProjects, canManage }: {
  params: Record<string, string | string[] | undefined>; canProjects: boolean; canManage: boolean;
}) {
  const value = (key: string) => typeof params[key] === 'string' ? params[key] as string : undefined;
  const scope: GanttScope = value('scope') === 'general' ? 'general' : value('scope') === 'project' || value('project') ? 'project' : value('scope') === 'cell' || value('cell') ? 'cell' : 'general';
  const projectId = scope === 'project' && canProjects ? scheduleId(params.project) : undefined;
  const cellId = scope === 'cell' ? scheduleId(params.cell) : undefined;
  const includeClosed = scope === 'project' || value('closed') === 'yes';
  const nav = <nav className={s.scopeNav} aria-label="Escopo do Gantt">
    <a href="/cronograma?view=gantt&scope=general" aria-current={scope === 'general' ? 'page' : undefined}>Gantt geral</a>
    <a href="/cronograma?view=gantt&scope=cell" aria-current={scope === 'cell' ? 'page' : undefined}>Gantt da célula</a>
    {canProjects && <a href="/cronograma?view=gantt&scope=project" aria-current={scope === 'project' ? 'page' : undefined}>Gantt do projeto</a>}
  </nav>;
  if (scope === 'project' && !canProjects) return <>{nav}<p className="notice">O Gantt por projeto exige acesso aos projetos. Você pode consultar as visões geral e por célula conforme suas permissões.</p></>;
  if (scope === 'project' && !projectId) {
    const projects = await listGanttProjects(value('q'), value('page'));
    return <>{nav}<section className="panel"><div className="panel-header"><div><h2>Escolher projeto</h2><p>Abra o roteiro completo para trabalhar prazos, dependências e referência do plano.</p></div></div>
      {value('project') && <p className="notice">O identificador do projeto é inválido. Selecione um projeto da lista.</p>}
      <form action="/cronograma" className="filters"><input type="hidden" name="view" value="gantt" /><input type="hidden" name="scope" value="project" /><input aria-label="Pesquisar projeto para Gantt" name="q" defaultValue={value('q')} maxLength={100} placeholder="Pesquisar OS ou nome do projeto" /><button className="button secondary">Pesquisar</button><a className="button secondary" href="/cronograma?view=gantt&scope=general">Voltar ao Gantt geral</a></form>
      {projects.items.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Projeto / OS</th><th>Nome</th><th>Abrir</th></tr></thead><tbody>{projects.items.map(project => <tr key={project.id}><td>{project.numero ? `OS ${project.numero}` : 'Projeto sem OS'}</td><td>{project.nome || 'Não informado'}</td><td><a className="text-link" href={`/cronograma?view=gantt&scope=project&project=${project.id}`}>Abrir Gantt</a></td></tr>)}</tbody></table></div> : <Empty title="Nenhum projeto encontrado" detail="Ajuste a pesquisa para abrir o cronograma." icon="calendar" />}
      <Pagination page={projects.page} pageSize={projects.page_size} total={projects.total} base="/cronograma" filters={{ view: 'gantt', scope: 'project', q: value('q') }} />
    </section></>;
  }
  const choices = scope === 'cell' ? await getPcpChoices() : null;
  const cellSelector = scope === 'cell' && <section className="panel"><div className="panel-content"><form action="/cronograma" className="filters" style={{ padding: 0 }}><input type="hidden" name="view" value="gantt" /><input type="hidden" name="scope" value="cell" /><select aria-label="Célula do Gantt" name="cell" defaultValue={cellId || ''} required><option value="">Selecione a célula</option>{choices?.cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select>{includeClosed && <input type="hidden" name="closed" value="yes" />}<button type="submit" className="button secondary">Abrir célula</button><a className="button secondary" href="/cronograma?view=gantt&scope=general">Voltar ao Gantt geral</a></form></div></section>;
  if (scope === 'cell' && !cellId) return <>{nav}{cellSelector}<p className="notice">Selecione uma célula para consultar todos os projetos alocados e ajustar seus prazos.</p></>;
  const snapshot = await getGanttSnapshot({ project_id: projectId ?? null, cell_id: cellId ?? null, include_closed: includeClosed });
  const query = new URLSearchParams({ view: 'gantt', scope });
  if (projectId) query.set('project', projectId);
  if (cellId) query.set('cell', cellId);
  if (includeClosed && scope !== 'project') query.set('closed', 'yes');
  for (const key of ['start', 'days', 'allocation']) if (value(key)) query.set(key, value(key)!);
  const destination = `/cronograma?${query}`;
  const toggle = new URLSearchParams(query); if (includeClosed) toggle.delete('closed'); else toggle.set('closed', 'yes');
  const key = [scope, projectId, cellId, snapshot.as_of].join(':');
  return <>{nav}{cellSelector}<div className="heading-actions" style={{ marginBottom: 16 }}>
    {scope !== 'project' && <a className="button small secondary" href={`/cronograma?${toggle}`}>{includeClosed ? 'Consultar somente trabalhos abertos' : 'Incluir etapas finalizadas e projetos encerrados'}</a>}
    {projectId && <><a className="button small secondary" href="/cronograma?view=gantt&scope=project">Trocar projeto</a><a className="button small secondary" href={`/cronograma?view=project&project=${projectId}`}>Roteiro e registros das etapas</a><a className="button small secondary" href={`/projetos/${projectId}`}>Informações do projeto</a></>}
    {cellId && <a className="button small secondary" href={`/planejamento/fila?cell=${cellId}`}>Prioridades e fila da célula</a>}
  </div><GanttPlanner key={key} snapshot={snapshot} scope={scope} canManage={canManage && canProjects} canProjects={canProjects} destination={destination} initialStart={value('start')} initialDays={value('days')} initialAllocation={scheduleId(params.allocation)} /></>;
}
