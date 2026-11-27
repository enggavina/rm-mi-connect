'use server';
import { actionUser, mutate } from './mutation';
import { createStageApprovalActions } from './stage-approval-mutations';
import { workshopFormReviewWritesEnabled, workshopOperationReadsEnabled } from './workshop-operation-reader';

const actions = createStageApprovalActions({ actionUser, mutate });
export async function transitionStageApproval(input: unknown) {
  if (workshopOperationReadsEnabled() && !workshopFormReviewWritesEnabled()) {
    return { ok: false as const, code: '42501', error: 'A oficina está disponível para consulta. As decisões ainda aguardam a liberação da operação.' };
  }
  return actions.transitionStageApproval(input);
}
