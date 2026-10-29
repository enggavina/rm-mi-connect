import { revalidatePath } from 'next/cache';
import type { SupabaseClient } from '@supabase/supabase-js';
import { mutationError } from './policy';
import { getWebUser } from './auth';
import { authorizeSsoAction } from './sso-bridge';
import { CorporateAuthError, type CorporateCapability } from './sso-policy';
import type { SsoContext } from './auth-policy';

export type WebActionResult =
  | { ok: true; data: { operation: string; id: string; projeto_id: string | null; updated_at: string; record: Record<string, unknown>; idempotent_replay: boolean } }
  | { ok: false; error: string; code: string; fieldErrors?: Record<string, string[] | undefined> };

export async function mutate(client: SupabaseClient, operation: string, value: { submissionId: string; [key: string]: unknown }, capability: CorporateCapability, sso?: SsoContext): Promise<WebActionResult> {
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
  if (operation === 'save_catalog' || operation === 'delete_catalog') revalidatePath('/cadastros');
  if (operation === 'save_engineering' || operation === 'save_photo_title') {
    revalidatePath('/engenharia', 'layout');
  }
  revalidatePath('/painel'); revalidatePath('/projetos'); revalidatePath('/planejamento'); revalidatePath('/formularios');
  if (result.projeto_id) revalidatePath(`/projetos/${result.projeto_id}`);
  if (operation === 'review_form') revalidatePath(`/formularios/${result.id}`);
  return { ok: true, data: result };
}

export async function actionUser(capability: CorporateCapability) {
  try {
    const access = await getWebUser(capability);
    if (access) return access;
    return { ok: false as const, code: 'CORP_UNAUTHORIZED', error: 'Sua sessão expirou. Entre novamente.' };
  } catch (error) {
    return { ok: false as const, ...(error instanceof CorporateAuthError ? { code: error.code, error: error.message } : mutationError()) };
  }
}
