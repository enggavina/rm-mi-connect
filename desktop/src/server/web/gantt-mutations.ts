import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { saveGanttPlanSchema, GANTT_MAX_ITEMS } from './gantt-policy';
import { uuid } from './policy';
import type { actionUser, mutate, WebActionResult } from './mutation';
import type { CorporateCapability } from './sso-policy';

const timestamp = z.string().datetime({ offset: true });
const recordSchema = z.object({ changed_ids: z.array(uuid).max(GANTT_MAX_ITEMS), links_changed: z.boolean(), baseline_id: uuid.nullable() });

export function createGanttActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function saveGanttPlan(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.planning.read', 'em.planning.manage', 'em.projects.read'] as CorporateCapability[]).every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar o Gantt.' };
    }
    const parsed = saveGanttPlanSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os prazos, as dependências e o motivo da alteração.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'save_gantt_plan', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const value = result.data, record = recordSchema.safeParse(value.record);
    const single = parsed.data.projects.length === 1 ? parsed.data.projects[0].id : null;
    const expectedId = single ?? parsed.data.submissionId;
    const submitted = new Set(parsed.data.items.map(item => item.id.toLowerCase()));
    if (value.operation !== 'save_gantt_plan' || !uuid.safeParse(value.id).success || !uuid.nullable().safeParse(value.projeto_id).success
      || value.id.toLowerCase() !== expectedId.toLowerCase()
      || (value.projeto_id?.toLowerCase() ?? null) !== (single?.toLowerCase() ?? null)
      || !timestamp.safeParse(value.updated_at).success || typeof value.idempotent_replay !== 'boolean' || !record.success
      || new Set(record.data.changed_ids.map(id => id.toLowerCase())).size !== record.data.changed_ids.length
      || record.data.changed_ids.some(id => !submitted.has(id.toLowerCase()))
      || record.data.links_changed && !parsed.data.dependencies
      || !!record.data.baseline_id !== !!parsed.data.baseline) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar o planejamento. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: value.operation, id: value.id, projeto_id: value.projeto_id, updated_at: value.updated_at,
      record: record.data, idempotent_replay: value.idempotent_replay } };
  }
  return { saveGanttPlan };
}
