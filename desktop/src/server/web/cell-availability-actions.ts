'use server';

import { actionUser, mutate } from './mutation';
import { createCellAvailabilityActions } from './cell-availability-mutations';

export async function manageCellAvailability(input: unknown) {
  return createCellAvailabilityActions({ actionUser, mutate }).manageCellAvailability(input);
}
