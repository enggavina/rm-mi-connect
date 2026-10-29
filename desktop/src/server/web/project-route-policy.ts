import { z } from 'zod';
import { uuid } from './policy';

/** Revisions are opaque strings; never round them through a JavaScript Date. */
export const saveProjectRouteSchema = z.object({
  submissionId: uuid,
  projeto_id: uuid,
  expected_project_updated_at: z.string().datetime({ offset: true }),
  expected_route_version: z.string().regex(/^[0-9a-f]{64}$/),
  items: z.array(z.object({ id: uuid, expected_updated_at: z.string().datetime({ offset: true }) }).strict()).min(1).max(2000),
}).strict().superRefine((value, context) => {
  if (new Set(value.items.map(item => item.id)).size !== value.items.length) {
    context.addIssue({ code: 'custom', path: ['items'], message: 'O roteiro contém uma alocação repetida.' });
  }
});

export type SaveProjectRouteInput = z.infer<typeof saveProjectRouteSchema>;
