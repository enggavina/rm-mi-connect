'use server';

import { planCellSchema, reviewFormSchema, saveProjectSchema } from './policy';
import { mutate, actionUser, type WebActionResult } from './mutation';
export type { WebActionResult } from './mutation';

export async function saveProject(input: unknown): Promise<WebActionResult> {
  const access = await actionUser('em.projects.manage');
  if ('ok' in access) return access;
  const parsed = saveProjectSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos informados.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(access.client, 'save_project', parsed.data, 'em.projects.manage', access.sso);
}

export async function planCell(input: unknown): Promise<WebActionResult> {
  const access = await actionUser('em.planning.manage');
  if ('ok' in access) return access;
  const parsed = planCellSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos do planejamento.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(access.client, 'plan_cell', parsed.data, 'em.planning.manage', access.sso);
}

export async function reviewForm(input: unknown): Promise<WebActionResult> {
  const access = await actionUser('em.forms.review');
  if ('ok' in access) return access;
  const parsed = reviewFormSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira a decisão e as respostas selecionadas.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(access.client, 'review_form', parsed.data, 'em.forms.review', access.sso);
}
