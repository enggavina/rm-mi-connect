import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';

const timestamp = z.string().datetime({ offset: true });
const text = z.string().nullable();
const assignmentSchema = z.object({
  id: uuid, avaliador_user_id: uuid, avaliador_nome: text, updated_at: timestamp, eligible: z.boolean(),
});
const recordSchema = z.object({
  id: uuid, status: z.string(), preenchido: z.boolean(), avaliador_user_id: uuid.nullable(), avaliador_nome: text, updated_at: timestamp,
});
const formSchema = z.object({
  id: uuid, titulo: text, linked: z.boolean(), assignment: assignmentSchema.nullable(), records: z.array(recordSchema).max(2000),
  can_assign: z.boolean(), action_reason: text, context_version: z.string().regex(/^[0-9a-f]{64}$/),
});
const snapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, status_pcp: text, data_real_de_entrega: timestamp.nullable(), updated_at: timestamp, closed: z.boolean() }),
  allocation: z.object({ id: uuid, projeto_id: uuid, celula_id: uuid, celula_nome: text, status: text, updated_at: timestamp }),
  forms: z.array(formSchema).max(1000), eligible_users: z.array(z.object({ id: uuid, nome: z.string(), matricula: text })).max(1000),
  total: z.number().int().nonnegative(), complete: z.boolean(), records_total: z.number().int().nonnegative(), records_complete: z.boolean(),
  eligible_total: z.number().int().nonnegative(), eligible_complete: z.boolean(),
});

export type FormReviewerAssignmentSnapshot = z.infer<typeof snapshotSchema>;
export type FormReviewerAssignmentForm = FormReviewerAssignmentSnapshot['forms'][number];

const readCapabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.forms.read'];
const unavailable = () => new Error('Não foi possível consultar os avaliadores desta célula. Tente novamente.');

/** One atomic RLS snapshot. Candidate identities never come from the global user catalog. */
export function createFormReviewerAssignmentData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getFormReviewerAssignments(projectId: string, allocationId: string, includeEligible = false): Promise<FormReviewerAssignmentSnapshot | null> {
    if (capabilities !== undefined && (!readCapabilities.every(capability => capabilities.includes(capability))
      || includeEligible && !capabilities.includes('em.planning.manage'))) throw new Error('Acesso não autorizado aos avaliadores desta célula.');
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(allocationId).success) return null;
    let result;
    try {
      result = await client.rpc('rm_web_form_reviewer_assignments_snapshot_v1', {
        p_project_id: projectId, p_allocation_id: allocationId, p_include_eligible: includeEligible,
      });
    } catch { throw unavailable(); }
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = snapshotSchema.safeParse(result.data);
    if (!parsed.success) throw unavailable();
    const snapshot = parsed.data;
    const closed = snapshot.project.data_real_de_entrega !== null
      || ['cancelado', 'finalizando_para_faturar'].includes(snapshot.project.status_pcp ?? '');
    const ended = closed || ['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '');
    const records = snapshot.forms.flatMap(form => form.records);
    const assignments = snapshot.forms.flatMap(form => form.assignment ? [form.assignment] : []);
    if (snapshot.project.id !== projectId || snapshot.project.closed !== closed
      || snapshot.allocation.id !== allocationId || snapshot.allocation.projeto_id !== projectId
      || snapshot.complete !== (snapshot.total <= 1000) || snapshot.records_complete !== (snapshot.records_total <= 2000)
      || snapshot.eligible_complete !== (snapshot.eligible_total <= 1000)
      || (snapshot.complete && snapshot.records_complete ? snapshot.forms.length !== snapshot.total || records.length !== snapshot.records_total : snapshot.forms.length !== 0)
      || new Set(snapshot.forms.map(form => form.id)).size !== snapshot.forms.length
      || new Set(records.map(record => record.id)).size !== records.length
      || new Set(assignments.map(assignment => assignment.id)).size !== assignments.length
      || new Set(snapshot.eligible_users.map(user => user.id)).size !== snapshot.eligible_users.length
      || (!snapshot.eligible_complete && snapshot.eligible_users.length !== 0)
      || (includeEligible && snapshot.eligible_complete && snapshot.eligible_users.length !== snapshot.eligible_total)
      || snapshot.forms.some(form => form.can_assign && (ended || !form.linked || !snapshot.complete || !snapshot.records_complete
        || !snapshot.eligible_complete || form.records.some(record => record.status === 'aprovado'))
        || includeEligible && snapshot.eligible_complete && form.assignment !== null
          && form.assignment.eligible !== snapshot.eligible_users.some(user => user.id === form.assignment?.avaliador_user_id))) throw unavailable();
    // Redact choices for viewers even if a stale RPC unexpectedly supplied them.
    return { ...snapshot, eligible_users: includeEligible ? snapshot.eligible_users : [] };
  }
  return { getFormReviewerAssignments };
}

export async function getFormReviewerAssignments(projectId: string, allocationId: string) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(readCapabilities);
  const includeEligible = ['administrador', 'padr_o'].includes(access.profile.perfil)
    && (!access.sso || access.sso.capabilities.includes('em.planning.manage'));
  return createFormReviewerAssignmentData(access.client, access.sso?.capabilities).getFormReviewerAssignments(projectId, allocationId, includeEligible);
}
