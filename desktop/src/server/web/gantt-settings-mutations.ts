import { z } from 'zod';
import { saveGanttSettingsSchema } from './gantt-settings-policy';
import { hasWebCapability } from './auth-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';
import type { CorporateCapability } from './sso-policy';

const receiptSchema = z.object({
  operation: z.literal('save_gantt_settings'), id: z.string().uuid(), projeto_id: z.string().uuid(),
  updated_at: z.string().datetime({ offset: true }), idempotent_replay: z.boolean(),
  record: z.object({ settings_changed: z.boolean() }).strict(),
});
export function createGanttSettingsActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  return { async saveGanttSettings(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.planning.read', 'em.planning.manage', 'em.projects.read'] as CorporateCapability[]).every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar o calendário e os marcos.' };
    }
    const checked = saveGanttSettingsSchema.safeParse(input);
    if (!checked.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os dias de trabalho, as exceções, os marcos e o motivo.', fieldErrors: checked.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'save_gantt_settings', checked.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const receipt = receiptSchema.safeParse(result.data);
    if (!receipt.success || receipt.data.id.toLowerCase() !== checked.data.projeto_id.toLowerCase()
      || receipt.data.projeto_id.toLowerCase() !== checked.data.projeto_id.toLowerCase()) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar o calendário e os marcos. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: receipt.data };
  } };
}
