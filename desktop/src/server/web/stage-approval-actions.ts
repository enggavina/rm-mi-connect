'use server';
import { actionUser, mutate } from './mutation';
import { createStageApprovalActions } from './stage-approval-mutations';

const actions = createStageApprovalActions({ actionUser, mutate });
export async function transitionStageApproval(input: unknown) { return actions.transitionStageApproval(input); }
