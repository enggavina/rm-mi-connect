import { getCellQueue, getPcpChoices } from '@/server/web/pcp-data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { CellQueueEditor } from '@/components/web/pcp-queue-editor';
import { PcpNavigation } from '@/components/web/pcp-navigation';
import { PageHeading, Empty } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import s from '@/components/web/pcp.module.css';

export default async function FilaCelula({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams; const cellId = typeof query.cell === 'string' ? query.cell : '';
  const [session, choices, snapshot] = await Promise.all([requireWebUser('em.planning.read'), getPcpChoices(), cellId ? getCellQueue(cellId) : null]);
  const canProjects = hasWebCapability(session, 'em.projects.read');
  const canEdit = hasWebCapability(session, 'em.planning.manage') && ['administrador', 'padr_o'].includes(session.profile.perfil);
  return <><a className="back-link" href="/planejamento"><Icon name="back" size={15} />Voltar ao planejamento</a>
    <PageHeading eyebrow="PCP · SEQUÊNCIA DA OPERAÇÃO" title={snapshot ? `Fila · ${snapshot.cell.nome || 'Célula'}` : 'Fila da célula'} description="Escolha uma célula para conferir os trabalhos abertos, definir prioridades e organizar a sequência. Alocações ocultas no mobile também participam desta fila." />
    <PcpNavigation active="queue" canProjects={canProjects} />
    <section className="panel"><div className="panel-content"><form action="/planejamento/fila" className={s.selector}><div className="field"><label htmlFor="queue-cell">Célula</label><select id="queue-cell" name="cell" required defaultValue={cellId}><option value="">Selecione a célula</option>{choices.cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select></div><button className="button secondary" type="submit">Abrir fila</button></form></div></section>
    {snapshot ? <section className="panel"><div className="panel-header"><div><h2>Trabalhos abertos <span className="inline-count">{snapshot.total}</span></h2><p>Projetos ativos · inclui trabalhos visíveis e ocultos</p></div><span className="panel-caption">{canEdit ? 'Alterações são aplicadas ao salvar' : 'Consulta da fila'}</span></div><CellQueueEditor key={`${snapshot.cell.id}:${snapshot.queue_version}`} snapshot={snapshot} canEdit={canEdit} canProjects={canProjects} /></section> : <section className="panel"><Empty title={cellId ? 'Célula não encontrada' : 'Selecione uma célula para começar'} detail={cellId ? 'Escolha uma célula disponível na lista para consultar sua fila.' : 'A escolha da célula mantém a ordem e as prioridades no contexto do trabalho.'} icon="board" /></section>}
  </>;
}
