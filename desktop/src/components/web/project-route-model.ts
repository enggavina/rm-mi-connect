import type { ProjectRouteSnapshot } from '@/server/web/project-route-data';
import type { SaveProjectRouteInput } from '@/server/web/project-route-policy';
import { freezeEngineeringRequest } from './engineering-model';
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
