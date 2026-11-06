import { catalogMutationError, deleteCatalogSchema, saveCatalogSchema } from './catalog-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

/** The same verified session and BFF mutation permit used by all web writes. */
export function createCatalogActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function execute(operation: 'save_catalog' | 'delete_catalog', input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.catalogs.manage');
    if ('ok' in access) return access;
    if (access.profile.perfil !== 'administrador') return { ok: false, ...catalogMutationError('42501') };
    const parsed = (operation === 'save_catalog' ? saveCatalogSchema : deleteCatalogSchema).safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos do cadastro.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, operation, parsed.data, 'em.catalogs.manage', access.sso);
    if (!result.ok && operation === 'delete_catalog' && parsed.data.kind === 'types' && result.code === '23503')
      return { ok: false, code: result.code, error: 'Este tipo de equipamento está em uso por equipamentos, projetos, roteiros ou registros relacionados e não pode ser excluído. Os vínculos foram preservados.' };
    return !result.ok && ['23503', '23505'].includes(result.code) ? { ok: false, ...catalogMutationError(result.code) } : result;
  }
  return { saveCatalog: (input: unknown) => execute('save_catalog', input), deleteCatalog: (input: unknown) => execute('delete_catalog', input) };
}
