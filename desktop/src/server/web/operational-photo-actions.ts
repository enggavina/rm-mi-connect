'use server';

import { actionUser, mutate } from './mutation';
import { createOperationalPhotoActions } from './operational-photo-mutations';

const actions = createOperationalPhotoActions({ actionUser, mutate });
export async function manageOperationalPhotos(input: unknown) { return actions.manageOperationalPhotos(input); }
