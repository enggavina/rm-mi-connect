import s from './pcp.module.css';

export function PcpNavigation({ active, canPlanning = true, canProjects = true }: {
  active: 'planning' | 'queue' | 'load' | 'receiving' | 'capacity' | 'execution'; canPlanning?: boolean; canProjects?: boolean;
}) {
  return <nav className={s.tabs} aria-label="Áreas do PCP">
    {canPlanning && <a href="/cronograma?view=gantt">Gantt e prazos</a>}
    {canPlanning && <><a href="/planejamento" aria-current={active === 'planning' ? 'page' : undefined}>Alocações</a><a href="/planejamento/fila" aria-current={active === 'queue' ? 'page' : undefined}>Fila da célula</a><a href="/planejamento/carga" aria-current={active === 'load' ? 'page' : undefined}>Carga planejada</a></>}
    {canPlanning && canProjects && <a href="/planejamento/capacidade" aria-current={active === 'capacity' ? 'page' : undefined}>Pessoas e máquinas</a>}
    {canPlanning && canProjects && <a href="/planejamento/execucao" aria-current={active === 'execution' ? 'page' : undefined}>Apontamentos</a>}
    {canProjects && <a href="/recebimentos" aria-current={active === 'receiving' ? 'page' : undefined}>Recebimentos</a>}
  </nav>;
}
