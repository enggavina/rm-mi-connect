import { z } from 'zod';
import { EXECUTION_READ_SCOPES, reviewExecutionSessionSchema } from './execution-policy';
import { hasWebCapability } from './auth-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';
const receiptSchema = z.object({ operation: z.literal('review_execution_session'), id: z.string().uuid(), projeto_id: z.string().uuid(),
  updated_at: z.string().datetime({ offset: true }), idempotent_replay: z.boolean(), record: z.object({ review_id: z.string().uuid() }).strict() });
export function createExecutionActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  return { async reviewExecutionSession(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil) || ![...EXECUTION_READ_SCOPES, 'em.planning.manage' as const].every(scope => hasWebCapability(access, scope))) return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar os apontamentos.' };
    const parsed = reviewExecutionSessionSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o apontamento, o término, o esforço informado e o motivo da revisão.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'review_execution_session', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const receipt = receiptSchema.safeParse(result.data);
    if (!receipt.success || receipt.data.id.toLowerCase() !== parsed.data.session_id.toLowerCase()) return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a revisão. Tente novamente com o mesmo protocolo.' };
    return { ok: true, data: receipt.data };
  } };
}
