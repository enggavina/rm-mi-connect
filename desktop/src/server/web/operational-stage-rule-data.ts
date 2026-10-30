import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';
import { STAGE_RULE_STATUSES } from './operational-stage-rule-policy';

const timestamp = z.string().datetime({ offset: true }), text = z.string().nullable();
const personSchema = z.object({ id: uuid, nome: text, matricula: text, eligible: z.boolean() });
const ruleSchema = z.object({
  id: uuid, projeto_id: uuid, celula_projeto_id: uuid.nullable(), celula_origem_id: uuid, celula_destino_id: uuid.nullable(), celula_destino_nome: text,
  status: text, status_cel_proj: text, bloquear_avanco_sem_aprov: z.boolean(), ativo: z.boolean(),
  aprovador_id: uuid.nullable(), aprovadores_ids: z.array(uuid), aprovadores_retorno_ids: z.array(uuid), aprovado_por_id: uuid.nullable(),
  data_aprovacao: timestamp.nullable(), created_at: timestamp, updated_at: timestamp,
  approvers: z.array(personSchema), return_approvers: z.array(personSchema), used: z.boolean(), history_ambiguous: z.boolean(),
  related_return_ids: z.array(uuid), pair_ambiguous: z.boolean(), managed_birth: z.boolean(), family_ids: z.array(uuid), supersedes_id: uuid.nullable(),
  can_edit: z.boolean(), can_retire: z.boolean(), can_restore: z.boolean(), action_reason: text,
});
const snapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, status_pcp: text, data_real_de_entrega: timestamp.nullable(), updated_at: timestamp, closed: z.boolean() }),
  allocation: z.object({ id: uuid, projeto_id: uuid, celula_id: uuid, celula_nome: text, status: text, updated_at: timestamp }),
  rules: z.array(ruleSchema).max(1000), rules_version: z.string().regex(/^[0-9a-f]{64}$/),
  statuses: z.array(z.object({ key: z.enum(STAGE_RULE_STATUSES), label: z.string() })),
  destinations: z.array(z.object({ allocation_id: uuid, celula_id: uuid, nome: text, status: text, updated_at: timestamp, can_select: z.boolean(), reason: text })).max(1000),
  eligible_users: z.array(z.object({ id: uuid, nome: z.string(), matricula: text, celula_ids: z.array(uuid) })).max(1000),
  total: z.number().int().nonnegative(), selected_total: z.number().int().nonnegative(), complete: z.boolean(),
  allocations_total: z.number().int().nonnegative(), allocations_complete: z.boolean(), eligible_total: z.number().int().nonnegative(), eligible_complete: z.boolean(),
  memberships_total: z.number().int().nonnegative(), memberships_complete: z.boolean(),
});
export type OperationalStageRuleSnapshot = z.infer<typeof snapshotSchema>;
export type OperationalStageRule = OperationalStageRuleSnapshot['rules'][number];
export type OperationalStageRulePerson = z.infer<typeof personSchema>;

const readCapabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.approvals.read'];
const unique = (ids: readonly string[]) => new Set(ids).size === ids.length;
const unavailable = () => new Error('Não foi possível consultar as regras de etapas desta célula. Tente novamente.');

