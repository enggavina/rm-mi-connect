import { hasWebCapability } from './auth-policy';
import { z } from 'zod';
import { manageProjectDocumentsSchema } from './project-document-folder-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

export function createProjectDocumentFolderActions(dependencies: { actionUser: typeof actionUser; mutate: typeof mutate }) {
  async function manageProjectDocuments(input: unknown): Promise<WebActionResult> {
    const access = await dependencies.actionUser('em.projects.manage');
    if ('ok' in access) return access;
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.projects.read', 'em.documents.read'] as const).every(capability => hasWebCapability(access, capability))) {
      return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar os documentos deste projeto.' };
    }
    const parsed = manageProjectDocumentsSchema.safeParse(input);
    if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira o nome da pasta, o destino e a confirmação.', fieldErrors: parsed.error.flatten().fieldErrors };
    const result = await dependencies.mutate(access.client, 'manage_project_documents', parsed.data, 'em.projects.manage', access.sso);
    if (!result.ok) return result.code === '22023' && parsed.data.action === 'delete_folder'
      ? { ...result, error: 'A pasta precisa estar vazia, sem subpastas, documentos ou envios pendentes. Confira também se o projeto continua aberto.' } : result;
    const data = result.data, request = parsed.data;
    const expectedId = request.action === 'create_folder' ? request.submissionId : request.action === 'move_document' ? request.document_id : request.folder_id;
    if (data.operation !== 'manage_project_documents' || data.projeto_id !== request.projeto_id || data.id !== expectedId
      || !z.string().datetime({ offset: true }).safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || data.record?.action !== request.action
      || (request.action === 'move_document'
        ? data.record.document_id !== request.document_id || data.record.source !== request.source || data.record.folder_id !== request.folder_id
        : data.record.id !== expectedId || data.record.projeto_id !== request.projeto_id
          || ((request.action === 'create_folder' || request.action === 'rename_folder') && data.record.nome !== request.nome)
          || ((request.action === 'create_folder' || request.action === 'move_folder') && data.record.parent_id !== request.parent_id))) {
      return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a alteração. Tente novamente com o mesmo protocolo.' };
    }
    return { ok: true, data: { operation: data.operation, id: data.id, projeto_id: data.projeto_id, updated_at: data.updated_at, idempotent_replay: data.idempotent_replay,
      record: request.action === 'move_document' ? { action: request.action, document_id: request.document_id, source: request.source, folder_id: request.folder_id }
        : { action: request.action, folder_id: data.id, nome: data.record.nome, parent_id: data.record.parent_id } } };
  }
  return { manageProjectDocuments };
}
