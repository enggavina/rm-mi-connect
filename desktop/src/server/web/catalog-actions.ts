'use server';

import { actionUser, mutate, type WebActionResult } from './mutation';
import { createCatalogActions } from './catalog-mutations';

export async function saveCatalog(input: unknown): Promise<WebActionResult> {
  return createCatalogActions({ actionUser, mutate }).saveCatalog(input);
}
export async function deleteCatalog(input: unknown): Promise<WebActionResult> {
  return createCatalogActions({ actionUser, mutate }).deleteCatalog(input);
}
