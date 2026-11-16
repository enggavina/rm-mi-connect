'use server';
import { actionUser, mutate } from './mutation';
import { createGanttSettingsActions } from './gantt-settings-mutations';
const actions = createGanttSettingsActions({ actionUser, mutate });
export async function saveGanttSettings(input: unknown) { return actions.saveGanttSettings(input); }
