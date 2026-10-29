'use server';
import { actionUser, mutate } from './mutation';
import { createEngineeringActions } from './engineering-mutations';

const actions = createEngineeringActions({ actionUser, mutate });
export async function saveEngineering(input: unknown) { return actions.saveEngineering(input); }
export async function savePhotoTitle(input: unknown) { return actions.savePhotoTitle(input); }
