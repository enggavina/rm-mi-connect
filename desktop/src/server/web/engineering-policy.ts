import { z } from 'zod';
import { mutationError, uuid } from './policy';

const version = z.string().datetime({ offset: true }).nullable();
const base = { submissionId: uuid, id: uuid, expected_updated_at: version };
const nonempty = (value: Record<string, unknown>) => Object.values(value).some(item => item !== undefined);
const unique = (values: string[]) => new Set(values).size === values.length;
const idList = z.array(uuid).max(200).refine(unique, 'Vínculos repetidos.');
// Legacy values must reach SQL unchanged: it permits exact grandfathered rows,
// while validating new/changed titles, numbering and approver memberships.
const legacyInteger = z.number().int().min(-2147483648).max(2147483647).nullable();
export const engineeringPhotoSchema = z.object({
  id: uuid, cadastro_foto_id: uuid.nullable(), numero: legacyInteger,
  descricao: z.string().nullable(),
}).strict();
export const engineeringStageSchema = z.object({
  id: uuid, celula_destino_id: uuid.nullable(),
  status_cel_proj: z.string().min(1).max(100).regex(/^[a-z0-9_]+$/).nullable(),
  bloquear_avanco_sem_aprov: z.boolean(),
  aprovadores_ids: z.array(uuid).max(500), aprovadores_retorno_ids: z.array(uuid).max(500),
}).strict();
const childIdsUnique = (rows: { id: string }[]) => unique(rows.map(row => row.id));
export const saveEngineeringSchema = z.object({
  ...base, celula_id: uuid, tipo_equipamento_id: uuid,
  changes: z.object({
    ativo: z.boolean().optional(), visibilidade: z.boolean().optional(),
    numero_fotos: z.number().int().min(0).max(1000).optional(), form_ids: idList.optional(),
    photos: z.array(engineeringPhotoSchema).max(1000).refine(childIdsUnique, 'Fotos repetidas.').optional(),
    stages: z.array(engineeringStageSchema).max(100).refine(childIdsUnique, 'Etapas repetidas.').optional(),
  }).strict().refine(nonempty, 'Informe uma alteração.'),
}).strict();
export const savePhotoTitleSchema = z.object({
  ...base,
  changes: z.object({
    titulo: z.string().trim().min(1).max(200).optional(),
    numero: z.number().int().min(0).max(1000).nullable().optional(), celula_id: uuid.nullable().optional(),
  }).strict().refine(nonempty, 'Informe uma alteração.'),
}).strict().superRefine((value, context) => {
  if (value.expected_updated_at === null) {
    if (!value.changes.titulo) context.addIssue({ code: 'custom', path: ['changes', 'titulo'], message: 'Informe o título.' });
    if (!Object.hasOwn(value.changes, 'celula_id') || value.changes.celula_id === undefined) context.addIssue({ code: 'custom', path: ['changes', 'celula_id'], message: 'Escolha uma célula ou o escopo global.' });
  }
});
export type SaveEngineeringInput = z.input<typeof saveEngineeringSchema>;
export type SavePhotoTitleInput = z.input<typeof savePhotoTitleSchema>;
export type EngineeringPhotoInput = z.input<typeof engineeringPhotoSchema>;
export type EngineeringStageInput = z.input<typeof engineeringStageSchema>;
export function engineeringMutationError(code?: string) {
  if (code === '23505') return { code, error: 'Já existe um vínculo ou título equivalente, ou este protocolo foi usado com outros dados. Atualize a tela.' };
  if (code === '23503') return { code, error: 'Um vínculo da configuração não está disponível ou não pode ser alterado. Confira as células, modelos e responsáveis.' };
  return mutationError(code);
}
