import { z } from 'zod';
import { uuid } from './policy';

export const STAGE_RULE_STATUSES = ['pendente', 'liberado_para_ensaios_parciais', 'liberado_para_impregna__o',
  'liberado_para_montagem', 'para_execu__o', 'em_dia', 'finalizado', 'atrasado', 'n_a'] as const;
const timestamp = z.string().datetime({ offset: true });
const ids = z.array(uuid).min(1).max(100).refine(values => new Set(values).size === values.length, 'Selecione cada identidade uma única vez.');
export const stageRuleConfigSchema = z.object({
  celula_destino_id: uuid,
  status_cel_proj: z.enum(STAGE_RULE_STATUSES),
  bloquear_avanco_sem_aprov: z.boolean(),
  aprovadores_ids: ids,
  aprovadores_retorno_ids: ids,
}).strict();
const common = {
  submissionId: uuid, projeto_id: uuid, celula_projeto_id: uuid,
  expected_project_updated_at: timestamp, expected_allocation_updated_at: timestamp,
  expected_rules_version: z.string().regex(/^[0-9a-f]{64}$/),
};
const target = { etapa_id: uuid, expected_etapa_updated_at: timestamp, confirm_change: z.literal(true) };
export const manageStageRulesSchema = z.discriminatedUnion('action', [
  z.object({ ...common, action: z.literal('create'), id: uuid, config: stageRuleConfigSchema }).strict(),
  z.object({ ...common, ...target, action: z.literal('replace'), replacement_id: uuid, config: stageRuleConfigSchema }).strict(),
  z.object({ ...common, ...target, action: z.literal('retire') }).strict(),
  z.object({ ...common, ...target, action: z.literal('restore') }).strict(),
]).superRefine((value, context) => {
  if (value.action === 'replace' && value.replacement_id === value.etapa_id) context.addIssue({
    code: 'custom', path: ['replacement_id'], message: 'A nova configuração precisa de um identificador próprio.',
  });
});
export type ManageStageRulesInput = z.infer<typeof manageStageRulesSchema>;

export const operationalStageRuleResultSchema = z.object({
  projeto_id: uuid, celula_projeto_id: uuid,
  action: z.enum(['create', 'replace', 'retire', 'restore']),
  etapa_id: uuid, previous_etapa_id: uuid.nullable(),
  rules_version: z.string().regex(/^[0-9a-f]{64}$/), changed_ids: z.array(uuid).max(2),
});
