'use server';

import { actionUser, mutate } from './mutation';
import { createProjectRouteActions } from './project-route-mutations';

const actions = createProjectRouteActions({ actionUser, mutate });
export async function saveProjectRoute(input: unknown) { return actions.saveProjectRoute(input); }
