import { z } from 'zod';
import { uuid } from './policy';

export const projectPhotoSelectionSchema = z.object({
  submissionId: uuid,
  projeto_id: uuid,
  foto_id: uuid,
  expected_updated_at: z.string().datetime({ offset: true }),
  selected: z.boolean(),
}).strict();

export type ProjectPhotoSelectionInput = z.infer<typeof projectPhotoSelectionSchema>;
export type ProjectPhotoFilters = { photoPage?: number | string; selection?: string; photoOrder?: string };

export function projectPhotoFilters(filters: ProjectPhotoFilters) {
  return { selectedOnly: filters.selection === 'selected', selectedFirst: filters.photoOrder === 'selected' };
}
