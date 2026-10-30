'use server';

import { actionUser, mutate } from './mutation';
import { createProjectCommentActions } from './project-comment-mutations';

export async function editProjectComment(input: unknown) {
  return createProjectCommentActions({ actionUser, mutate }).editProjectComment(input);
}
