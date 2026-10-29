import { engineeringMutationError, saveEngineeringSchema, savePhotoTitleSchema } from './engineering-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

export function createEngineeringActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function execute(operation: 'save_engineering' | 'save_photo_title', input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.engineering.manage');
    if ('ok' in access) return access;
    if (access.profile.perfil !== 'administrador') return { ok: false, ...engineeringMutationError('42501') };
    const parsed = (operation === 'save_engineering' ? saveEngineeringSchema : savePhotoTitleSchema).safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos da configuração.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, operation, parsed.data, 'em.engineering.manage', access.sso);
    return !result.ok && ['23503', '23505'].includes(result.code) ? { ok: false, ...engineeringMutationError(result.code) } : result;
  }
  return {
    saveEngineering: (input: unknown) => execute('save_engineering', input),
    savePhotoTitle: (input: unknown) => execute('save_photo_title', input),
  };
}
