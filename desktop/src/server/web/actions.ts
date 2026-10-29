'use server';

import { revalidatePath } from 'next/cache';
import type { SupabaseClient } from '@supabase/supabase-js';
import { mutationError, planCellSchema, reviewFormSchema, saveProjectSchema } from './policy';
import { getWebUser } from './auth';
import { authorizeSsoAction } from './sso-bridge';
import { CorporateAuthError, type CorporateCapability } from './sso-policy';
import type { SsoContext } from './auth-policy';

export type WebActionResult =
  | { ok: true; data: { operation: string; id: string; projeto_id: string; updated_at: string; record: Record<string, unknown>; idempotent_replay: boolean } }
  | { ok: false; error: string; code: string; fieldErrors?: Record<string, string[] | undefined> };

async function mutate(client: SupabaseClient, operation: string, value: { submissionId: string; [key: string]: unknown }, capability: CorporateCapability, sso?: SsoContext): Promise<WebActionResult> {
  const { submissionId, ...payload } = value;
  let response;
  try {
    if (sso) await authorizeSsoAction(sso, submissionId, operation, payload, capability);
    response = await client.rpc('rm_web_mutate_v1', {
      p_client_submission_id: submissionId, p_operation: operation, p_payload: payload,
    });
  } catch (error) {
    return { ok: false, ...(error instanceof CorporateAuthError ? { code: error.code, error: error.message } : mutationError()) };
  }
  if (response.error) return { ok: false, ...mutationError(response.error.code) };
  const result = response.data;
  if (!result || typeof result.id !== 'string' || typeof result.operation !== 'string') return { ok: false, ...mutationError() };
  revalidatePath('/painel'); revalidatePath('/projetos'); revalidatePath('/planejamento'); revalidatePath('/formularios');
  if (result.projeto_id) revalidatePath(`/projetos/${result.projeto_id}`);
  if (operation === 'review_form') revalidatePath(`/formularios/${result.id}`);
  return { ok: true, data: result };
}

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

async function actionUser(capability: CorporateCapability) {
  try {
    const access = await getWebUser(capability);
    if (access) return access;
    return { ok: false as const, code: 'CORP_UNAUTHORIZED', error: 'Sua sessão expirou. Entre novamente.' };
  } catch (error) {
    return { ok: false as const, ...(error instanceof CorporateAuthError ? { code: error.code, error: error.message } : mutationError()) };
  }
}
