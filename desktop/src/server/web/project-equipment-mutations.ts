import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { saveProjectEquipmentSchema, projectEquipmentResultSchema } from './project-equipment-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });
export function createProjectEquipmentActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function saveProjectEquipment(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.projects.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil) || !(['em.portal.read', 'em.projects.read'] as const).every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar os dados técnicos do equipamento.' };
    }
    const parsed = saveProjectEquipmentSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os dados técnicos e confirme a alteração.', fieldErrors: parsed.error.flatten().fieldErrors };
    const value = parsed.data;
    const result = await dependencies.mutate(access.client, 'save_project_equipment', value, 'em.projects.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = projectEquipmentResultSchema.safeParse(data.record);
    if (data.operation !== 'save_project_equipment' || data.id !== value.equipamento_id || data.projeto_id !== value.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !record.success
      || record.data.projeto_id !== value.projeto_id || record.data.equipamento_id !== value.equipamento_id
      || new Set(record.data.changed_fields).size !== record.data.changed_fields.length
      || record.data.changed_fields.some(key => !Object.hasOwn(value.changes, key))) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar os dados técnicos. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: record.data } };
  }
  return { saveProjectEquipment };
}
