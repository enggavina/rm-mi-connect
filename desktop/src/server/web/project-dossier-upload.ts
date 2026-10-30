import { createHash } from 'node:crypto';
import { z } from 'zod';
import { hasWebCapability, sameOriginPost } from './auth-policy';
import { MAX_PROJECT_ATTACHMENT_BYTES, attachmentSignatureMatches, projectAttachmentPath, projectAttachmentSchema, type ProjectAttachmentInput } from './project-dossier-policy';
import type { actionUser, mutate, WebActionResult } from './mutation';

type Dependencies = { actionUser: typeof actionUser; mutate: typeof mutate; storeAttachment: (input: ProjectAttachmentInput, bytes: Uint8Array) => Promise<void> };
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
const timestamp = z.string().datetime({ offset: true });
const fail = (code: string, error: string): WebActionResult => ({ ok: false, code, error });
const unavailable = () => fail('UNAVAILABLE', 'Não foi possível confirmar o anexo. Tente novamente com o mesmo arquivo e protocolo.');
export function attachmentUploadResponse(result: WebActionResult, status?: number) {
  const code = result.ok ? '' : result.code;
  return Response.json(result, { status: status ?? (result.ok ? 200 : code === 'CORP_UNAUTHORIZED' ? 401
    : ['42501', 'CORP_FORBIDDEN'].includes(code) ? 403 : ['PT409', 'P0002', '23505', '40001'].includes(code) ? 409
      : ['INVALID_INPUT', '22023', '22P02', '23514', '23503'].includes(code) ? 400 : 503), headers });
}
const response = attachmentUploadResponse;
/** Reserve and finalization use distinct, deterministic receipts for one frozen intent. */
export function attachmentReservationId(submissionId: string) {
  const bytes = createHash('sha256').update(`em-dossier-reserve:${submissionId}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
export class AttachmentBodyTooLarge extends Error {}
const BodyTooLarge = AttachmentBodyTooLarge;
export async function boundedAttachmentForm(request: Request): Promise<FormData> {
  const maximum = MAX_PROJECT_ATTACHMENT_BYTES + 64 * 1024;
  const contentLength = request.headers.get('content-length');
  if (contentLength && (!/^\d+$/.test(contentLength) || Number(contentLength) > maximum)) throw new BodyTooLarge();
  if (!request.body) throw new Error('Missing upload');
  const reader = request.body.getReader(), chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const chunk = await reader.read(); if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > maximum) { await reader.cancel(); throw new BodyTooLarge(); }
      chunks.push(chunk.value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new Response(bytes, { headers: { 'Content-Type': request.headers.get('content-type')! } }).formData();
}
const boundedForm = boundedAttachmentForm;
export async function handleProjectAttachmentUpload(request: Request, projectId: string, dependencies: Dependencies): Promise<Response> {
  if (!sameOriginPost(request.headers.get('origin'), request.headers.get('host'))) return response(fail('42501', 'Origem da solicitação não autorizada.'), 403);
  if (!z.string().uuid().safeParse(projectId).success) return response(fail('INVALID_INPUT', 'Projeto inválido.'), 400);
  try {
    const access = await dependencies.actionUser('em.projects.manage');
    if ('ok' in access) return response(access);
    if (!['administrador', 'padr_o'].includes(access.profile.perfil)
      || !(['em.portal.read', 'em.projects.read', 'em.documents.read'] as const).every(capability => hasWebCapability(access, capability))) {
      return response(fail('42501', 'Seu acesso permite apenas consultar os documentos do projeto.'));
    }
    if (!/^multipart\/form-data;\s*boundary=/i.test(request.headers.get('content-type') || '')) return response(fail('INVALID_INPUT', 'Selecione um arquivo PDF, JPEG ou PNG.'), 415);
    let form: FormData;
    try { form = await boundedForm(request); }
    catch (error) { return response(fail('INVALID_INPUT', error instanceof BodyTooLarge ? 'Use um arquivo de até 20 MiB.' : 'Não foi possível ler o arquivo selecionado.'), error instanceof BodyTooLarge ? 413 : 400); }
    const rawInput = form.get('input'), file = form.get('file');
    if ([...form.keys()].length !== 2 || form.getAll('input').length !== 1 || form.getAll('file').length !== 1
      || typeof rawInput !== 'string' || rawInput.length > 8192 || !file || typeof file === 'string') return response(fail('INVALID_INPUT', 'Confira os dados e o arquivo do anexo.'));
    if (file.size > MAX_PROJECT_ATTACHMENT_BYTES) return response(fail('INVALID_INPUT', 'Use um arquivo de até 20 MiB.'), 413);
    let decoded: unknown; try { decoded = JSON.parse(rawInput); } catch { return response(fail('INVALID_INPUT', 'Confira os dados do anexo.')); }
    const parsed = projectAttachmentSchema.safeParse(decoded);
    if (!parsed.success || parsed.data.projeto_id !== projectId) return response(fail('INVALID_INPUT', 'Confira o projeto, os dados e o arquivo do anexo.'));
    const input = parsed.data;
    if (file.size !== input.byte_size || file.name !== input.filename || file.type !== input.mime_type) return response(fail('INVALID_INPUT', 'O arquivo mudou desde a seleção. Confira os dados antes de enviar.'));
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (createHash('sha256').update(bytes).digest('hex') !== input.sha256 || !attachmentSignatureMatches(bytes, input.mime_type)) {
      return response(fail('INVALID_INPUT', 'O conteúdo do arquivo não corresponde ao tipo ou à seleção informada.'), 415);
    }
    const { submissionId, ...metadata } = input;
    const reserve = await dependencies.mutate(access.client, 'reserve_project_attachment', {
      submissionId: attachmentReservationId(submissionId), upload_id: submissionId, ...metadata,
    }, 'em.projects.manage', access.sso);
    if (!reserve.ok) return response(reserve);
    const expectedPath = projectAttachmentPath(projectId, submissionId, input.mime_type), reservation = reserve.data.record;
    if (reserve.data.operation !== 'reserve_project_attachment' || reserve.data.id !== submissionId || reserve.data.projeto_id !== projectId
      || !timestamp.safeParse(reserve.data.updated_at).success || typeof reserve.data.idempotent_replay !== 'boolean'
      || !reservation || typeof reservation !== 'object' || reservation.upload_id !== submissionId || reservation.projeto_id !== projectId || reservation.path !== expectedPath
      || reservation.sha256 !== input.sha256 || reservation.byte_size !== input.byte_size || reservation.mime_type !== input.mime_type) return response(unavailable());
    await dependencies.storeAttachment(input, bytes);
    const final = await dependencies.mutate(access.client, 'finalize_project_attachment', {
      submissionId, projeto_id: projectId, upload_id: submissionId,
    }, 'em.projects.manage', access.sso);
    if (!final.ok) return response(final);
    const data = final.data, record = data.record;
    if (data.operation !== 'finalize_project_attachment' || data.id !== submissionId || data.projeto_id !== projectId
      || !timestamp.safeParse(data.updated_at).success || typeof data.idempotent_replay !== 'boolean'
      || !record || typeof record !== 'object' || record.upload_id !== submissionId || record.attachment_id !== submissionId || record.projeto_id !== projectId
      || record.nome !== input.nome || record.descricao !== input.descricao || record.tipo_arquivo !== input.mime_type
      || record.status !== input.status || record.visivel_cliente !== false || record.updated_at !== data.updated_at
      || (input.data_vencimento === null ? record.data_vencimento !== null : typeof record.data_vencimento !== 'string'
        || Date.parse(record.data_vencimento) !== Date.parse(input.data_vencimento))) return response(unavailable());
    return response({ ok: true, data: { operation: data.operation, id: data.id, projeto_id: projectId, updated_at: data.updated_at,
      idempotent_replay: data.idempotent_replay, record: { upload_id: submissionId, projeto_id: projectId, attachment_id: submissionId,
        nome: record.nome, descricao: record.descricao, tipo_arquivo: record.tipo_arquivo, status: record.status,
        data_vencimento: record.data_vencimento, visivel_cliente: false, updated_at: record.updated_at } } });
  } catch { return response(unavailable()); }
}
