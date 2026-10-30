import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createWebData, listProjects } from '@/server/web/data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { CORPORATE_CAPABILITIES } from '@/server/web/sso-policy';
import { editorChoices } from '@/server/web/choices';
import { createProjectScheduleData } from '@/server/web/project-schedule-data';
import { getOperationalPhotos } from '@/server/web/operational-photo-data';
import { createProjectRouteData } from '@/server/web/project-route-data';
import { allocationRecords, orderedProjectAllocations, scheduleHref, scheduleId, scheduleTab, scheduleView, selectedAllocation, type ScheduleTab } from '@/server/web/project-schedule-policy';
import { PageHeading, Status, Details, Empty, Pagination, date, display } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { CellEditor } from '@/components/web/editor';
import { StageApprovalTable } from '@/components/web/stage-approval-list';
import { GanttSchedule } from '@/components/web/gantt-schedule';
import { ProjectAllocationList } from '@/components/web/project-schedule';
import { OperationalPhotoEditor } from '@/components/web/operational-photo-editor';
import { FormReviewerEditor } from '@/components/web/form-reviewer-editor';
import { getFormReviewerAssignments } from '@/server/web/form-reviewer-data';
import { getOperationalStageRules } from '@/server/web/operational-stage-rule-data';
import { getCellAvailability } from '@/server/web/cell-availability-data';
import { availabilityMatchesContext } from '@/components/web/cell-availability-model';
import { AllocationPlanningPanel } from '@/components/web/allocation-planning-panel';
import { OperationalStageRuleEditor } from '@/components/web/operational-stage-rule-editor';
import { ProjectRouteEditor } from '@/components/web/project-route-editor';
import s from '@/components/web/project-schedule.module.css';