/** The snapshot contains all configuration revisions and only project-scoped choices. */
export function createOperationalStageRuleData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getOperationalStageRules(projectId: string, allocationId: string, includeChoices = false): Promise<OperationalStageRuleSnapshot | null> {
    if (capabilities !== undefined && (!readCapabilities.every(capability => capabilities.includes(capability))
      || includeChoices && !capabilities.includes('em.planning.manage'))) throw new Error('Acesso não autorizado às regras de etapas desta célula.');
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(allocationId).success) return null;
    let result;
    try { result = await client.rpc('rm_web_stage_rules_snapshot_v1', { p_project_id: projectId, p_allocation_id: allocationId, p_include_choices: includeChoices }); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = snapshotSchema.safeParse(result.data); if (!parsed.success) throw unavailable();
    const snapshot = parsed.data;
    const closed = snapshot.project.data_real_de_entrega !== null || ['cancelado', 'finalizando_para_faturar'].includes(snapshot.project.status_pcp ?? '');
    const allComplete = snapshot.complete && snapshot.allocations_complete && snapshot.eligible_complete && snapshot.memberships_complete;
    if (snapshot.project.id !== projectId || snapshot.project.closed !== closed || snapshot.allocation.id !== allocationId || snapshot.allocation.projeto_id !== projectId
      || snapshot.complete !== (snapshot.total <= 1000) || snapshot.allocations_complete !== (snapshot.allocations_total <= 1000)
      || snapshot.eligible_complete !== (snapshot.eligible_total <= 1000) || snapshot.memberships_complete !== (snapshot.memberships_total <= 5000)
      || snapshot.selected_total > snapshot.total || !unique(snapshot.rules.map(rule => rule.id))
      || (snapshot.complete && snapshot.allocations_complete ? snapshot.rules.length !== snapshot.selected_total : snapshot.rules.length !== 0)
      || !unique(snapshot.statuses.map(status => status.key))
      || !unique(snapshot.destinations.map(destination => destination.allocation_id)) || !unique(snapshot.destinations.map(destination => destination.celula_id))
      || !unique(snapshot.eligible_users.map(user => user.id))
      || (!allComplete && (snapshot.statuses.length > 0 || snapshot.destinations.length > 0 || snapshot.eligible_users.length > 0))
      || (includeChoices && allComplete && snapshot.eligible_users.length !== snapshot.eligible_total)
      || snapshot.destinations.some(destination => destination.can_select && (destination.celula_id === snapshot.allocation.celula_id || ['finalizado', 'n_a'].includes(destination.status ?? '')))
      || snapshot.eligible_users.some(user => !unique(user.celula_ids))
      || snapshot.rules.some(rule => rule.projeto_id !== projectId || rule.celula_origem_id !== snapshot.allocation.celula_id
        || rule.celula_projeto_id !== null && rule.celula_projeto_id !== allocationId
        || !unique(rule.family_ids) || !unique(rule.related_return_ids) || !unique(rule.approvers.map(user => user.id)) || !unique(rule.return_approvers.map(user => user.id))
        || rule.supersedes_id === rule.id
        || (closed || snapshot.allocation.status === 'n_a' || !allComplete || rule.used || rule.history_ambiguous
          || !rule.managed_birth && (rule.pair_ambiguous || rule.related_return_ids.length > 0)
          || rule.status_cel_proj === 'retornado' || !['nulo', null].includes(rule.status)) && (rule.can_edit || rule.can_retire || rule.can_restore)
        || rule.ativo && rule.can_restore || !rule.ativo && (rule.can_edit || rule.can_retire)
        || snapshot.total >= 1000 && rule.can_edit
        || rule.can_restore && (!STAGE_RULE_STATUSES.some(status => status === rule.status_cel_proj)
          || includeChoices && allComplete && !snapshot.destinations.some(destination => destination.celula_id === rule.celula_destino_id && destination.can_select))
        || rule.can_restore && snapshot.rules.some(other => other.ativo && rule.family_ids.includes(other.id)))) throw unavailable();
    // Viewers see operational configuration, never a second global user catalog.
    return includeChoices ? snapshot : { ...snapshot, statuses: [], destinations: [], eligible_users: [] };
  }
  return { getOperationalStageRules };
}

export async function getOperationalStageRules(projectId: string, allocationId: string) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(readCapabilities);
  const includeChoices = ['administrador', 'padr_o'].includes(access.profile.perfil)
    && (!access.sso || access.sso.capabilities.includes('em.planning.manage'));
  return createOperationalStageRuleData(access.client, access.sso?.capabilities).getOperationalStageRules(projectId, allocationId, includeChoices);
}
