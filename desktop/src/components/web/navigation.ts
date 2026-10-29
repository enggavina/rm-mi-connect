import type { CorporateCapability } from '@/server/web/sso-policy';
import type { IconName } from './icons';

export type PortalNavigationItem = { href: string; label: string; icon: IconName; capability: CorporateCapability };
const groups: { label: string; items: PortalNavigationItem[] }[] = [
  { label: 'Operação', items: [
    { href: '/painel', label: 'Visão geral', icon: 'dashboard', capability: 'em.portal.read' },
  ] },
  { label: 'Planejamento', items: [
    { href: '/recebimentos', label: 'Recebimentos', icon: 'download', capability: 'em.projects.read' },
    { href: '/projetos', label: 'Projetos', icon: 'folder', capability: 'em.projects.read' },
    { href: '/cronograma', label: 'Cronograma', icon: 'calendar', capability: 'em.planning.read' },
    { href: '/planejamento', label: 'Planejamento', icon: 'board', capability: 'em.planning.read' },
    { href: '/formularios', label: 'Formulários e aprovações', icon: 'clipboard', capability: 'em.forms.read' },
    { href: '/aprovacoes', label: 'Aprovações de etapas', icon: 'check', capability: 'em.approvals.read' },
  ] },
  { label: 'Cadastros', items: [
    { href: '/cadastros', label: 'Cadastros gerais', icon: 'settings', capability: 'em.catalogs.read' },
    { href: '/engenharia/titulos', label: 'Títulos de fotos', icon: 'image', capability: 'em.engineering.read' },
    { href: '/engenharia', label: 'Gestão de tipos', icon: 'board', capability: 'em.engineering.read' },
    { href: '/modelos-formularios', label: 'Gestão de formulários', icon: 'clipboard', capability: 'em.form_templates.read' },
  ] },
];

export function portalNavigation(capabilities?: readonly CorporateCapability[]) {
  return groups.map(group => ({ ...group, items: group.items.filter(item => capabilities === undefined || capabilities.includes(item.capability)) }))
    .filter(group => group.items.length > 0);
}

export function activePortalItem(path: string, items: readonly PortalNavigationItem[]) {
  return items.filter(item => path === item.href || path.startsWith(item.href + '/')).sort((a, b) => b.href.length - a.href.length)[0];
}
