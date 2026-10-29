import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';

const timestamp = z.string().datetime({ offset: true });
const text = z.string().nullable();
const projectRouteSchema = z.object({
  project: z.object({ id: uuid, numero: text, nome: text, status_pcp: text, data_real_de_entrega: timestamp.nullable(), updated_at: timestamp, closed: z.boolean() }),
  items: z.array(z.object({ id: uuid, celula_id: uuid.nullable(), celula_nome: text, status: text, visibilidade: z.boolean(), indice: z.number().int().nullable(), updated_at: timestamp })).max(2000),
  route_version: z.string().regex(/^[0-9a-f]{64}$/), total: z.number().int().nonnegative(), complete: z.boolean(),
});
export type ProjectRouteSnapshot = z.infer<typeof projectRouteSchema>;
export type ProjectRouteItem = ProjectRouteSnapshot['items'][number];
const unavailable = () => new Error('Não foi possível consultar o roteiro do projeto. Tente novamente.');

export function createProjectRouteData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectRoute(projectId: string): Promise<ProjectRouteSnapshot | null> {
    if (capabilities !== undefined && !['em.portal.read', 'em.planning.read', 'em.projects.read'].every(code => capabilities.includes(code as CorporateCapability))) {
      throw new Error('Acesso não autorizado a esta área.');
    }
    if (!uuid.safeParse(projectId).success) return null;
    const result = await client.rpc('rm_web_project_route_snapshot_v1', { p_project_id: projectId });
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = projectRouteSchema.safeParse(result.data);
    if (!parsed.success) throw unavailable();
    const snapshot = parsed.data;
    const closed = snapshot.project.data_real_de_entrega !== null || ['cancelado', 'finalizando_para_faturar'].includes(snapshot.project.status_pcp ?? '');
    if (snapshot.project.id !== projectId || snapshot.project.closed !== closed
      || new Set(snapshot.items.map(item => item.id)).size !== snapshot.items.length
      || (snapshot.complete ? snapshot.total > 2000 || snapshot.items.length !== snapshot.total : snapshot.total <= 2000 || snapshot.items.length !== 0)
      || snapshot.items.some((item, index, items) => {
        if (!index) return false;
        const previous = items[index - 1];
        if (previous.indice === null) return item.indice !== null || previous.id > item.id;
        return item.indice !== null && (previous.indice > item.indice || previous.indice === item.indice && previous.id > item.id);
      })) throw unavailable();
    // Zod strips fields outside this minimum DTO, including private snapshots.
    return snapshot;
  }
  return { getProjectRoute };
}

export async function getProjectRoute(projectId: string) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser('em.planning.read');
  return createProjectRouteData(access.client, access.sso?.capabilities).getProjectRoute(projectId);
}
