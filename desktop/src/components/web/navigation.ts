import type { CorporateCapability } from '@/server/web/sso-policy';
import type { IconName } from './icons';

export type PortalNavigationItem = { href: string; label: string; description: string; icon: IconName; capability: CorporateCapability; requires?: readonly CorporateCapability[]; shortcutOrder?: number; home?: false; external?: true };
export const WORKSHOP_3D_PATH = '/gemeo-digital';
const groups: { label: string; items: PortalNavigationItem[] }[] = [
  { label: 'Operação', items: [
    { href: '/painel', label: 'Início', description: 'Encontre as funcionalidades da oficina.', icon: 'dashboard', capability: 'em.portal.read', shortcutOrder: 0, home: false },
    { href: '/acompanhamento', label: 'Acompanhamento da operação', description: 'Consulte os indicadores, projetos recentes e pendências da operação.', icon: 'chart', capability: 'em.portal.read', shortcutOrder: 1, home: false },
    { href: WORKSHOP_3D_PATH, label: 'Gêmeo digital 3D', description: 'Visualize a oficina em 3D com os projetos e células do EM.', icon: 'cube', capability: 'em.planning.read', requires: ['em.projects.read', 'em.portal.read'], shortcutOrder: 2, home: false },
    { href: '/projetos', label: 'Projetos', description: 'Equipamentos, células, formulários, fotos e documentos de cada projeto.', icon: 'folder', capability: 'em.projects.read', shortcutOrder: 3 },
    { href: '/recebimentos', label: 'Recebimentos', description: 'Confira os equipamentos recebidos e as pendências para o planejamento.', icon: 'download', capability: 'em.projects.read' },
    { href: '/formularios', label: 'Formulários e aprovações', description: 'Consulte as respostas e avalie os registros enviados pela equipe.', icon: 'clipboard', capability: 'em.forms.read', shortcutOrder: 5 },
    { href: '/aprovacoes', label: 'Aprovações de etapas', description: 'Consulte, libere e avalie as etapas conforme sua autorização.', icon: 'check', capability: 'em.approvals.read', shortcutOrder: 6 },
  ] },
  { label: 'Planejamento', items: [
    { href: '/cronograma', label: 'Gantt e cronograma', description: 'Planeje prazos e etapas nas visões geral, por célula e por projeto.', icon: 'calendar', capability: 'em.planning.read', shortcutOrder: 4 },
    { href: '/planejamento', label: 'Planejamento', description: 'Consulte as alocações e acompanhe responsáveis, horas e bloqueios.', icon: 'board', capability: 'em.planning.read' },
    { href: '/planejamento/fila', label: 'Fila da célula', description: 'Defina a prioridade e a sequência dos trabalhos de uma célula.', icon: 'board', capability: 'em.planning.read' },
    { href: '/planejamento/carga', label: 'Carga planejada', description: 'Veja horas informadas, bloqueios e prazos por célula.', icon: 'clock', capability: 'em.planning.read' },
    { href: '/planejamento/capacidade', label: 'Pessoas e máquinas', description: 'Planeje disponibilidade, reservas diárias e sobrecarga dos recursos da oficina.', icon: 'users', capability: 'em.planning.read', requires: ['em.projects.read', 'em.portal.read'] },
    { href: '/planejamento/execucao', label: 'Apontamentos da oficina', description: 'Acompanhe trabalho informado, pausas, términos e revisão dos apontamentos.', icon: 'clock', capability: 'em.planning.read', requires: ['em.projects.read', 'em.portal.read'] },
  ] },
  { label: 'Cadastros', items: [
    { href: '/cadastros', label: 'Cadastros gerais', description: 'Clientes, células, tipos de equipamento e consulta da equipe.', icon: 'settings', capability: 'em.catalogs.read' },
    { href: '/engenharia/titulos', label: 'Títulos de fotos', description: 'Mantenha os títulos utilizados nas fotos obrigatórias dos equipamentos.', icon: 'image', capability: 'em.engineering.read' },
    { href: '/engenharia', label: 'Tipos e roteiros', description: 'Configure células, formulários, fotos e etapas por tipo de equipamento.', icon: 'board', capability: 'em.engineering.read' },
    { href: '/modelos-formularios', label: 'Modelos de formulário', description: 'Crie, revise e publique os modelos utilizados pela operação.', icon: 'clipboard', capability: 'em.form_templates.read' },
  ] },
];

export function portalNavigation(capabilities?: readonly CorporateCapability[]) {
  return groups.map(group => ({ ...group, items: group.items.filter(item => capabilities === undefined || capabilities.includes(item.capability) && (item.requires ?? []).every(capability => capabilities.includes(capability))) }))
    .filter(group => group.items.length > 0);
}

/** Work modules stay on the home; monitoring has dedicated sidebar entries. */
export function portalHomeModules(capabilities?: readonly CorporateCapability[]) {
  return portalNavigation(capabilities).map(group => ({ ...group, items: group.items.filter(item => item.home !== false) }))
    .filter(group => group.items.length > 0);
}

/** Keep the sidebar small without creating a second permission catalogue. */
export function portalShortcuts(capabilities?: readonly CorporateCapability[]) {
  return portalNavigation(capabilities).flatMap(group => group.items).filter(item => item.shortcutOrder !== undefined)
    .sort((a, b) => a.shortcutOrder! - b.shortcutOrder!);
}

export function activePortalItem(path: string, items: readonly PortalNavigationItem[]) {
  return items.filter(item => !item.external && (path === item.href || path.startsWith(item.href + '/'))).sort((a, b) => b.href.length - a.href.length)[0];
}
