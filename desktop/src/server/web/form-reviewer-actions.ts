'use server';

import { actionUser, mutate } from './mutation';
import { createFormReviewerActions } from './form-reviewer-mutations';

export async function assignFormReviewer(input: unknown) {
  return createFormReviewerActions({ actionUser, mutate }).assignFormReviewer(input);
}
