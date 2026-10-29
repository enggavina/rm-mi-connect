import { z } from 'zod';
import { uuid } from './policy';

export const stageActions = ['liberar', 'retornar', 'aprovar'] as const;
const timestamp = z.string().datetime({ offset: true });

/** Versions remain the exact database strings; no date round-trip loses microseconds. */
export const transitionStageApprovalSchema = z.object({
  submissionId: uuid,
  aprovacao_etapa_id: uuid,
  expected_updated_at: timestamp,
  expected_cell_updated_at: timestamp,
  acao: z.enum(stageActions),
  observacao: z.string().max(10_000).nullable(),
}).strict().superRefine((value, context) => {
  if (value.acao === 'retornar' && !value.observacao?.trim()) context.addIssue({ code: 'custom', path: ['observacao'], message: 'Informe o motivo do retorno.' });
});

export type TransitionStageApprovalInput = z.infer<typeof transitionStageApprovalSchema>;
