import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { manageOperationalPhotosSchema, operationalPhotoResultSchema } from './operational-photo-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });
const readCapabilities = ['em.projects.read', 'em.planning.read', 'em.photos.read'] as const;

export function createOperationalPhotoActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function manageOperationalPhotos(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.planning.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !readCapabilities.every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar as fotos desta célula.' };
    }
    const parsed = manageOperationalPhotosSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os títulos e recarregue os dados da célula antes de salvar.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'manage_operational_photos', parsed.data, 'em.planning.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data, record = operationalPhotoResultSchema.safeParse(data.record);
    const targets = new Set(parsed.data.action === 'add' ? parsed.data.items.map(item => item.id) : [parsed.data.foto_id]);
    if (data.operation !== 'manage_operational_photos' || data.id !== parsed.data.celula_projeto_id || data.projeto_id !== parsed.data.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !record.success
      || record.data.projeto_id !== parsed.data.projeto_id || record.data.celula_projeto_id !== parsed.data.celula_projeto_id || record.data.action !== parsed.data.action
      || new Set(record.data.changed_ids).size !== record.data.changed_ids.length || record.data.changed_ids.some(id => !targets.has(id))) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a alteração das fotos. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: record.data } };
  }
  return { manageOperationalPhotos };
}
