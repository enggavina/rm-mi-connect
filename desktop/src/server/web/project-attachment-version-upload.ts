import { createHash } from 'node:crypto';
import { z } from 'zod';
import { hasWebCapability, sameOriginPost } from './auth-policy';
import { MAX_PROJECT_ATTACHMENT_BYTES, attachmentSignatureMatches, projectAttachmentPath, type ProjectAttachmentInput } from './project-dossier-policy';
import { AttachmentBodyTooLarge, attachmentUploadResponse as response, boundedAttachmentForm } from './project-dossier-upload';
import { projectAttachmentVersionSchema, attachmentVersionReservationSchema, attachmentVersionResultSchema } from './project-attachment-version-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

type Dependencies = { actionUser: typeof actionUser; mutate: typeof mutate; storeAttachment: (input: ProjectAttachmentInput, bytes: Uint8Array) => Promise<void> };
const timestamp = z.string().datetime({ offset: true }), uuid = z.string().uuid();
const fail = (code: string, error: string): WebActionResult => ({ ok: false, code, error });
const unavailable = () => fail('UNAVAILABLE', 'Não foi possível confirmar a nova versão. Tente novamente com o mesmo arquivo e protocolo.');
export function attachmentVersionReservationId(submissionId: string) {
  const bytes = createHash('sha256').update(`em-dossier-version-reserve:${submissionId}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
export async function handleProjectAttachmentVersionUpload(request: Request, projectId: string, attachmentId: string, dependencies: Dependencies): Promise<Response> {
  if (!sameOriginPost(request.headers.get('origin'), request.headers.get('host'))) return response(fail('42501', 'Origem da solicitação não autorizada.'), 403);
  if (!uuid.safeParse(projectId).success || !uuid.safeParse(attachmentId).success) return response(fail('INVALID_INPUT', 'Projeto ou anexo inválido.'), 400);
  projectId = projectId.toLowerCase(); attachmentId = attachmentId.toLowerCase();
  try {
    const access = await dependencies.actionUser('em.projects.manage'); if ('ok' in access) return response(access);
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.projects.read', 'em.documents.read'] as const).every(capability => hasWebCapability(access, capability))) {
      return response(fail('42501', 'Seu acesso permite apenas consultar as versões deste anexo.'));
    }
    if (!/^multipart\/form-data;\s*boundary=/i.test(request.headers.get('content-type') || '')) return response(fail('INVALID_INPUT', 'Selecione um arquivo PDF, JPEG ou PNG.'), 415);
    let form: FormData;
    try { form = await boundedAttachmentForm(request); }
    catch (error) { return response(fail('INVALID_INPUT', error instanceof AttachmentBodyTooLarge ? 'Use um arquivo de até 20 MiB.' : 'Não foi possível ler o arquivo selecionado.'), error instanceof AttachmentBodyTooLarge ? 413 : 400); }
    const raw = form.get('input'), file = form.get('file');
    if ([...form.keys()].length !== 2 || form.getAll('input').length !== 1 || form.getAll('file').length !== 1 || typeof raw !== 'string'
      || raw.length > 12_288 || !file || typeof file === 'string') return response(fail('INVALID_INPUT', 'Confira os dados e o arquivo da nova versão.'));
    if (file.size > MAX_PROJECT_ATTACHMENT_BYTES) return response(fail('INVALID_INPUT', 'Use um arquivo de até 20 MiB.'), 413);
    let decoded: unknown; try { decoded = JSON.parse(raw); } catch { return response(fail('INVALID_INPUT', 'Confira os dados da nova versão.')); }
    const parsed = projectAttachmentVersionSchema.safeParse(decoded);
    if (!parsed.success || parsed.data.projeto_id !== projectId || parsed.data.source_attachment_id !== attachmentId) return response(fail('INVALID_INPUT', 'Confira o projeto, o anexo e os dados da nova versão.'));
    const input = parsed.data, extensions: Record<string, RegExp> = { 'application/pdf': /\.pdf$/i, 'image/jpeg': /\.jpe?g$/i, 'image/png': /\.png$/i };
    if (file.size !== input.byte_size || file.name !== input.filename || file.type !== input.mime_type || !extensions[input.mime_type].test(file.name)) {
      return response(fail('INVALID_INPUT', 'O arquivo mudou desde a seleção ou não corresponde ao tipo informado.'));
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (createHash('sha256').update(bytes).digest('hex') !== input.sha256 || !attachmentSignatureMatches(bytes, input.mime_type)) return response(fail('INVALID_INPUT', 'O conteúdo do arquivo não corresponde ao tipo ou à seleção informada.'), 415);
    const { submissionId, ...metadata } = input;
    const reserve = await dependencies.mutate(access.client, 'reserve_project_attachment_version', { submissionId: attachmentVersionReservationId(submissionId), upload_id: submissionId, ...metadata }, 'em.projects.manage', access.sso);
    if (!reserve.ok) return response(reserve);
    const reservation = attachmentVersionReservationSchema.safeParse(reserve.data.record);
    if (reserve.data.operation !== 'reserve_project_attachment_version' || reserve.data.id !== submissionId || reserve.data.projeto_id !== projectId
      || !timestamp.safeParse(reserve.data.updated_at).success || typeof reserve.data.idempotent_replay !== 'boolean' || !reservation.success
      || reservation.data.upload_id !== submissionId || reservation.data.projeto_id !== projectId || reservation.data.source_attachment_id !== attachmentId
      || reservation.data.path !== projectAttachmentPath(projectId, submissionId, input.mime_type) || reservation.data.mime_type !== input.mime_type
      || reservation.data.byte_size !== input.byte_size || reservation.data.sha256 !== input.sha256 || reservation.data.context_version !== input.expected_context_version) return response(unavailable());
    await dependencies.storeAttachment(input, bytes);
    const final = await dependencies.mutate(access.client, 'finalize_project_attachment_version', { submissionId, projeto_id: projectId, upload_id: submissionId }, 'em.projects.manage', access.sso);
    if (!final.ok) return response(final);
    const data = final.data, result = attachmentVersionResultSchema.safeParse(data.record);
    if (data.operation !== 'finalize_project_attachment_version' || data.id !== submissionId || data.projeto_id !== projectId
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean' || !result.success
      || result.data.upload_id !== submissionId || result.data.attachment_id !== submissionId || result.data.projeto_id !== projectId || result.data.source_attachment_id !== attachmentId
      || result.data.root_attachment_id !== reservation.data.root_attachment_id || result.data.revision !== reservation.data.revision
      || result.data.nome !== input.nome || result.data.descricao !== input.descricao || result.data.tipo_arquivo !== input.mime_type
      || result.data.status !== input.status || result.data.updated_at !== data.updated_at
      || (input.data_vencimento === null ? result.data.data_vencimento !== null : !result.data.data_vencimento || Date.parse(result.data.data_vencimento) !== Date.parse(input.data_vencimento))) return response(unavailable());
    return response({ ok: true, data: { operation: data.operation, id: data.id, projeto_id: projectId, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: result.data } });
  } catch { return response(unavailable()); }
}