export default async function Cronograma({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const session = await requireWebUser('em.planning.read');
  const canProjects = hasWebCapability(session, 'em.projects.read');
  const view = scheduleView(params, canProjects);
  const viewNavigation = <nav className="tabs" aria-label="Visões do cronograma">
    {canProjects && <a href={scheduleHref()} aria-current={view === 'project' ? 'page' : undefined}>Células por projeto</a>}
    <a href="/cronograma?view=gantt" aria-current={view === 'gantt' ? 'page' : undefined}>Gantt de prazos</a>
  </nav>;
  const heading = <PageHeading eyebrow="PCP · PLANEJAMENTO E CONTROLE" title="Cronograma"
    description={view === 'project' ? 'Escolha um projeto e acompanhe o roteiro e os registros de cada célula.' : 'Consulte os prazos planejados das células em uma janela de seis semanas.'}
    actions={<Link className="button secondary" href="/planejamento"><Icon name="board" size={16} />Ver planejamento</Link>} />;
  if (view === 'gantt') return <>{heading}{viewNavigation}<GanttSchedule params={params} canProjects={canProjects} /></>;

  const projectId = scheduleId(params.project);
  if (!projectId) {
    const q = typeof params.q === 'string' ? params.q : undefined;
    const client = scheduleId(params.client);
    const projects = await listProjects({ q, client, page: typeof params.page === 'string' ? params.page : undefined });
    return <>{heading}{viewNavigation}<section className="panel"><div className="panel-header"><div><h2>Selecionar projeto</h2><p>Pesquise pela OS ou escolha o cliente.</p></div></div>
      {params.project && <p className="notice" role="status">O projeto informado é inválido. Selecione um projeto da lista.</p>}
      <form className="filters" action="/cronograma"><input type="hidden" name="view" value="project" />
        <div className="search-field"><Icon name="search" size={16} /><input name="q" aria-label="Buscar OS, projeto ou cliente" defaultValue={q} placeholder="OS, projeto ou cliente…" maxLength={100} /></div>
        <select name="client" aria-label="Cliente" defaultValue={client || ''}><option value="">Todos os clientes</option>{projects.clients.map(customer => <option key={customer.id} value={customer.id}>{customer.nome}</option>)}</select>
        <button className="button secondary" type="submit">Pesquisar</button><Link className="button secondary" href="/planejamento">Voltar ao planejamento</Link>
      </form>
      {projects.rows.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Projeto / OS</th><th>Cliente</th><th>Status PCP</th><th className="table-action">Selecionar</th></tr></thead><tbody>{projects.rows.map(project => <tr key={project.id}>
        <td><a className="table-title" href={scheduleHref(project.id)}>{project.numero ? `OS ${project.numero}` : project.nome || 'Projeto sem OS'}</a><span className="table-subtitle">{project.descricao_equipamento || project.nome}</span></td>
        <td>{project.cliente_nome || 'Cliente não informado'}</td><td><Status value={project.status_pcp} /></td>
        <td className="table-action"><a href={scheduleHref(project.id)} aria-label={`Selecionar ${project.numero || project.nome || 'projeto'}`}><Icon name="arrow" size={16} /></a></td>
      </tr>)}</tbody></table></div> : <Empty title="Nenhum projeto encontrado" detail="Ajuste a pesquisa ou o cliente selecionado." icon="search" />}
      <Pagination {...projects} base="/cronograma" filters={{ view: 'project', q, client }} />
    </section></>;
  }
  // Reuse the project reader while excluding unused media/document/history
  // capabilities from this composition. Slots below have their own bounded DTO.
  const projectCapabilities = (session.sso?.capabilities ?? CORPORATE_CAPABILITIES).filter(capability => !['em.photos.read', 'em.documents.read', 'em.history.read'].includes(capability));
  const [data, route] = await Promise.all([
    createWebData(session.client, projectCapabilities).getProject(projectId),
    createProjectRouteData(session.client, session.sso?.capabilities).getProjectRoute(projectId),
  ]);
  if (!data) notFound();
  const project = data.project;
  const allocations = orderedProjectAllocations(data.allocations, projectId);
  const current = selectedAllocation(allocations, projectId, params.allocation);
  const availability = current ? await getCellAvailability(projectId, current.id) : null;
  const availabilityCurrent = !!availability && !!current && availabilityMatchesContext(availability, project, current);
  const currentWritable = !!current && current.retirada !== true && availabilityCurrent && !availability?.allocation.retirada;
  const tabs: { id: ScheduleTab; label: string }[] = [
    ...(hasWebCapability(session, 'em.photos.read') ? [{ id: 'fotos' as const, label: 'Fotos previstas' }] : []),
    ...(hasWebCapability(session, 'em.forms.read') ? [{ id: 'formularios' as const, label: 'Formulários' }] : []),
    ...(hasWebCapability(session, 'em.approvals.read') ? [{ id: 'etapas' as const, label: 'Aprovações de etapas' }] : []),
  ];
  const tab = scheduleTab(params.tab, tabs.map(item => item.id));
  const manager = ['administrador', 'padr_o'].includes(session.profile.perfil);
  const canPlan = manager && hasWebCapability(session, 'em.planning.manage');
  const canPlanCurrent = canPlan && currentWritable;
  const canEditProject = manager && hasWebCapability(session, 'em.projects.manage');
  const closed = !!project.data_real_de_entrega || ['cancelado', 'finalizando_para_faturar'].includes(project.status_pcp);
  const choices = canPlan && !closed && (!current || currentWritable) ? await editorChoices('planning') : null;
  const reader = createProjectScheduleData(session.client, session.sso?.capabilities);
  const photos = current && tab === 'fotos' ? await getOperationalPhotos(projectId, current.id) : null;
  const reviewers = current && tab === 'formularios' ? await getFormReviewerAssignments(projectId, current.id) : null;
  const stages = current && tab === 'etapas' ? await reader.stages(projectId, current.id, typeof params.page === 'string' ? params.page : undefined) : null;
  const stageRules = current && tab === 'etapas' ? await getOperationalStageRules(projectId, current.id) : null;
  const activeStageRules = stageRules?.rules.filter(rule => rule.ativo) ?? [];
  const stageRulesCurrent = !!stageRules && !!stages && stageRules.complete && stageRules.allocations_complete
    && stageRules.project.updated_at === project.updated_at && stageRules.allocation.updated_at === current?.updated_at
    && activeStageRules.length === stages.total && stages.items.every(item => activeStageRules.some(rule => rule.id === item.stage.id
      && rule.updated_at === item.stage.updated_at && (rule.status ?? 'nulo') === (item.stage.status ?? 'nulo')
      && item.allocation?.updated_at === stageRules.allocation.updated_at));
  const cellNames = new Map(data.cells.map(cell => [cell.id, cell.nome]));
  const userNames = new Map(data.users.map(user => [user.id, user.nome]));
  const formNames = new Map(data.forms.map(form => [form.id, form.titulo]));
  const records = current ? allocationRecords(data.records, current) : [];
  const formIds = current ? [...new Set<string>([...(current.forms_ids || []), ...records.map(record => record.form_id)].filter((id): id is string => typeof id === 'string'))] : [];

  const reviewerRecords = reviewers?.forms.flatMap(form => form.records) ?? [];
  const reviewerRecordsCurrent = !reviewers || reviewers.complete && reviewers.records_complete
    && reviewerRecords.length === records.length && reviewerRecords.every(record => records.some(row => row.id === record.id
      && row.updated_at === record.updated_at && row.status === record.status && row.preenchido === record.preenchido
      && (row.avaliador_user_id ?? null) === record.avaliador_user_id));
  const recordPanels = Object.fromEntries([...new Set([...formIds, ...(reviewers?.forms.map(form => form.id) ?? [])])].map(formId => {
    const submitted = records.filter(record => record.form_id === formId);
    const snapshotRecords = reviewers?.forms.find(form => form.id === formId)?.records;
    const changed = reviewers?.complete && reviewers.records_complete && (!snapshotRecords || snapshotRecords.length !== submitted.length
      || snapshotRecords.some(record => !submitted.some(row => row.id === record.id && row.updated_at === record.updated_at
        && row.status === record.status && row.preenchido === record.preenchido && (row.avaliador_user_id ?? null) === record.avaliador_user_id)));
    if (changed) return [formId, <p className="notice" key={formId}>Os registros foram atualizados durante a consulta. <a className="text-link" href={scheduleHref(projectId, current?.id, 'formularios')}>Recarregar formulários da célula</a> para consultar o estado atual.</p>];
    return [formId, submitted.length ? <div className="table-scroll" key={formId}><table className="data-table"><thead><tr><th>Registro</th><th>Operador</th><th>Status</th><th>Registro em</th><th className="table-action">Consultar</th></tr></thead><tbody>{submitted.map(record => <tr key={record.id}>
      <td>{record.codigo_text || record.codigo || 'Sem código'}<span className="table-subtitle">{record.preenchido ? 'Preenchido' : 'Em preenchimento'}{record.revisado ? ' · Revisado' : ''}</span></td><td>{userNames.get(record.identidade_user_id) || userNames.get(record.created_by_user_id) || 'Não informado'}{record.avaliador_user_id && <span className="table-subtitle">Avaliador do registro: {userNames.get(record.avaliador_user_id) || 'Não disponível'}</span>}</td><td><Status value={record.status} /></td><td>{date(record.created_at, true)}</td><td className="table-action"><Link href={`/formularios/${record.id}`} aria-label={`Consultar respostas de ${formNames.get(formId) || 'formulário'}`}><Icon name="arrow" size={15} /></Link></td>
    </tr>)}</tbody></table></div> : <p className="form-note" key={formId}>Aguardando preenchimento pela equipe.</p>];
  }));

  return <>{heading}{viewNavigation}<a className="back-link" href={scheduleHref()}><Icon name="back" size={15} />Trocar projeto</a>
    <section className="panel"><div className={`panel-header ${s.projectHeader}`}><div><h2>{project.numero ? `OS ${project.numero}` : project.nome || 'Projeto sem OS'}</h2><p>{data.client?.nome || project.cliente_nome_exportacao || 'Cliente não informado'}</p></div><div className="heading-actions"><Status value={project.status_pcp} /><Link className="button small secondary" href={`/projetos/${projectId}`}>Informações do projeto</Link>{canEditProject && <Link className="button small secondary" href={`/projetos/${projectId}/editar`}><Icon name="edit" size={14} />Editar projeto</Link>}</div></div>
      <div className="panel-content"><Details values={[[ 'Equipamento', project.descricao_equipamento || project.nome ], ['Chegada', date(project.chegada_do_equipamento, true)], ['Início previsto', date(project.data_prevista_inicio)], ['Entrega prevista', date(project.data_prevista_final)], ['Data contratual', date(project.data_contratual)], ['Escopo', project.escopo_abreviado]]} /></div>
    </section>
    {closed && <p className="notice" role="status">Este projeto está encerrado. O planejamento permanece disponível para consulta.</p>}
    {route && route.total > 0 && canPlan && !closed && (!current || currentWritable) && <details className="panel"><summary className={s.orderSummary}><span>Organizar sequência de execução</span><span className={s.orderClosed}>Expandir</span><span className={s.orderOpen}>Recolher</span></summary><div className="panel-content">
      <ProjectRouteEditor key={`${route.project.id}:${route.route_version}`} snapshot={route} canEdit={canPlan && !closed} destination={scheduleHref(projectId, current?.id, tab)} />
    </div></details>}
    {params.allocation && !current && <p className="notice" role="status">A célula selecionada não pertence a este projeto ou não está mais disponível. Selecione uma célula do roteiro.</p>}
    <div className={s.workspace}><div><ProjectAllocationList projectId={projectId} allocations={allocations} cells={data.cells} selectedId={current?.id} tab={tab} />
      {choices && data.cells.some(cell => !allocations.some(row => row.celula_id === cell.id)) && <CellEditor key={projectId} projectId={projectId} cells={data.cells.filter(cell => !allocations.some(row => row.celula_id === cell.id))} forms={choices.forms} users={choices.users} destination={scheduleHref(projectId)} />}
    </div><div className={s.context}>
      {current ? <><section className="panel"><div className={`panel-header ${s.projectHeader}`}><div><h2>{cellNames.get(current.celula_id) || 'Célula selecionada'}</h2><p>{current.retirada ? 'Retirada do planejamento · consulta histórica' : current.visibilidade ? 'Disponível no mobile' : 'Oculta no mobile'} · {current.forms_ids?.length || 0} formulários vinculados</p></div><div className="heading-actions"><Status value={current.status} /><a className="button small secondary" href={scheduleHref(projectId)}><Icon name="close" size={14} />Fechar célula</a></div></div>
        <div className="panel-content"><Details values={[[ 'Início previsto', date(current.data_inicio)], ['Prazo', date(current.data_limite)], ['Responsável', userNames.get(current.responsavel_id)], ['Prioridade', display(current.prioridade)], ['Execução', current.bloqueada === 'sim' ? `Bloqueada · ${current.motivo_bloqueio || 'Motivo não informado'}` : 'Sem bloqueio'], ['Observação', current.observacao]]} />
          {current.retirada && <p className="notice">Esta alocação foi retirada. Seus registros e vínculos permanecem disponíveis para consulta; restaurar conserva o mesmo identificador e começa com a célula oculta no mobile.</p>}
          <AllocationPlanningPanel key={`${current.id}:${availability?.context_version ?? current.updated_at}`} projectId={projectId} allocation={current} cells={data.cells}
            forms={choices?.forms ?? data.forms} users={choices?.users ?? data.users} snapshot={availability} canManage={canPlan} canPlan={canPlanCurrent && !closed}
            destination={scheduleHref(projectId, current.id, tab)} current={availabilityCurrent} />
        </div></section>
        {tabs.length ? <nav className="tabs" aria-label="Registros da célula">{tabs.map(item => <a key={item.id} href={scheduleHref(projectId, current.id, item.id)} aria-current={tab === item.id ? 'page' : undefined}>{item.label}</a>)}</nav> : <p className="notice">Seu acesso permite consultar o planejamento. As demais áreas dependem das permissões de fotos, formulários ou aprovações.</p>}
        {tab === 'fotos' && photos && <section className="panel"><div className={`panel-header ${s.projectHeader}`}><div><h2>Fotos previstas e registradas <span className="inline-count">{photos.total}</span></h2><p>Defina os títulos obrigatórios desta célula e acompanhe as capturas.</p></div><a className="text-link" href={`/projetos/${projectId}?tab=fotos`}>Abrir galeria<Icon name="arrow" size={14} /></a></div>
          <OperationalPhotoEditor key={`${current.id}:${photos.photos_version}`} snapshot={photos} canManage={canPlanCurrent}
            destination={scheduleHref(projectId, current.id, 'fotos')} />
        </section>}
        {tab === 'formularios' && <section className="panel"><div className="panel-header"><div><h2>Formulários da célula <span className="inline-count">{reviewers?.total ?? formIds.length}</span></h2><p>Defina o avaliador dos próximos envios e consulte os registros da execução.</p></div></div>
          {reviewers && reviewers.complete && reviewers.records_complete && !reviewerRecordsCurrent && <p className="notice" role="status">Os registros mudaram durante a consulta. Recarregue os formulários da célula antes de atribuir um avaliador.</p>}
          {reviewers ? <FormReviewerEditor key={`${current.id}:${reviewers.forms.map(form => form.context_version).join('|')}`} snapshot={reviewers} canManage={canPlanCurrent && reviewerRecordsCurrent}
            destination={scheduleHref(projectId, current.id, 'formularios')} recordPanels={recordPanels} />
            : <><p className="notice" role="status">O contexto dos avaliadores não está mais disponível. Recarregue a célula antes de atribuir.</p>{Object.entries(recordPanels).map(([id, panel]) => <div className="panel-content" key={id}><h3 className={s.slotTitle}>{formNames.get(id) || 'Formulário não disponível'}</h3>{panel}</div>)}</>}
        </section>}
        {tab === 'etapas' && <>
          {stageRules ? <details className="panel"><summary className={s.orderSummary}><span>{canPlan ? 'Configurar regras de etapas' : 'Consultar regras de etapas'}</span><span className={s.orderClosed}>Expandir</span><span className={s.orderOpen}>Recolher</span></summary>
            {stageRules.complete && stageRules.allocations_complete && !stageRulesCurrent && current.retirada !== true && <div className="panel-content"><p className="notice" role="status">As etapas ou a célula mudaram durante a consulta. <a className="text-link" href={scheduleHref(projectId, current.id, 'etapas')}>Recarregar regras e decisões</a> antes de configurar.</p></div>}
            <OperationalStageRuleEditor key={`${current.id}:${stageRules.rules_version}`} snapshot={stageRules} canManage={canPlanCurrent && stageRulesCurrent}
              destination={scheduleHref(projectId, current.id, 'etapas')} />
          </details> : <p className="notice" role="status">O contexto de configuração não está disponível. Recarregue a célula antes de alterar regras.</p>}
          {stages && <section className="panel"><div className="panel-header"><h2>Decisões da célula <span className="inline-count">{stages.total}</span></h2></div><StageApprovalTable items={current.retirada ? stages.items.map(item => ({ ...item, available_actions: [], action_reason: 'Célula retirada do planejamento: somente consulta.' })) : stages.items} canProjects hideProject /><Pagination {...stages} base="/cronograma" filters={{ view: 'project', project: projectId, allocation: current.id, tab: 'etapas' }} /></section>}
        </>}
      </> : <section className="panel"><Empty title="Selecione uma célula" detail="Escolha uma célula do roteiro para consultar datas, planejamento, fotos, formulários e aprovações." icon="board" /></section>}
    </div></div>
  </>;
}
