import { freezeEngineeringRequest } from './engineering-model';

export const DOSSIER_MAX_FILE_BYTES = 20 * 1024 * 1024;
export const DOSSIER_FILE_ACCEPT = '.pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png';
export type DossierDocumentStatus = 'No prazo' | 'Vencido';
export type DossierCommentAllocation = { id: string; projeto_id: string; celula_id: string; updated_at: string; retirada?: boolean; visibilidade?: boolean; name: string };
export type DossierCommentRequest = { submissionId: string; projeto_id: string; celula_projeto_id: string; expected_project_updated_at: string; expected_allocation_updated_at: string; evento: string };
export type DossierAttachmentRequest = { submissionId: string; projeto_id: string; expected_project_updated_at: string; nome: string; descricao: string | null; filename: string; mime_type: string; byte_size: number; sha256: string; data_vencimento: string | null; status: DossierDocumentStatus };

export function dossierCommentRequest(projectId: string, projectVersion: string, allocation: DossierCommentAllocation | undefined, text: string, submissionId: string): DossierCommentRequest {
  if (!allocation || allocation.projeto_id !== projectId || allocation.retirada) throw new Error('Selecione uma célula ativa deste projeto.');
  const evento = text.trim();
  if (!evento || evento.length > 10_000) throw new Error('Informe um comentário de até 10.000 caracteres.');
  return freezeEngineeringRequest({ submissionId, projeto_id: projectId, celula_projeto_id: allocation.id,
    expected_project_updated_at: projectVersion, expected_allocation_updated_at: allocation.updated_at, evento });
}

export function dossierFileError(file: Pick<File, 'name' | 'size' | 'type'>): string | null {
  if (!file.name || file.name.length > 180 || /[\\/\u0000-\u001f\u007f]/.test(file.name)) return 'O nome do arquivo deve ter até 180 caracteres, sem barras ou caracteres de controle.';
  if (!Number.isInteger(file.size) || file.size <= 0) return 'Selecione um arquivo que contenha dados.';
  if (file.size > DOSSIER_MAX_FILE_BYTES) return 'O arquivo deve ter no máximo 20 MiB.';
  const extensions: Record<string, RegExp> = { 'application/pdf': /\.pdf$/i, 'image/jpeg': /\.jpe?g$/i, 'image/png': /\.png$/i };
  if (!extensions[file.type]?.test(file.name)) return 'Selecione um arquivo PDF, JPEG ou PNG com a extensão correspondente.';
  return null;
}

export function dossierExpiry(value: string): string | null {
  if (!value) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Confira a data de vencimento.');
  const date = new Date(`${value}T12:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) throw new Error('Confira a data de vencimento.');
  return date.toISOString();
}

export function dossierAttachmentRequest(projectId: string, projectVersion: string, file: Pick<File, 'name' | 'size' | 'type'>,
  draft: { nome: string; descricao: string; status: string; expiry: string }, sha256: string, submissionId: string): DossierAttachmentRequest {
  const error = dossierFileError(file); if (error) throw new Error(error);
  const nome = draft.nome.trim(), descricao = draft.descricao.trim();
  if (!nome || nome.length > 200) throw new Error('Informe um título de até 200 caracteres para o anexo.');
  if (descricao.length > 2000) throw new Error('A observação deve ter até 2.000 caracteres.');
  if (!['No prazo', 'Vencido'].includes(draft.status)) throw new Error('Selecione o status do documento.');
  if (!/^[0-9a-f]{64}$/.test(sha256)) throw new Error('Não foi possível conferir o arquivo. Selecione-o novamente.');
  return freezeEngineeringRequest({ submissionId, projeto_id: projectId, expected_project_updated_at: projectVersion, nome,
    descricao: descricao || null, filename: file.name, mime_type: file.type, byte_size: file.size, sha256,
    data_vencimento: dossierExpiry(draft.expiry), status: draft.status as DossierDocumentStatus });
}
