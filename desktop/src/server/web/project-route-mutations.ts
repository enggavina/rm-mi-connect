import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { saveProjectRouteSchema } from './project-route-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';
import { uuid } from './policy';

const timestamp = z.string().datetime({ offset: true });
const routeResult = z.object({ projeto_id: uuid, route_version: z.string().regex(/^[0-9a-f]{64}$/), changed_ids: z.array(uuid).max(2000) });

export function createProjectRouteActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function saveProjectRoute(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !hasWebCapability(access, 'em.projects.read') || !hasWebCapability(access, 'em.planning.read')) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar o roteiro do projeto.' };
    }
    const parsed = saveProjectRouteSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira a sequência completa das células.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'save_project_route', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = routeResult.safeParse(data.record);
    const submitted = new Set(parsed.data.items.map(item => item.id));
    if (data.operation !== 'save_project_route' || data.id !== parsed.data.projeto_id || data.projeto_id !== parsed.data.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !record.success
      || record.data.projeto_id !== parsed.data.projeto_id || new Set(record.data.changed_ids).size !== record.data.changed_ids.length
      || record.data.changed_ids.some(id => !submitted.has(id))) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a sequência. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: record.data } };
  }
  return { saveProjectRoute };
}
