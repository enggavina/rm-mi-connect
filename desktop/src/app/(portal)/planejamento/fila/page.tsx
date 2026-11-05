import { getCellQueue, getPcpChoices } from '@/server/web/pcp-data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { CellQueueEditor } from '@/components/web/pcp-queue-editor';
import { PcpNavigation } from '@/components/web/pcp-navigation';
import { PageHeading, Empty, Details, Status, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { editorChoices } from '@/server/web/choices';
import { createWebData } from '@/server/web/data';
import { CORPORATE_CAPABILITIES } from '@/server/web/sso-policy';
import { getCellAvailability } from '@/server/web/cell-availability-data';
import { availabilityMatchesContext } from '@/components/web/cell-availability-model';
import { AllocationPlanningPanel } from '@/components/web/allocation-planning-panel';
import { queueAllocationHref, queueAllocationMatches } from '@/components/web/queue-allocation-model';
import { scheduleId } from '@/server/web/project-schedule-policy';
import s from '@/components/web/pcp.module.css';

export default async function FilaCelula({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams; const cellId = typeof query.cell === 'string' ? query.cell : '';
  const [session, choices, snapshot] = await Promise.all([requireWebUser('em.planning.read'), getPcpChoices(), cellId ? getCellQueue(cellId) : null]);
  const canProjects = hasWebCapability(session, 'em.projects.read');
  const canEdit = hasWebCapability(session, 'em.planning.manage') && ['administrador', 'padr_o'].includes(session.profile.perfil);
  const allocationId = scheduleId(query.allocation);
  const item = canProjects && snapshot?.complete && allocationId ? snapshot.items.find(row => row.id === allocationId) : undefined;
  const capabilities = (session.sso?.capabilities ?? CORPORATE_CAPABILITIES).filter(capability => !['em.photos.read', 'em.documents.read', 'em.history.read'].includes(capability));
  const projectData = item ? await createWebData(session.client, capabilities).getProject(item.projeto_id, { includeDossier: false, includeEquipment: false }) : null;
  const allocation = projectData?.allocations.find(row => row.id === item?.id);
  const availability = item && allocation ? await getCellAvailability(item.projeto_id, item.id) : null;
  const current = !!item && queueAllocationMatches(item, allocation) && !!availability && !!projectData
    && availabilityMatchesContext(availability, projectData.project, allocation!);
  const planningChoices = item && current && canEdit && !availability?.project.closed ? await editorChoices('planning') : null;
  return <><a className="back-link" href="/planejamento"><Icon name="back" size={15} />Voltar ao planejamento</a>
    <PageHeading eyebrow="PCP · SEQUÊNCIA DA OPERAÇÃO" title={snapshot ? `Fila · ${snapshot.cell.nome || 'Célula'}` : 'Fila da célula'} description="Escolha uma célula para conferir os trabalhos abertos, definir prioridades e organizar a sequência. Alocações ocultas no mobile também participam desta fila." />
    <PcpNavigation active="queue" canProjects={canProjects} />
    <section className="panel"><div className="panel-content"><form action="/planejamento/fila" className={s.selector}><div className="field"><label htmlFor="queue-cell">Célula</label><select id="queue-cell" name="cell" required defaultValue={cellId}><option value="">Selecione a célula</option>{choices.cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select></div><button className="button secondary" type="submit">Abrir fila</button></form></div></section>
    {query.allocation && !item && <p className="notice" role="status">A alocação selecionada não está disponível nesta fila. Escolha um trabalho aberto da célula.</p>}
    {item && <section className="panel" id="editar-alocacao" data-queue-allocation={item.id}><div className="panel-header"><div><h2>{item.numero_projeto ? `OS ${item.numero_projeto}` : 'Projeto sem OS'} · Dados da alocação</h2><p>As alterações pertencem à relação entre este projeto e esta célula.</p></div><a className="button small secondary" href={queueAllocationHref(cellId)}>Fechar alocação</a></div><div className="panel-content">
      {!current || !projectData || !allocation ? <p className="notice" role="status">A fila ou a alocação mudou durante a consulta. Reabra os dados da alocação antes de editar.</p> : <><Status value={allocation.status} /><Details values={[
        ['Início previsto', date(allocation.data_inicio)], ['Prazo da célula', date(allocation.data_limite)], ['Fim realizado', date(allocation.data_fim_real)],
        ['Responsável', projectData.users.find(user => user.id === allocation.responsavel_id)?.nome], ['Horas previstas', allocation.horas_previstas], ['Horas realizadas', allocation.horas_realizadas],
        ['Motivo do atraso', allocation.motivo_atraso], ['Observação', allocation.observacao],
      ]} />
        <p className="form-note" style={{ marginTop: 20 }}>O status e o fim realizado seguem as regras de execução e aprovação das etapas. A edição abaixo conserva esses controles e a ordem do roteiro.</p>
        <AllocationPlanningPanel key={`${allocation.id}:${availability?.context_version ?? allocation.updated_at}`} projectId={item.projeto_id} allocation={allocation} cells={projectData.cells}
          forms={planningChoices?.forms ?? projectData.forms} users={planningChoices?.users ?? projectData.users} snapshot={availability} canManage={canEdit} canPlan={!!planningChoices}
          destination={queueAllocationHref(cellId, item.id)} current={current} />
        <div className="form-actions"><a className="button small secondary" href={`/cronograma?project=${item.projeto_id}&allocation=${item.id}`}>Fotos, formulários e aprovações</a><a className="button small secondary" href={`/projetos/${item.projeto_id}?tab=planejamento#celula-${item.id}`}>Projeto e histórico da célula</a></div>
      </>}
    </div></section>}
    {snapshot ? <section className="panel"><div className="panel-header"><div><h2>Trabalhos abertos <span className="inline-count">{snapshot.total}</span></h2><p>Projetos ativos · inclui trabalhos visíveis e ocultos</p></div><span className="panel-caption">{item ? 'Feche a alocação para alterar a ordem e as prioridades da fila' : canEdit ? 'Alterações são aplicadas ao salvar' : 'Consulta da fila'}</span></div><CellQueueEditor key={`${snapshot.cell.id}:${snapshot.queue_version}:${item?.id ?? ''}`} snapshot={snapshot} canEdit={canEdit && !item} canProjects={canProjects} /></section> : <section className="panel"><Empty title={cellId ? 'Célula não encontrada' : 'Selecione uma célula para começar'} detail={cellId ? 'Escolha uma célula disponível na lista para consultar sua fila.' : 'A escolha da célula mantém a ordem e as prioridades no contexto do trabalho.'} icon="board" /></section>}
  </>;
}
