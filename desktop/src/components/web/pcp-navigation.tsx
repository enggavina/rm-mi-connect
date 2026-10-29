import s from './pcp.module.css';

export function PcpNavigation({ active, canPlanning = true, canProjects = true }: {
  active: 'planning' | 'queue' | 'load' | 'receiving'; canPlanning?: boolean; canProjects?: boolean;
}) {
  return <nav className={s.tabs} aria-label="Áreas do PCP">
    {canPlanning && <><a href="/planejamento" aria-current={active === 'planning' ? 'page' : undefined}>Alocações</a><a href="/planejamento/fila" aria-current={active === 'queue' ? 'page' : undefined}>Fila da célula</a><a href="/planejamento/carga" aria-current={active === 'load' ? 'page' : undefined}>Carga planejada</a></>}
    {canProjects && <a href="/recebimentos" aria-current={active === 'receiving' ? 'page' : undefined}>Recebimentos</a>}
  </nav>;
}
