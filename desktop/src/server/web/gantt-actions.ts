'use server';

import { actionUser, mutate } from './mutation';
import { createGanttActions } from './gantt-mutations';

const actions = createGanttActions({ actionUser, mutate });
export async function saveGanttPlan(input: unknown) { return actions.saveGanttPlan(input); }
