import type { ProjectRouteSnapshot } from '@/server/web/project-route-data';
import type { SaveProjectRouteInput } from '@/server/web/project-route-policy';
import { freezeEngineeringRequest } from './engineering-model';
import type { WebRow } from '@/server/web/data';
export { moveQueueItem as moveProjectRouteItem, queueOrderChanged as projectRouteOrderChanged } from './pcp-model';

export function projectRouteNeedsNormalization(items: readonly { indice: number | null }[]) {
  return items.some((item, index) => item.indice !== index + 1);
}
export function projectRouteRequest(snapshot: ProjectRouteSnapshot, items: readonly { id: string; updated_at: string }[], submissionId: string): SaveProjectRouteInput {
  return freezeEngineeringRequest({ submissionId, projeto_id: snapshot.project.id,
    expected_project_updated_at: snapshot.project.updated_at, expected_route_version: snapshot.route_version,
    items: items.map(item => ({ id: item.id, expected_updated_at: item.updated_at })) });
}
export function projectRouteDestination(value: string, projectId: string): string {
  return /^\/(?!\/)[^\\\u0000-\u0020]*$/.test(value) ? value : `/cronograma?project=${encodeURIComponent(projectId)}`;
}

/** Two reads may race; show per-cell configuration only for the same full route. */
export function projectRouteMatchesContext(snapshot: ProjectRouteSnapshot | null, project: WebRow, allocations: readonly WebRow[]) {
  if (!snapshot || !snapshot.complete || snapshot.project.id !== project.id || snapshot.project.updated_at !== project.updated_at) return false;
  const active = allocations.filter(allocation => allocation.projeto_id === project.id && allocation.retirada !== true);
  return snapshot.items.length === active.length && snapshot.items.every(item => active.some(allocation => allocation.id === item.id
    && allocation.celula_id === item.celula_id && allocation.updated_at === item.updated_at));
}
