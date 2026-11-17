import { requireWebUser } from '@/server/web/auth';
import { createExecutionData } from '@/server/web/execution-data';
import { EXECUTION_READ_SCOPES } from '@/server/web/execution-policy';
import { createPcpData, getPcpChoices } from '@/server/web/pcp-data';
import { scheduleId } from '@/server/web/project-schedule-policy';
import { executionQuality, qualityLabels } from '@/server/web/quality-policy';
import { PcpNavigation } from '@/components/web/pcp-navigation';
import { PageHeading, Stat, Empty, Pagination, date } from '@/components/web/ui';
import { pageNumber } from '@/server/web/policy';

export default async function Qualidade({searchParams}: {searchParams:Promise<Record<string,string|string[]|undefined>>}) {
  const query = await searchParams, access = await requireWebUser(EXECUTION_READ_SCOPES);
  const cell = scheduleId(query.cell) ?? null, page = pageNumber(typeof query.page === 'string' ? query.page : undefined);
  const [snapshot, receiving, choices] = await Promise.all([
    createExecutionData(access.client,access.sso?.capabilities).getExecutionSnapshot({project_id:null,cell_id:cell,session_id:null,include_closed:false}),
    createPcpData(access.client,access.sso?.capabilities).listReceiving(), getPcpChoices(),
  ]);
  const quality = executionQuality(snapshot), size = 50;
  const percent = (value:number|null) => value === null ? 'Sem base' : `${value.toLocaleString('pt-BR')}%`;
  return <><PageHeading eyebrow="PCP · CONFIABILIDADE" title="Qualidade dos dados" description="Identifique etapas que precisam de planejamento ou conferência e pendências de identificação dos projetos." actions={<a className="button secondary" href="/planejamento/execucao">Conferir apontamentos</a>} />
    <PcpNavigation active="quality" />
    <section className="panel"><div className="panel-header"><h2>Identificação dos projetos</h2><a href="/recebimentos" className="text-link">Conferir recebimentos</a></div><div className="panel-content"><p>Todos os projetos ativos com pendência de identificação ou alocação, independentemente do filtro de célula abaixo. Um projeto pode ter mais de uma pendência.</p>
      <div className="stats-grid"><Stat label="Sem OS" value={receiving.summary.without_number} icon="folder" /><Stat label="Sem tipo" value={receiving.summary.without_type} icon="settings" /><Stat label="Sem célula ativa" value={receiving.summary.without_allocation} icon="board" /><Stat label="Tipo legado para revisão" value={receiving.summary.legacy_type_locked} icon="clipboard" /></div>
    </div></section>
    <section className="panel" style={{marginTop:24}}><div className="panel-header"><h2>Prazos e registros de execução</h2><span>Leitura de {date(snapshot.as_of,true)}</span></div>
      <form className="filters" action="/planejamento/qualidade"><label htmlFor="quality-cell">Célula</label><select id="quality-cell" name="cell" defaultValue={cell ?? ''}><option value="">Todas as células autorizadas</option>{choices.cells.map(c=><option key={c.id} value={c.id}>{c.nome || 'Célula'}</option>)}</select><button className="button secondary">Consultar</button><a className="button ghost" href="/planejamento/qualidade">Limpar</a></form>
      {!quality ? <div className="panel-content"><p role="alert" className="notice">A consulta excedeu o limite de leitura completa. Selecione uma célula. Nenhum percentual foi calculado sobre dados parciais.</p></div> : <>
        <div className="panel-content"><p>{quality.total} etapas ativas, incluindo as ocultas no mobile. Etapas retiradas, encerradas ou de projetos encerrados não compõem os indicadores.</p>
          <div className="stats-grid"><Stat label="Com início e prazo válidos" value={percent(quality.datedPercent)} icon="calendar" detail={`${quality.dated} de ${quality.total} etapas`} /><Stat label="Com apontamento recebido" value={percent(quality.receivedPercent)} icon="clipboard" detail={`${quality.received} de ${quality.total} etapas`} /><Stat label="Etapas com revisão pendente" value={quality.review} icon="clock" /></div>
          <p className="notice">Os percentuais medem cobertura dos dados, não avanço físico do projeto. Ausência de apontamento não comprova parada; o banco não conhece registros ainda offline. Nenhuma data, hora ou situação é corrigida automaticamente.</p>
        </div>
        {quality.rows.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Projeto / célula</th><th>Conferir</th><th>Ações</th></tr></thead><tbody>{quality.rows.slice((page-1)*size,page*size).map(({allocation:a,reasons})=><tr key={a.id}><td><a className="table-title" href={`/projetos/${a.project_id}`}>{a.numero_projeto || 'Recebimento sem OS'}</a><span className="table-subtitle">{a.cell_name || 'Célula sem nome'} · {a.cliente_nome || 'Cliente não informado'}</span></td><td>{reasons.map(reason=><div key={reason}>{qualityLabels[reason]}</div>)}</td><td><a href={`/cronograma?view=gantt&scope=project&project=${a.project_id}`} className="text-link">Planejar prazos</a><br/><a href={`/planejamento/execucao?project=${a.project_id}&cell=${a.cell_id}`} className="text-link">Conferir execução</a></td></tr>)}</tbody></table></div> : <Empty title="Nenhuma pendência nesta leitura" detail="Os campos avaliados estão preenchidos; isso não substitui a conferência da equipe." icon="check" />}
        <Pagination page={page} pageSize={size} total={quality.rows.length} base="/planejamento/qualidade" filters={{cell:cell ?? undefined}} />
      </>}
    </section>
  </>;
}
