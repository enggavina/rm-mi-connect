import { z } from 'zod';
import { uuid } from './policy';

const timestamp = z.string().datetime({ offset: true });
export const assignFormReviewerSchema = z.object({
  submissionId: uuid,
  projeto_id: uuid,
  celula_projeto_id: uuid,
  form_id: uuid,
  avaliador_user_id: uuid,
  expected_project_updated_at: timestamp,
  expected_allocation_updated_at: timestamp,
  expected_context_version: z.string().regex(/^[0-9a-f]{64}$/),
  confirm_replace: z.boolean(),
}).strict();
export type AssignFormReviewerInput = z.infer<typeof assignFormReviewerSchema>;

export const formReviewerResultSchema = z.object({
  assignment_id: uuid,
  projeto_id: uuid,
  celula_projeto_id: uuid,
  celula_id: uuid,
  form_id: uuid,
  avaliador_user_id: uuid,
  context_version: z.string().regex(/^[0-9a-f]{64}$/),
  records_updated_ids: z.array(uuid).max(2000),
});
