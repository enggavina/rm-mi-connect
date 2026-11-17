'use server';
import { actionUser, mutate } from './mutation';
import { createCapacityActions } from './capacity-mutations';
const actions = createCapacityActions({ actionUser, mutate });
export async function saveCapacityResource(input: unknown) { return actions.saveCapacityResource(input); }
export async function saveCapacityBookings(input: unknown) { return actions.saveCapacityBookings(input); }
