'use server';

import { actionUser, mutate } from './mutation';
import { createProjectPhotoActions } from './project-photo-mutations';

const actions = createProjectPhotoActions({ actionUser, mutate });
export async function setProjectPhotoSelection(input: unknown) { return actions.setProjectPhotoSelection(input); }
