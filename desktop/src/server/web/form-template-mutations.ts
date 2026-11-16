import { createFormTemplateSchema, saveFormTemplateSchema, publishFormTemplateSchema, deleteFormTemplateSchema, formTemplateMutationError } from './form-template-policy';
import { formDraftDto } from './form-template-dto';
import { z } from 'zod';
import type { actionUser, mutate, WebActionResult } from './mutation';
const schemas = { create_form_template: createFormTemplateSchema, save_form_template: saveFormTemplateSchema, publish_form_template: publishFormTemplateSchema, delete_form_template: deleteFormTemplateSchema };

export function createFormTemplateActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function execute(operation: keyof typeof schemas, input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.form_templates.manage');
    if ('ok' in access) return access;
    if (access.profile.perfil !== 'administrador') return { ok: false, ...formTemplateMutationError('42501') };
    const parsed = schemas[operation].safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o conteúdo do modelo.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, operation, parsed.data, 'em.form_templates.manage', access.sso);
    if (!result.ok) {
      if (operation === 'delete_form_template' && result.code === '23503') return { ok: false, code: result.code,
        error: 'O modelo possui vínculos, publicações relacionadas ou histórico de uso. Remova apenas modelos sem dependências; respostas e históricos são preservados.' };
      return ['23503','23505'].includes(result.code) ? { ok: false, ...formTemplateMutationError(result.code) } : result;
    }
    // SQL's stored source metadata includes a cover URL; never forward raw
    // record/snapshot/publication envelopes from a Server Action to the client.
    try {
      if (operation === 'delete_form_template') {
        if (result.data.operation !== operation || result.data.id !== parsed.data.id || result.data.projeto_id !== null
          || !z.string().datetime({ offset: true }).safeParse(result.data.updated_at).success || typeof result.data.idempotent_replay !== 'boolean'
          || result.data.record.id !== parsed.data.id || result.data.record.deleted !== true || !('kind' in parsed.data) || result.data.record.kind !== parsed.data.kind) throw new Error('Invalid deletion result');
        return { ok: true, data: { operation, id: parsed.data.id, projeto_id: null, updated_at: result.data.updated_at,
          idempotent_replay: result.data.idempotent_replay, record: { id: parsed.data.id, kind: parsed.data.kind, deleted: true } } };
      }
      return { ok: true, data: { operation: result.data.operation, id: result.data.id, projeto_id: null,
        updated_at: result.data.updated_at, idempotent_replay: result.data.idempotent_replay,
        record: { ...formDraftDto(result.data.record) } } };
    } catch { return { ok: false, ...formTemplateMutationError() }; }
  }
  return {
    createFormTemplate: (input: unknown) => execute('create_form_template', input),
    saveFormTemplate: (input: unknown) => execute('save_form_template', input),
    publishFormTemplate: (input: unknown) => execute('publish_form_template', input),
    deleteFormTemplate: (input: unknown) => execute('delete_form_template', input),
  };
}
