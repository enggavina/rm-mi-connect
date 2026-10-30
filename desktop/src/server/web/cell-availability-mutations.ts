import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { manageCellAvailabilitySchema, cellAvailabilityResultSchema } from './cell-availability-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });
const reads = ['em.portal.read', 'em.projects.read', 'em.planning.read'] as const;
export function createCellAvailabilityActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function manageCellAvailability(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil) || !reads.every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar a disponibilidade da célula.' };
    }
    const parsed = manageCellAvailabilitySchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o contexto e confirme a alteração de disponibilidade.', fieldErrors: parsed.error.flatten().fieldErrors };
    const value = parsed.data;
    const result = await dependencies.mutate(access.client, 'manage_cell_availability', value, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = cellAvailabilityResultSchema.safeParse(data.record);
    if (data.operation !== 'manage_cell_availability' || data.id !== value.celula_projeto_id || data.projeto_id !== value.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !record.success
      || record.data.projeto_id !== value.projeto_id || record.data.celula_projeto_id !== value.celula_projeto_id
      || record.data.action !== value.action || record.data.changed_ids.some(id => id !== value.celula_projeto_id)
      || record.data.retirada && record.data.visibilidade
      || value.action === 'set_visibility' && (record.data.retirada || record.data.visibilidade !== value.visibilidade)
      || value.action === 'retire' && (!record.data.retirada || record.data.visibilidade)
      || value.action === 'restore' && (record.data.retirada || record.data.visibilidade)) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a disponibilidade. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      record: record.data, idempotent_replay: data.idempotent_replay } };
  }
  return { manageCellAvailability };
}
