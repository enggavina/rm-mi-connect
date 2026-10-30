'use server';

import { actionUser, mutate } from './mutation';
import { createOperationalStageRuleActions } from './operational-stage-rule-mutations';

export async function manageStageRules(input: unknown) {
  return createOperationalStageRuleActions({ actionUser, mutate }).manageStageRules(input);
}
