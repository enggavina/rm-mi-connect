import { z } from 'zod';
const uuid = z.string().uuid(), timestamp = z.string().datetime({ offset: true });
const base = { submissionId: uuid, projeto_id: uuid, expected_project_updated_at: timestamp };
const folder = { folder_id: uuid, expected_folder_updated_at: timestamp };
const nome = z.string().trim().min(1).max(200).refine(value => !/[\\/\u0000-\u001f\u007f]/.test(value) && !['.', '..'].includes(value), 'Informe um nome de pasta válido.');
export const manageProjectDocumentsSchema = z.discriminatedUnion('action', [
  z.object({ ...base, action: z.literal('create_folder'), parent_id: uuid.nullable(), nome }).strict(),
  z.object({ ...base, ...folder, action: z.literal('rename_folder'), nome }).strict(),
  z.object({ ...base, ...folder, action: z.literal('move_folder'), parent_id: uuid.nullable(), confirm_change: z.literal(true) }).strict(),
  z.object({ ...base, ...folder, action: z.literal('delete_folder'), confirm_change: z.literal(true) }).strict(),
  z.object({ ...base, action: z.literal('move_document'), source: z.enum(['docs', 'documents']), document_id: uuid,
    folder_id: uuid.nullable(), expected_folder_id: uuid.nullable(), confirm_change: z.literal(true) }).strict(),
]);
export type ManageProjectDocumentsInput = z.infer<typeof manageProjectDocumentsSchema>;
