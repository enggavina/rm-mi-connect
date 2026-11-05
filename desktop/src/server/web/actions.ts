'use server';

import { planCellSchema, reviewFormSchema, saveProjectSchema, saveProjectWithEquipmentSchema } from './policy';
import { mutate, actionUser, type WebActionResult } from './mutation';
import { hasWebCapability } from './auth-policy';
export type { WebActionResult } from './mutation';

export async function saveProject(input: unknown): Promise<WebActionResult> {
  const access = await actionUser('em.projects.manage');
  if ('ok' in access) return access;
  const parsed = saveProjectSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os campos informados.', fieldErrors: parsed.error.flatten().fieldErrors };
  return mutate(access.client, 'save_project', parsed.data, 'em.projects.manage', access.sso);
}

export async function saveProjectWithEquipment(input: unknown): Promise<WebActionResult> {
  const access = await actionUser('em.projects.manage');
  if ('ok' in access) return access;
  if (!['administrador', 'padr_o'].includes(access.profile.perfil) || !(['em.portal.read', 'em.projects.read'] as const).every(capability => hasWebCapability(access, capability)))
    return { ok: false, code: '42501', error: 'Seu acesso permite apenas consultar o projeto.' };
  const parsed = saveProjectWithEquipmentSchema.safeParse(input);
  if (!parsed.success) return { ok: false, code: 'INVALID_INPUT', error: 'Confira os dados do projeto e do equipamento.', fieldErrors: parsed.error.flatten().fieldErrors };
  const result = await mutate(access.client, 'save_project_with_equipment', parsed.data, 'em.projects.manage', access.sso);
  if (!result.ok) return result;
  const value = result.data;
  if (value.operation !== 'save_project_with_equipment' || value.id !== parsed.data.id || value.projeto_id !== parsed.data.id
    || value.record?.id !== parsed.data.id || value.record?.equipamento_id !== parsed.data.equipment.id
    || typeof value.idempotent_replay !== 'boolean' || typeof value.updated_at !== 'string' || Number.isNaN(Date.parse(value.updated_at)))
    return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar o projeto e o equipamento. Tente novamente com o mesmo protocolo.' };
  return { ok: true, data: { operation: value.operation, id: value.id, projeto_id: value.projeto_id, updated_at: value.updated_at,
    idempotent_replay: value.idempotent_replay, record: { id: value.id, equipamento_id: parsed.data.equipment.id } } };
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
