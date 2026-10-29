import { z } from 'zod';
import { uuid } from './policy';

export const queuePriorities = ['muito_baixa', 'baixa', 'media', 'alta', 'muito_alta'] as const;
export type QueuePriority = typeof queuePriorities[number];
export const receivingReasons = ['without_number', 'without_type', 'without_allocation', 'awaiting_arrival', 'legacy_type_locked'] as const;
export type ReceivingReason = 'all' | typeof receivingReasons[number];

/** These are opaque revisions, not dates to round through a JavaScript Date. */
export const saveCellQueueSchema = z.object({
  submissionId: uuid,
  celula_id: uuid,
  expected_queue_version: z.string().regex(/^[0-9a-f]{64}$/),
  apply_order: z.boolean(),
  items: z.array(z.object({
    id: uuid,
    expected_updated_at: z.string().datetime({ offset: true }),
    prioridade: z.enum(queuePriorities).nullable(),
  }).strict()).min(1).max(2000),
}).strict().superRefine((value, context) => {
  if (new Set(value.items.map(item => item.id)).size !== value.items.length) {
    context.addIssue({ code: 'custom', path: ['items'], message: 'A fila contém uma alocação repetida.' });
  }
});

export type SaveCellQueueInput = z.infer<typeof saveCellQueueSchema>;
