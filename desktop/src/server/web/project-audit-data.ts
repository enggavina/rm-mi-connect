import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';

export const projectAuditKinds = ['cells', 'operations'] as const;
export type ProjectAuditKind = typeof projectAuditKinds[number];
const topics = ['cells', 'photos', 'forms', 'approvals'] as const;
const scalar = z.union([z.string().max(10000), z.number(), z.boolean(), z.null()]);
const fields = ['data_inicio', 'data_limite', 'bloqueada', 'motivo_bloqueio', 'motivo_atraso', 'observacao',
  'visibilidade', 'prioridade', 'indice', 'posicao', 'horas_previstas', 'horas_realizadas', 'responsavel_id',
  'status', 'forms_ids', 'retirada', 'selecao_relatorio', 'titulo', 'categoria_foto', 'tag', 'lixeira',
  'captured', 'form_id', 'avaliador_user_id', 'celula_destino_id', 'status_cel_proj', 'bloquear_avanco_sem_aprov',
  'aprovadores_ids', 'aprovadores_retorno_ids', 'ativo', 'tipo_equipamento_id', 'route_cell_count', 'captured_photo_count'] as const;
const changeSchema = z.object({ field: z.enum(fields), before: z.union([scalar, z.array(scalar).max(2000)]),
  after: z.union([scalar, z.array(scalar).max(2000)]) });
const itemSchema = z.object({ id: z.string().regex(/^audit:[0-9a-f]{64}$/), projeto_id: uuid, topic: z.enum(topics),
  action: z.string().min(1).max(100), entity_id: uuid, celula_id: uuid.nullable(), celula_projeto_id: uuid.nullable(),
  cell_name: z.string().max(500).nullable(), actor_id: uuid.nullable(), actor_name: z.string().max(500).nullable(),
  occurred_at: z.string().datetime({ offset: true }), source: z.enum(['web', 'mobile', 'legacy']), prior_evidence: z.boolean(),
  changes: z.array(changeSchema).min(1).max(32), reason: z.string().max(10000).nullable() });
export const projectAuditPageSchema = z.object({ project_id: uuid, kind: z.enum(projectAuditKinds),
  page: z.number().int().positive(), page_size: z.literal(25), total: z.number().int().nonnegative(),
  items: z.array(itemSchema).max(25) });
export type ProjectAuditPage = z.infer<typeof projectAuditPageSchema>;
export type ProjectAuditEvent = ProjectAuditPage['items'][number];
const base: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.history.read'];
const unavailable = () => new Error('Não foi possível consultar a auditoria do projeto. Recarregue a página.');

export function createProjectAuditData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectAudit(projectId: string, kind: ProjectAuditKind, page: unknown = 1): Promise<ProjectAuditPage | null> {
    const allowed = (capability: CorporateCapability) => capabilities === undefined || capabilities.includes(capability);
    if (!base.every(allowed) || kind === 'cells' && !allowed('em.planning.read')) throw new Error('Acesso não autorizado ao histórico do projeto.');
    if (!uuid.safeParse(projectId).success) return null;
    if (!projectAuditKinds.includes(kind)) throw unavailable();
    const requestedPage = typeof page === 'string' && /^[1-9]\d{0,5}$/.test(page) ? Number(page) : page;
    if (typeof requestedPage !== 'number' || !Number.isSafeInteger(requestedPage) || requestedPage < 1 || requestedPage > 1000000) throw unavailable();
    const allowedTopics = (['photos', 'forms', 'approvals'] as const).filter(topic => allowed(`em.${topic}.read`));
    let result;
    try { result = await client.rpc('rm_web_project_audit_v1', { p_project_id: projectId.toLowerCase(), p_kind: kind, p_page: requestedPage, p_topics: allowedTopics }); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = projectAuditPageSchema.safeParse(result.data);
    if (!parsed.success) throw unavailable();
    const data = parsed.data;
    if (data.project_id !== projectId.toLowerCase() || data.kind !== kind
      || data.page !== Math.min(requestedPage, Math.max(1, Math.ceil(data.total / 25)))
      || data.items.length !== Math.min(25, Math.max(0, data.total - (data.page - 1) * 25))
      || new Set(data.items.map(item => item.id)).size !== data.items.length
      || data.items.some((item, index) => item.projeto_id !== data.project_id
        || (kind === 'cells' ? item.topic !== 'cells' : item.topic === 'cells' || !allowedTopics.includes(item.topic))
        || new Set(item.changes.map(change => change.field)).size !== item.changes.length
        || index > 0 && (item.occurred_at > data.items[index - 1].occurred_at
          || item.occurred_at === data.items[index - 1].occurred_at && item.id < data.items[index - 1].id))) throw unavailable();
    return data;
  }
  return { getProjectAudit };
}

export async function getProjectAudit(projectId: string, kind: ProjectAuditKind, page: unknown = 1) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(kind === 'cells' ? [...base, 'em.planning.read'] : base);
  return createProjectAuditData(access.client, access.sso?.capabilities).getProjectAudit(projectId, kind, page);
}
