'use server';
import { actionUser, mutate } from './mutation';
import { createProjectEquipmentActions } from './project-equipment-mutations';

export async function saveProjectEquipment(input: unknown) {
  return createProjectEquipmentActions({ actionUser, mutate }).saveProjectEquipment(input);
}
