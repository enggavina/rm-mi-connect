import { z } from 'zod';
import { uuid } from './policy';

const timestamp = z.string().datetime({ offset: true });
const version = z.string().regex(/^[0-9a-f]{64}$/);
const common = {
  submissionId: uuid, projeto_id: uuid, celula_projeto_id: uuid,
  expected_project_updated_at: timestamp, expected_allocation_updated_at: timestamp,
  expected_context_version: version, confirm_change: z.literal(true),
};
export const manageCellAvailabilitySchema = z.discriminatedUnion('action', [
  z.object({ ...common, action: z.literal('set_visibility'), visibilidade: z.boolean() }).strict(),
  z.object({ ...common, action: z.literal('retire') }).strict(),
  z.object({ ...common, action: z.literal('restore') }).strict(),
]);
export type ManageCellAvailabilityInput = z.infer<typeof manageCellAvailabilitySchema>;

export const cellAvailabilityResultSchema = z.object({
  projeto_id: uuid, celula_projeto_id: uuid,
  action: z.enum(['set_visibility', 'retire', 'restore']),
  visibilidade: z.boolean(), retirada: z.boolean(), context_version: version,
  changed_ids: z.array(uuid).max(1),
});
