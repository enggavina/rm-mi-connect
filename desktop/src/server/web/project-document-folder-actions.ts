'use server';
import { actionUser, mutate } from './mutation';
import { createProjectDocumentFolderActions } from './project-document-folder-mutations';
export async function manageProjectDocuments(input: unknown) {
  return createProjectDocumentFolderActions({ actionUser, mutate }).manageProjectDocuments(input);
}
