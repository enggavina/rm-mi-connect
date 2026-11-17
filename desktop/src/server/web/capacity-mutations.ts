import { z } from 'zod';
import { saveCapacityBookingsSchema, saveCapacityResourceSchema, CAPACITY_READ_SCOPES } from './capacity-policy';
import { hasWebCapability } from './auth-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const receipt = z.object({ operation: z.enum(['save_capacity_resource', 'save_capacity_bookings']), id: z.string().uuid(),
  projeto_id: z.string().uuid().nullable(), updated_at: z.string().datetime({ offset: true }), idempotent_replay: z.boolean(), record: z.record(z.string(), z.unknown()) });
const resourceRecord = z.object({ resource_changed: z.boolean() }).strict();
const bookingRecord = z.object({ changed_days: z.number().int().min(0).max(31) }).strict();
export function createCapacityActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function execute(operation: 'save_capacity_resource' | 'save_capacity_bookings', input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil) || ![...CAPACITY_READ_SCOPES, 'em.planning.manage' as const].every(scope => hasWebCapability(access, scope))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar a capacidade.' };
    }
    const checked = operation === 'save_capacity_resource' ? saveCapacityResourceSchema.safeParse(input) : saveCapacityBookingsSchema.safeParse(input);
    if (!checked.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o recurso, as horas, as datas e o motivo da alteração.', fieldErrors: checked.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, operation, checked.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const parsed = receipt.safeParse(result.data);
    const expectedId = 'resource_id' in checked.data ? checked.data.resource_id : checked.data.id;
    if (!parsed.success || parsed.data.operation !== operation || expectedId && parsed.data.id.toLowerCase() !== expectedId.toLowerCase()
      || operation === 'save_capacity_resource' && parsed.data.projeto_id !== null
      || operation === 'save_capacity_bookings' && !parsed.data.projeto_id
      || !(operation === 'save_capacity_resource' ? resourceRecord.safeParse(parsed.data.record).success : bookingRecord.safeParse(parsed.data.record).success)) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a alteração de capacidade. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: parsed.data };
  }
  return { saveCapacityResource: (input: unknown) => execute('save_capacity_resource', input), saveCapacityBookings: (input: unknown) => execute('save_capacity_bookings', input) };
}
