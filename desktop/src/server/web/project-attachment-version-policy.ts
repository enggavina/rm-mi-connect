import { z } from 'zod';
import { projectAttachmentSchema } from './project-dossier-policy';

const uuid = z.string().uuid().transform(value => value.toLowerCase());
const timestamp = z.string().datetime({ offset: true }), text = z.string().nullable(), hash = z.string().regex(/^[a-f0-9]{64}$/);
export const projectAttachmentVersionSchema = projectAttachmentSchema.extend({
  submissionId: uuid, projeto_id: uuid, source_attachment_id: uuid, expected_attachment_updated_at: timestamp,
  expected_context_version: hash, motivo: z.string().trim().min(1).max(2000).refine(value => !value.includes('\u0000')),
  confirm_change: z.literal(true),
}).strict();
export type ProjectAttachmentVersionInput = z.infer<typeof projectAttachmentVersionSchema>;
export const projectAttachmentMetadataSchema = z.object({
  id: uuid, projeto_id: uuid, nome: text, descricao: text, tipo_arquivo: text, status: text,
  data_vencimento: timestamp.nullable(), created_at: timestamp, updated_at: timestamp, created_by: uuid.nullable(),
  visivel_cliente: z.boolean().nullable(), author_name: text, author_registration: text, has_file: z.boolean(),
  filename: text, byte_size: z.number().int().nonnegative().nullable(),
}).strict();
export const projectAttachmentSnapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, updated_at: timestamp, status_pcp: text,
    data_real_de_entrega: timestamp.nullable(), closed: z.boolean() }).strict(),
  attachment: projectAttachmentMetadataSchema,
  series: z.object({ root_id: uuid, head_id: uuid, head_updated_at: timestamp, selected_revision: z.number().int().positive(), head_revision: z.number().int().positive() }).strict().nullable(),
  can_replace: z.boolean(), reason: text, context_version: hash,
  history: z.object({ total: z.number().int().nonnegative(), page: z.number().int().positive(), page_size: z.literal(25),
    items: z.array(projectAttachmentMetadataSchema.extend({ revision: z.number().int().positive(), motivo: text, current: z.boolean() }).strict()).max(25) }).strict(),
}).strict();
export type ProjectAttachmentSnapshot = z.infer<typeof projectAttachmentSnapshotSchema>;
export const attachmentVersionReservationSchema = z.object({ upload_id: uuid, projeto_id: uuid, path: z.string(), mime_type: z.string(),
  byte_size: z.number().int().positive(), sha256: hash, source_attachment_id: uuid, root_attachment_id: uuid,
  revision: z.number().int().min(2), context_version: hash });
export const attachmentVersionResultSchema = z.object({ upload_id: uuid, projeto_id: uuid, attachment_id: uuid, source_attachment_id: uuid,
  root_attachment_id: uuid, revision: z.number().int().min(2), nome: z.string(), descricao: text, tipo_arquivo: z.string(),
  status: z.enum(['No prazo', 'Vencido']), data_vencimento: timestamp.nullable(), visivel_cliente: z.literal(false), updated_at: timestamp,
  project_updated_at: timestamp, context_version: hash });
