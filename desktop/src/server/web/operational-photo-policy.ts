import { z } from 'zod';
import { uuid } from './policy';

const timestamp = z.string().datetime({ offset: true });
const common = {
  submissionId: uuid,
  projeto_id: uuid,
  celula_projeto_id: uuid,
  expected_project_updated_at: timestamp,
  expected_allocation_updated_at: timestamp,
  expected_photos_version: z.string().regex(/^[0-9a-f]{64}$/),
};
const target = { foto_id: uuid, expected_foto_updated_at: timestamp };

export const manageOperationalPhotosSchema = z.discriminatedUnion('action', [
  z.object({ ...common, action: z.literal('add'), items: z.array(z.object({ id: uuid, cadastro_foto_id: uuid }).strict()).min(1).max(100) }).strict(),
  z.object({ ...common, ...target, action: z.literal('tag'), tag: z.string().max(2000).nullable() }).strict(),
  z.object({ ...common, ...target, action: z.literal('retire') }).strict(),
  z.object({ ...common, ...target, action: z.literal('restore') }).strict(),
]).superRefine((value, context) => {
  if (value.action === 'add' && (new Set(value.items.map(item => item.id)).size !== value.items.length
    || new Set(value.items.map(item => item.cadastro_foto_id)).size !== value.items.length)) {
    context.addIssue({ code: 'custom', path: ['items'], message: 'Selecione cada título uma única vez.' });
  }
});

export type ManageOperationalPhotosInput = z.infer<typeof manageOperationalPhotosSchema>;

export const operationalPhotoResultSchema = z.object({
  projeto_id: uuid, celula_projeto_id: uuid, action: z.enum(['add', 'tag', 'retire', 'restore']),
  photos_version: z.string().regex(/^[0-9a-f]{64}$/), changed_ids: z.array(uuid).max(100),
});
