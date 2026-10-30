import { z } from 'zod';

const uuid = z.string().uuid().transform(value => value.toLowerCase());
const timestamp = z.string().datetime({ offset: true }), text = z.string().nullable();
const hash = z.string().regex(/^[a-f0-9]{64}$/);
const content = (max: number) => z.string().trim().min(1).max(max).refine(value => !value.includes('\u0000'));
export const editProjectCommentSchema = z.object({
  submissionId: uuid, projeto_id: uuid, comentario_id: uuid,
  expected_project_updated_at: timestamp, expected_comment_updated_at: timestamp,
  expected_context_version: hash, evento: content(10_000), motivo: content(2000), confirm_change: z.literal(true),
}).strict();
export type EditProjectCommentInput = z.infer<typeof editProjectCommentSchema>;
export const projectCommentSnapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, updated_at: timestamp, status_pcp: text,
    data_real_de_entrega: timestamp.nullable(), closed: z.boolean() }).strict(),
  comment: z.object({ id: uuid, projeto_id: uuid, celula_id: uuid.nullable(), cadastrado_por_id: uuid.nullable(),
    evento: text, created_at: timestamp, updated_at: timestamp, author_name: text, author_registration: text, cell_name: text }).strict(),
  allocation: z.object({ id: uuid, updated_at: timestamp, retirada: z.boolean() }).strict().nullable(),
  can_edit: z.boolean(), reason: text, context_version: hash,
  history: z.object({ total: z.number().int().nonnegative(), page: z.number().int().positive(), page_size: z.literal(25),
    items: z.array(z.object({ id: uuid, revision: z.number().int().positive(), evento_anterior: text, evento_novo: z.string(),
      motivo: z.string(), editor_id: uuid, editor_name: text, editor_registration: text, created_at: timestamp }).strict()).max(25) }).strict(),
}).strict();
export type ProjectCommentSnapshot = z.infer<typeof projectCommentSnapshotSchema>;
export const projectCommentResultSchema = z.object({ projeto_id: uuid, comentario_id: uuid, project_updated_at: timestamp,
  changed: z.boolean(), revision: z.number().int().nonnegative(), context_version: hash });
