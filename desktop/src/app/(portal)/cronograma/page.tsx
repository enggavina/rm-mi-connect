import Link from 'next/link';
import { listPlanning } from '@/server/web/data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { formatGanttDay, ganttBar, ganttWindow, GANTT_DAYS, isoCalendarDay } from '@/server/web/gantt';
import { Empty, PageHeading, Pagination, display } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function Cronograma({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const filters = Object.fromEntries(['q', 'cell', 'status', 'page'].map(key => [key, typeof params[key] === 'string' ? params[key] as string : undefined]));
  const window = ganttWindow(typeof params.start === 'string' ? params.start : undefined);
  const [data, session] = await Promise.all([listPlanning(filters), requireWebUser('em.planning.read')]);
  const canProjects = hasWebCapability(session, 'em.projects.read');
  const cells = new Map(data.cells.map(cell => [cell.id, cell.nome]));
  const periodFilters = { ...filters, start: window.isoStart };
  const periodHref = (start: number) => {
    const query = new URLSearchParams(Object.entries({ ...periodFilters, start: isoCalendarDay(start) }).filter((entry): entry is [string, string] => !!entry[1]));
    return `/cronograma?${query}`;
  };
  return <>
    <PageHeading eyebrow="PCP · PLANEJAMENTO E CONTROLE" title="Cronograma" description="Consulte os prazos planejados das células em uma janela de seis semanas." actions={<Link className="button secondary" href="/planejamento"><Icon name="board" size={16} />Ver planejamento</Link>} />
    {window.invalidStart && <p className="notice" role="status">A data informada é inválida. O período padrão está sendo exibido.</p>}
    <section className="panel">
      <div className="panel-header"><div><h2>{formatGanttDay(window.start)} — {formatGanttDay(window.end)}</h2><p>42 dias · Datas da oficina no horário de São Paulo</p></div><div className="heading-actions">
        <a className="button small secondary" href={periodHref(window.start - GANTT_DAYS)} aria-label="Ver seis semanas anteriores"><Icon name="back" size={14} />Anterior</a>
        <a className="button small secondary" href={periodHref(window.today - 14)}>Hoje</a>
        <a className="button small secondary" href={periodHref(window.start + GANTT_DAYS)} aria-label="Ver próximas seis semanas">Próximo<Icon name="arrow" size={14} /></a>
      </div></div>
      <form className="filters" action="/cronograma">
        <div className="search-field"><Icon name="search" size={16} /><input name="q" aria-label="Buscar OS ou projeto" defaultValue={filters.q} placeholder="Buscar OS ou projeto…" maxLength={100} /></div>
        <select name="cell" aria-label="Célula" defaultValue={filters.cell || ''}><option value="">Todas as células</option>{data.cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select>
        <select name="status" aria-label="Status da célula" defaultValue={filters.status || ''}><option value="">Todos os status</option>{data.statuses.map(status => <option key={status.id} value={status.option_key}>{status.bubble_display}</option>)}</select>
        <div className="field"><label htmlFor="gantt-start">Início do período</label><input id="gantt-start" name="start" type="date" defaultValue={window.isoStart} required /></div>
        <button type="submit" className="button secondary">Aplicar</button>
      </form>
      <div className="gantt-legend"><span><i className="legend-dot" />Planejado</span><span><i className="legend-dot red" />Prazo vencido</span><span><i className="legend-dot green" />Finalizado</span></div>
      {data.rows.length ? <div className="gantt-scroll" role="region" aria-label="Cronograma por célula, com rolagem horizontal" tabIndex={0}><div className="gantt" role="table" aria-label="Prazos das células dos projetos">
        <div className="gantt-head" role="row"><div role="columnheader">Projeto / célula</div><div className="gantt-axis" role="columnheader" aria-label="Seis semanas">{window.ticks.map(tick => <span key={tick}>{formatGanttDay(tick, true)}</span>)}</div></div>
        {data.rows.map(row => {
          const bar = ganttBar({ data_inicio: row.data_inicio, data_limite: row.data_limite, status: row.status }, window);
          const number = row.project?.numero || row.numero_projeto;
          const href = `/projetos/${row.projeto_id}?tab=planejamento`;
          const range = bar.kind === 'bar' ? `${formatGanttDay(bar.start)} a ${formatGanttDay(bar.end)}` : '';
          const state = bar.kind === 'bar' ? bar.complete ? 'Finalizado' : bar.overdue ? 'Prazo vencido' : display(row.status) : '';
          return <div className="gantt-row" role="row" key={row.id}>
            <div className="gantt-row-title" role="rowheader">{canProjects ? <Link href={href}>{number ? `OS ${String(number).trim()}` : 'Projeto sem OS'}</Link> : <span>{number ? `OS ${String(number).trim()}` : 'Projeto sem OS'}</span>}<small>{cells.get(row.celula_id) || 'Célula não informada'}</small><small>{display(row.status)}</small></div>
            <div className="gantt-track" role="cell">
              {bar.kind === 'bar' ? canProjects ? <Link href={href} className={`gantt-bar${bar.complete ? ' complete' : bar.overdue ? ' overdue' : ''}`} style={{ left: `${bar.left}%`, width: `${bar.width}%` }} title={`${range} · ${state}`} aria-label={`Planejamento: ${range}. ${state}. Abrir projeto.`}>{formatGanttDay(bar.start, true)} — {formatGanttDay(bar.end, true)}</Link> : <span className={`gantt-bar${bar.complete ? ' complete' : bar.overdue ? ' overdue' : ''}`} style={{ left: `${bar.left}%`, width: `${bar.width}%` }} title={`${range} · ${state}`}>{formatGanttDay(bar.start, true)} — {formatGanttDay(bar.end, true)}</span>
                : <span className="panel-caption" style={{ padding: '0 16px' }}>{bar.kind === 'missing' ? 'Sem datas planejadas' : bar.kind === 'invalid' ? 'Datas planejadas inválidas' : 'Fora do período'}</span>}
            </div>
          </div>;
        })}
      </div></div> : <Empty title="Nenhuma alocação encontrada" detail="Ajuste os filtros ou abra um projeto para planejar suas células." icon="calendar" />}
      <Pagination {...data} base="/cronograma" filters={periodFilters} />
    </section>
  </>;
}
