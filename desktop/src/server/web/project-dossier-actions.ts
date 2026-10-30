'use server';
import { actionUser, mutate } from './mutation';
import { createProjectDossierActions } from './project-dossier-mutations';

export async function addProjectComment(input: unknown) {
  return createProjectDossierActions({ actionUser, mutate }).addProjectComment(input);
}
