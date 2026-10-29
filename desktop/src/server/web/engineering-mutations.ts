import { deletePhotoTitleSchema, engineeringMutationError, photoTitleDeletionResultSchema, saveEngineeringSchema, savePhotoTitleSchema } from './engineering-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

export function createEngineeringActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function execute(operation: 'save_engineering' | 'save_photo_title' | 'delete_photo_title', input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.engineering.manage');
    if ('ok' in access) return access;
    if (access.profile.perfil !== 'administrador') return { ok: false, ...engineeringMutationError('42501') };
    const schema = operation === 'save_engineering' ? saveEngineeringSchema : operation === 'save_photo_title' ? savePhotoTitleSchema : deletePhotoTitleSchema;
    const parsed = schema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos da configuração.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, operation, parsed.data, 'em.engineering.manage', access.sso);
    if (result.ok && operation === 'delete_photo_title') {
      const checked = photoTitleDeletionResultSchema.safeParse(result.data);
      if (!checked.success || checked.data.id !== parsed.data.id || checked.data.record.id !== parsed.data.id) {
        return { ok: false, ...engineeringMutationError('UNAVAILABLE') };
      }
      return { ok: true, data: { operation: 'delete_photo_title', id: checked.data.id, projeto_id: null,
        updated_at: checked.data.updated_at, idempotent_replay: checked.data.idempotent_replay, record: { id: checked.data.id } } };
    }
    if (!result.ok && operation === 'delete_photo_title' && result.code === '23503') return { ok: false, code: result.code, error: 'Este título está vinculado a fotos ou modelos e não pode ser excluído. Os registros foram preservados.' };
    return !result.ok && ['23503', '23505'].includes(result.code) ? { ok: false, ...engineeringMutationError(result.code) } : result;
  }
  return {
    saveEngineering: (input: unknown) => execute('save_engineering', input),
    savePhotoTitle: (input: unknown) => execute('save_photo_title', input),
    deletePhotoTitle: (input: unknown) => execute('delete_photo_title', input),
  };
}
