import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getProject, type WebRow } from '@/server/web/data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import type { CorporateCapability } from '@/server/web/sso-policy';
import { editorChoices } from '@/server/web/choices';
import { PageHeading, Status, Details, Empty, Pagination, date, display } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { ProjectPhotoGallery } from '@/components/web/project-photo-gallery';
import { CellEditor } from '@/components/web/editor';
import { getCellAvailability } from '@/server/web/cell-availability-data';
import { scheduleId } from '@/server/web/project-schedule-policy';
import { availabilityMatchesContext } from '@/components/web/cell-availability-model';
import { AllocationPlanningPanel } from '@/components/web/allocation-planning-panel';
import { ProjectDocumentsPanel, ProjectHistoryPanel } from '@/components/web/project-dossier-panels';

const allTabs: { id: string; label: string; capability: CorporateCapability }[] = [{ id: 'informacoes', label: 'Informações', capability: 'em.projects.read' }, { id: 'planejamento', label: 'Células e planejamento', capability: 'em.planning.read' }, { id: 'formularios', label: 'Formulários', capability: 'em.forms.read' }, { id: 'fotos', label: 'Galeria de fotos', capability: 'em.photos.read' }, { id: 'documentos', label: 'Documentos', capability: 'em.documents.read' }, { id: 'historico', label: 'Histórico', capability: 'em.history.read' }];
export default async function Projeto({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params; const query = await searchParams;
  const selection = query.selection === 'selected' ? 'selected' : 'all';
  const photoOrder = query.photo_order === 'selected' ? 'selected' : 'sequence';
  const [data, session] = await Promise.all([getProject(id, { photoPage: typeof query.page === 'string' ? query.page : undefined, selection, photoOrder }), requireWebUser('em.projects.read')]); if (!data) notFound();
  const tabs = allTabs.filter(item => hasWebCapability(session, item.capability));
  const tab = tabs.some(item => item.id === query.tab) ? String(query.tab) : 'informacoes';
  const project = data.project; const cellNames = new Map(data.cells.map(cell => [cell.id, cell.nome])); const userNames = new Map(data.users.map(user => [user.id, user.nome])); const formNames = new Map(data.forms.map(form => [form.id, form.titulo]));
  const manager = ['administrador', 'padr_o'].includes(session.profile.perfil);
  const canPlan = manager && hasWebCapability(session, 'em.planning.manage');
  const canEdit = manager && hasWebCapability(session, 'em.projects.manage');
  const closed = !!project.data_real_de_entrega || ['cancelado', 'finalizando_para_faturar'].includes(project.status_pcp);
  const choices = tab === 'planejamento' && canPlan && !closed ? await editorChoices('planning') : null;
  const activeAllocations = data.allocations.filter(allocation => allocation.retirada !== true), retiredAllocations = data.allocations.filter(allocation => allocation.retirada === true);
  const selectedAllocationId = tab === 'planejamento' ? scheduleId(query.allocation) : undefined;
  const selectedAllocation = selectedAllocationId ? data.allocations.find(allocation => allocation.id === selectedAllocationId && allocation.projeto_id === id) : undefined;
  const availability = selectedAllocation ? await getCellAvailability(id, selectedAllocation.id) : null;
  const availabilityCurrent = !!availability && !!selectedAllocation && availabilityMatchesContext(availability, project, selectedAllocation);
  const newCells = data.cells.filter(cell => !data.allocations.some(allocation => allocation.celula_id === cell.id));
  const projectData = data;
  function allocationPanel(allocation: WebRow) {
    const selected = allocation.id === selectedAllocationId;
    const destination = `/projetos/${id}?tab=planejamento&allocation=${allocation.id}#celula-${allocation.id}`;
    return <section className="panel" key={allocation.id} id={`celula-${allocation.id}`} data-project-allocation={allocation.id}>
      <div className="panel-header"><div><h2>{cellNames.get(allocation.celula_id) || 'Célula'}</h2><p>{allocation.forms_ids?.length || 0} formulários vinculados · {allocation.retirada ? 'Retirada do planejamento · consulta histórica' : allocation.visibilidade ? 'Disponível no mobile' : 'Oculta no mobile'}</p></div><Status value={allocation.status} /></div>
      <div className="panel-content"><Details values={[
        ['Início previsto', date(allocation.data_inicio)], ['Prazo', date(allocation.data_limite)], ['Responsável', userNames.get(allocation.responsavel_id)], ['Horas previstas', allocation.horas_previstas],
        ['Execução', allocation.bloqueada === 'sim' ? `Bloqueada · ${allocation.motivo_bloqueio || 'Motivo não informado'}` : 'Sem bloqueio'], ['Observação', allocation.observacao],
      ]} />{!!allocation.forms_ids?.length && <p className="form-note" style={{ margin: '22px 0 0' }}>{allocation.forms_ids.map((formId: string) => formNames.get(formId) || 'Modelo indisponível').join(' · ')}</p>}
        {selected ? <><div className="form-actions"><a className="button small secondary" href={`/projetos/${id}?tab=planejamento#celula-${allocation.id}`}>Fechar disponibilidade</a></div>
          <AllocationPlanningPanel key={`${allocation.id}:${availability?.context_version ?? allocation.updated_at}`} projectId={id} allocation={allocation} cells={projectData.cells}
            forms={choices?.forms ?? projectData.forms} users={choices?.users ?? projectData.users} snapshot={availability} canManage={canPlan} canPlan={!!choices && !closed}
            destination={destination} current={availabilityCurrent} /></>
          : <div style={{ marginTop: 20 }}><div className="heading-actions">
            {choices && !allocation.retirada && !['finalizado', 'n_a'].includes(allocation.status ?? '') && <CellEditor projectId={id} allocation={allocation} cells={projectData.cells} forms={choices.forms} users={choices.users} destination={destination} />}
            <a className="button small secondary" href={destination} aria-label={`${canPlan ? 'Gerenciar' : 'Consultar'} disponibilidade de ${cellNames.get(allocation.celula_id) || 'célula'}`}>Disponibilidade da célula</a>
          </div></div>}
      </div>
    </section>;
  }
  const title = project.numero ? `OS ${project.numero.trim()}` : 'Projeto em recebimento';
  return <><Link className="back-link" href="/projetos"><Icon name="back" size={15} />Todos os projetos</Link><PageHeading eyebrow="ACOMPANHAMENTO DO PROJETO" title={title} description={project.descricao_equipamento || project.nome || 'Informações e registros do equipamento em uma mesma jornada.'} actions={canEdit && <Link className="button secondary" href={`/projetos/${id}/editar`}><Icon name="edit" size={15} />Editar projeto</Link>} />
    <section className="panel"><div className="panel-content project-summary"><div><h2>{data.client?.nome || project.cliente_nome_exportacao || 'Cliente não informado'}</h2><div className="summary-meta"><span>Chegada: {date(project.chegada_do_equipamento)}</span><span>Entrega prevista: {date(project.data_prevista_final)}</span>{hasWebCapability(session, 'em.planning.read') && <span>{activeAllocations.length} células no planejamento{retiredAllocations.length ? ` · ${retiredAllocations.length} retiradas` : ''}</span>}</div></div><Status value={project.status_pcp} /></div></section>
    <nav className="tabs" aria-label="Áreas do projeto">{tabs.map(item => <a key={item.id} href={`/projetos/${id}?tab=${item.id}`} aria-current={tab === item.id ? 'page' : undefined}>{item.label}</a>)}</nav>
    {tab === 'informacoes' && <>
      <section className="panel"><div className="panel-header"><h2>Informações do projeto</h2></div><div className="panel-content"><Details values={[
        ['OS / número', project.numero], ['Nome', project.nome], ['Cliente', data.client?.nome || project.cliente_nome_exportacao], ['Descrição do equipamento', project.descricao_equipamento], ['Contato', project.contato], ['Proprietário', project.proprietario], ['Status PCP', display(project.status_pcp)], ['Etapa do projeto', display(project.status)], ['Nota fiscal', project.nota_fiscal], ['Chegada do equipamento', date(project.chegada_do_equipamento, true)], ['Início previsto', date(project.data_prevista_inicio)], ['Entrega prevista', date(project.data_prevista_final)], ['Data contratual', date(project.data_contratual)], ['Data renegociada', date(project.data_renegociada)], ['Entrega realizada', date(project.data_real_de_entrega)], ['Última atualização', date(project.updated_at, true)], ['Escopo', project.escopo_abreviado], ['Eventualidades', project.eventualidades], ['Motivo de replanejamento', project.replanejamento_motivo],
      ]} />{project.arquivo_nota_fiscal_url && <div style={{ marginTop: 25 }}><a className="button small secondary" href={`/api/web/documents/${id}?source=invoice`} target="_blank" rel="noopener noreferrer"><Icon name="download" size={14} />Abrir nota fiscal</a></div>}</div></section>
      <section className="panel"><div className="panel-header"><h2>Dados do equipamento</h2></div>{data.equipment ? <div className="panel-content"><Details values={[
        ['Fabricante', data.equipment.fabricante], ['Modelo', data.equipment.modelo], ['Número de série', data.equipment.numero_serie], ['Placa do motor', display(data.equipment.placa_motor)], ['Descrição', data.equipment.descricao], ['Potência', data.equipment.potencia], ['Rotação', data.equipment.rotacao], ['Tensão do estator', data.equipment.tensao_estator], ['Corrente do estator', data.equipment.corrente_estator], ['Frequência', data.equipment.frequencia], ['Classe de isolamento', data.equipment.classe_isolamento], ['Grau de proteção', data.equipment.grau_ip], ['Forma', data.equipment.forma], ['Regime', data.equipment.regime], ['Peso', data.equipment.peso], ['Ligação', data.equipment.ligacao], ['Norma', data.equipment.norma], ['Certificado', data.equipment.certificado],
      ]} /></div> : <Empty title="Dados de equipamento ainda não informados" detail="As informações serão exibidas conforme o recebimento e os registros do projeto." icon="settings" />}</section>
    </>}
    {tab === 'planejamento' && <>
      {closed && <div className="notice">Este projeto está encerrado. O planejamento permanece disponível para consulta.</div>}
      {query.allocation && !selectedAllocation && <p className="notice" role="status">A célula solicitada não pertence a este projeto ou não está disponível. Escolha uma alocação abaixo.</p>}
      {activeAllocations.map(allocationPanel)}
      {!activeAllocations.length && <section className="panel"><Empty title="Nenhuma célula ativa no planejamento" detail="Aloque uma nova célula ou consulte as retiradas preservadas. Formulários, fotos e regras existentes não serão copiados novamente ao restaurar." icon="board" /></section>}
      {retiredAllocations.length > 0 && <details open={selectedAllocation?.retirada === true}><summary className="back-link">Células retiradas ({retiredAllocations.length})</summary>{retiredAllocations.map(allocationPanel)}</details>}
      {choices && newCells.length > 0 && <CellEditor projectId={id} cells={newCells} forms={choices.forms} users={choices.users} destination={`/projetos/${id}?tab=planejamento`} />}
    </>}
    {tab === 'formularios' && <section className="panel"><div className="panel-header"><h2>Registros do projeto <span className="inline-count">{data.records.length}</span></h2></div>{data.records.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Formulário</th><th>Célula</th><th>Operador</th><th>Status</th><th>Enviado em</th><th className="table-action">Abrir</th></tr></thead><tbody>{data.records.map(record => <tr key={record.id}><td><Link className="table-title" href={`/formularios/${record.id}`}>{formNames.get(record.form_id) || 'Formulário'}</Link><span className="table-subtitle">Registro {record.codigo_text || record.codigo || 'sem código'}</span></td><td>{cellNames.get(record.celula_id) || 'Projeto'}</td><td>{userNames.get(record.identidade_user_id) || userNames.get(record.created_by_user_id) || 'Não informado'}</td><td><Status value={record.status} /></td><td>{date(record.created_at)}</td><td className="table-action"><Link href={`/formularios/${record.id}`} aria-label="Consultar respostas"><Icon name="arrow" size={15} /></Link></td></tr>)}</tbody></table></div> : <Empty title="Nenhum formulário enviado" detail="Os registros enviados pelos operadores aparecerão aqui após a sincronização." icon="clipboard" />}</section>}
    {tab === 'fotos' && <>
      <div className="section-divider"><h2>Fotos registradas <span className="inline-count">{data.photoTotal}</span></h2><span className="panel-caption">Toque em uma foto para ampliar</span></div>
      <form className="filters" action={`/projetos/${id}`}><input type="hidden" name="tab" value="fotos" />
        <select name="selection" aria-label="Seleção para relatório" defaultValue={selection}><option value="all">Todas as fotos</option><option value="selected">Selecionadas para relatório</option></select>
        <select name="photo_order" aria-label="Ordenação das fotos" defaultValue={photoOrder}><option value="sequence">Número da foto</option><option value="selected">Selecionadas primeiro</option></select>
        <button type="submit" className="button secondary">Aplicar</button>
      </form>
      {data.photos.length ? <ProjectPhotoGallery projectId={id} canSelect={canEdit && hasWebCapability(session, 'em.photos.read')}
        destination={`/projetos/${id}?tab=fotos&selection=${selection}&photo_order=${photoOrder}&page=${data.photoPage}`}
        photos={data.photos.map(photo => ({ id: photo.id, titulo: photo.titulo, foto_url: photo.foto_url, categoria_foto: photo.categoria_foto,
          cellName: cellNames.get(photo.celula_id) || 'Projeto / recebimento', legenda: photo.legenda, selecao_relatorio: photo.selecao_relatorio, updated_at: photo.updated_at }))} />
        : <section className="panel"><Empty title={selection === 'selected' ? 'Nenhuma foto selecionada' : 'Nenhuma foto registrada'} detail={selection === 'selected' ? 'Exiba todas as fotos para selecionar as que devem compor o relatório.' : 'As fotos capturadas pela equipe aparecerão aqui após a sincronização.'} icon="image" /></section>}
      <Pagination page={data.photoPage} pageSize={data.photoPageSize} total={data.photoTotal} base={`/projetos/${id}`} filters={{ tab: 'fotos', selection, photo_order: photoOrder }} />
    </>}
    {tab === 'documentos' && <ProjectDocumentsPanel projectId={id} projectVersion={project.updated_at} documents={data.documents} attachments={data.attachments} users={data.users} canAdd={canEdit} closed={closed} />}
    {tab === 'historico' && <ProjectHistoryPanel projectId={id} projectVersion={project.updated_at} comments={data.comments} stages={data.stages} cells={data.cells} users={data.users} allocations={data.allocations} canAdd={canEdit && hasWebCapability(session, 'em.planning.read')} closed={closed} />}
  </>;
}
