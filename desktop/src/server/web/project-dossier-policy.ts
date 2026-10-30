import { z } from 'zod';

export const MAX_PROJECT_ATTACHMENT_BYTES = 20 * 1024 * 1024;
export const PROJECT_ATTACHMENT_MIME_TYPES = ['application/pdf', 'image/jpeg', 'image/png'] as const;
const uuid = z.string().uuid(), timestamp = z.string().datetime({ offset: true });
const text = (max: number) => z.string().trim().max(max).refine(value => !value.includes('\u0000'));
export const addProjectCommentSchema = z.object({
  submissionId: uuid, projeto_id: uuid, celula_projeto_id: uuid,
  expected_project_updated_at: timestamp, expected_allocation_updated_at: timestamp,
  evento: text(10_000).refine(value => value.length > 0),
}).strict();
export const projectAttachmentSchema = z.object({
  submissionId: uuid, projeto_id: uuid, expected_project_updated_at: timestamp,
  nome: text(200).refine(value => value.length > 0), descricao: text(2000).nullable().transform(value => value || null),
  filename: z.string().min(1).max(180).regex(/^[^/\\\x00-\x1f\x7f]+$/),
  mime_type: z.enum(PROJECT_ATTACHMENT_MIME_TYPES), byte_size: z.number().int().positive().max(MAX_PROJECT_ATTACHMENT_BYTES),
  sha256: z.string().regex(/^[0-9a-f]{64}$/), data_vencimento: timestamp.nullable(), status: z.enum(['No prazo', 'Vencido']),
}).strict();
export type ProjectAttachmentInput = z.infer<typeof projectAttachmentSchema>;
export function projectAttachmentPath(projectId: string, uploadId: string, mime: ProjectAttachmentInput['mime_type']) {
  return `web-dossier/${projectId}/${uploadId}.${mime === 'application/pdf' ? 'pdf' : mime === 'image/png' ? 'png' : 'jpg'}`;
}
export function attachmentSignatureMatches(bytes: Uint8Array, mime: ProjectAttachmentInput['mime_type']) {
  if (mime === 'application/pdf') return bytes.length >= 5 && [37, 80, 68, 70, 45].every((value, index) => bytes[index] === value);
  if (mime === 'image/png') return bytes.length >= 8 && [137, 80, 78, 71, 13, 10, 26, 10].every((value, index) => bytes[index] === value);
  return bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
}
