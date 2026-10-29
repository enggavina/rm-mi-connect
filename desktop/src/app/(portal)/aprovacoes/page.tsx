import { listStageApprovals, getStageApprovalChoices, type StageApprovalState } from '@/server/web/stage-approval-data';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { PageHeading, Pagination } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { StageApprovalTable } from '@/components/web/stage-approval-list';

export default async function Aprovacoes({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const query = await searchParams;
  const filters = Object.fromEntries(['q', 'cell', 'state', 'project', 'mine', 'page'].map(key => [key, typeof query[key] === 'string' ? query[key] as string : undefined]));
  const state: StageApprovalState = ['pending', 'approved', 'returned', 'all'].includes(filters.state || '') ? filters.state as StageApprovalState : 'pending';
  filters.state = state;
  const [session, data, choices] = await Promise.all([requireWebUser('em.approvals.read'), listStageApprovals({ ...filters, state, mine: filters.mine === 'true' }), getStageApprovalChoices()]);
  const canDecide = hasWebCapability(session, 'em.approvals.decide');
  return <><PageHeading eyebrow="PCP · FLUXO ENTRE CÉLULAS" title="Aprovações de etapas" description="Consulte as liberações e os retornos do roteiro. Abra uma etapa para conferir o contexto e registrar a decisão disponível." actions={hasWebCapability(session, 'em.planning.read') && <a className="button secondary" href="/planejamento"><Icon name="board" size={15} />Ver planejamento</a>} />
    <section className="panel"><div className="panel-header"><h2>Etapas dos projetos <span className="inline-count">{data.total}</span></h2><span className="panel-caption">Web e mobile acompanham as mesmas decisões</span></div>
      <form className="filters" action="/aprovacoes">
        {filters.project && <input type="hidden" name="project" value={filters.project} />}
        <div className="search-field"><Icon name="search" size={16} /><input name="q" aria-label="Buscar OS ou projeto" placeholder="Buscar OS ou projeto…" defaultValue={filters.q} maxLength={100} /></div>
        <select name="cell" aria-label="Célula de origem" defaultValue={filters.cell || ''}><option value="">Todas as células de origem</option>{choices.cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select>
        <select name="state" aria-label="Estado da decisão" defaultValue={filters.state || 'pending'}><option value="pending">Pendentes</option><option value="approved">Aprovadas</option><option value="returned">Retornadas</option><option value="all">Todas as decisões</option></select>
        {canDecide && <label className="check-label"><input type="checkbox" name="mine" value="true" defaultChecked={filters.mine === 'true'} />Posso decidir agora</label>}
        <button className="button secondary">Filtrar</button>{filters.project && <a className="text-link" href="/aprovacoes">Ver todos os projetos</a>}
      </form>
      <StageApprovalTable items={data.items} canProjects={hasWebCapability(session, 'em.projects.read')} />
      <Pagination page={data.page} pageSize={data.page_size} total={data.total} base="/aprovacoes" filters={filters} />
    </section></>;
}
