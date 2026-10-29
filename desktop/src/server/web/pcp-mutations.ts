import { z } from 'zod';
import { saveCellQueueSchema } from './pcp-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });

export function createPcpActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function saveCellQueue(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)) {
      return { ok: false, code: '42501', error: 'Seu perfil permite apenas consultar o planejamento.' };
    }
    const parsed = saveCellQueueSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira as prioridades e a sequência da célula.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'save_cell_queue', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data;
    if (data.operation !== 'save_cell_queue' || data.id !== parsed.data.celula_id || data.projeto_id !== null
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean') {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a alteração. Tente novamente com o mesmo protocolo.' };
    }
    // A batch can cover several projects. The private before/after snapshot and
    // operational rows stay on the server, including on idempotent replay.
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: null,
      updated_at: data.updated_at, record: {}, idempotent_replay: data.idempotent_replay } };
  }
  return { saveCellQueue };
}
