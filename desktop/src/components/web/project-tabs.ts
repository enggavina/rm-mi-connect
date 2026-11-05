import type { CorporateCapability } from '@/server/web/sso-policy';

export const projectTabs: { id: string; label: string; capability: CorporateCapability }[] = [
  { id: 'informacoes', label: 'Informações', capability: 'em.projects.read' },
  { id: 'roteiro', label: 'Roteiro', capability: 'em.planning.read' },
  { id: 'planejamento', label: 'Células e projetos', capability: 'em.planning.read' },
  { id: 'formularios', label: 'Formulários', capability: 'em.forms.read' },
  { id: 'fotos', label: 'Galeria de fotos', capability: 'em.photos.read' },
  { id: 'documentos', label: 'Documentos', capability: 'em.documents.read' },
  { id: 'comentarios', label: 'Comentários', capability: 'em.history.read' },
  { id: 'historico', label: 'Histórico', capability: 'em.history.read' },
];

/** Preserve old filtered-comment bookmarks without mixing new audit events. */
export function selectedProjectTab(query: Record<string, string | string[] | undefined>, allowedIds: readonly string[]) {
  const requested = query.tab === 'historico' && Object.keys(query).some(key => key.startsWith('comment_')) ? 'comentarios' : query.tab;
  return typeof requested === 'string' && allowedIds.includes(requested) ? requested : 'informacoes';
}
