import { createFormTemplateSchema, saveFormTemplateSchema, publishFormTemplateSchema, formTemplateMutationError } from './form-template-policy';
import { formDraftDto } from './form-template-dto';
import type { actionUser, mutate, WebActionResult } from './mutation';
const schemas = { create_form_template: createFormTemplateSchema, save_form_template: saveFormTemplateSchema, publish_form_template: publishFormTemplateSchema };

export function createFormTemplateActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function execute(operation: keyof typeof schemas, input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.form_templates.manage');
    if ('ok' in access) return access;
    if (access.profile.perfil !== 'administrador') return { ok: false, ...formTemplateMutationError('42501') };
    const parsed = schemas[operation].safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o conteúdo do modelo.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, operation, parsed.data, 'em.form_templates.manage', access.sso);
    if (!result.ok) return ['23503','23505'].includes(result.code) ? { ok: false, ...formTemplateMutationError(result.code) } : result;
    // SQL's stored source metadata includes a cover URL; never forward raw
    // record/snapshot/publication envelopes from a Server Action to the client.
    try {
      return { ok: true, data: { operation: result.data.operation, id: result.data.id, projeto_id: null,
        updated_at: result.data.updated_at, idempotent_replay: result.data.idempotent_replay,
        record: { ...formDraftDto(result.data.record) } } };
    } catch { return { ok: false, ...formTemplateMutationError() }; }
  }
  return {
    createFormTemplate: (input: unknown) => execute('create_form_template', input),
    saveFormTemplate: (input: unknown) => execute('save_form_template', input),
    publishFormTemplate: (input: unknown) => execute('publish_form_template', input),
  };
}
