'use server';

import { revalidatePath } from 'next/cache';
import type { SupabaseClient } from '@supabase/supabase-js';
import { requireWebUser } from './auth';
import { mutationError, planCellSchema, reviewFormSchema, saveProjectSchema } from './policy';

export type WebActionResult =
  | { ok: true; data: { operation: string; id: string; projeto_id: string; updated_at: string; record: Record<string, unknown>; idempotent_replay: boolean } }
  | { ok: false; error: string; code: string; fieldErrors?: Record<string, string[] | undefined> };

async function mutate(client: SupabaseClient, operation: string, value: { submissionId: string; [key: string]: unknown }): Promise<WebActionResult> {
  const { submissionId, ...payload } = value;
  let response;
  try {
    response = await client.rpc('rm_web_mutate_v1', {
      p_client_submission_id: submissionId, p_operation: operation, p_payload: payload,
    });
  } catch { return { ok: false, ...mutationError() }; }
  if (response.error) return { ok: false, ...mutationError(response.error.code) };
  const result = response.data;
  if (!result || typeof result.id !== 'string' || typeof result.operation !== 'string') return { ok: false, ...mutationError() };
  revalidatePath('/painel'); revalidatePath('/projetos'); revalidatePath('/planejamento'); revalidatePath('/formularios');
  if (result.projeto_id) revalidatePath(`/projetos/${result.projeto_id}`);
  if (operation === 'review_form') revalidatePath(`/formularios/${result.id}`);
  return { ok: true, data: result };
}

export async function saveProject(input: unknown): Promise<WebActionResult> {
  const { client } = await requireWebUser();
  const parsed = saveProjectSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos informados.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(client, 'save_project', parsed.data);
}

export async function planCell(input: unknown): Promise<WebActionResult> {
  const { client } = await requireWebUser();
  const parsed = planCellSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos do planejamento.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(client, 'plan_cell', parsed.data);
}

export async function reviewForm(input: unknown): Promise<WebActionResult> {
  const { client } = await requireWebUser();
  const parsed = reviewFormSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira a decisão e as respostas selecionadas.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(client, 'review_form', parsed.data);
}
