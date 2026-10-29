import { z } from 'zod';
import { hasWebCapability } from './auth-policy';
import { projectPhotoSelectionSchema } from './project-photo-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

const timestamp = z.string().datetime({ offset: true });

export function createProjectPhotoActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function setProjectPhotoSelection(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.projects.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !hasWebCapability(access, 'em.photos.read') || !hasWebCapability(access, 'em.projects.read')) {
      return { ok: false, code: '42501', error: 'Seu acesso não permite selecionar fotos deste projeto.' };
    }
    const parsed = projectPhotoSelectionSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Recarregue a foto antes de alterar a seleção.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'set_project_photo_selection', parsed.data, 'em.projects.manage', access.sso);
    if (!result.ok) return result;
    const data = result.data;
    const record = data.record;
    if (data.operation !== 'set_project_photo_selection' || data.id !== parsed.data.foto_id || data.projeto_id !== parsed.data.projeto_id
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean'
      || !record || record.foto_id !== parsed.data.foto_id || record.projeto_id !== parsed.data.projeto_id
      || record.selecao_relatorio !== parsed.data.selected || record.updated_at !== data.updated_at) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a seleção. Tente novamente com o mesmo protocolo.' };
    }
    // Audit snapshots stay private, including on a replay from an older consumer.
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: { foto_id: record.foto_id, projeto_id: record.projeto_id,
      selecao_relatorio: record.selecao_relatorio, updated_at: record.updated_at } } };
  }
  return { setProjectPhotoSelection };
}
