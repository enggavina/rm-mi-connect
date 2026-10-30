import { z } from 'zod';

export const projectEquipmentTextFields = ['embarcacao', 'fabricante', 'modelo', 'numero_serie', 'descricao', 'certificado', 'norma',
  'potencia', 'rotacao', 'tensao_estator', 'tipo_tensao', 'corrente_estator', 'corrente_partida', 'frequencia', 'classe_isolamento',
  'grau_ip', 'forma', 'regime', 'peso', 'ligacao', 'componentes'] as const;
export const projectEquipmentEditableFields = [...projectEquipmentTextFields, 'placa_motor', 'fp', 'fs', 'numero_cabos'] as const;
export type ProjectEquipmentField = typeof projectEquipmentEditableFields[number];
const uuid = z.string().uuid().transform(value => value.toLowerCase());
const timestamp = z.string().datetime({ offset: true }), hash = z.string().regex(/^[0-9a-f]{64}$/);
const text = z.string().nullable();
const textFields = Object.fromEntries(projectEquipmentTextFields.map(key => [key, text])) as Record<typeof projectEquipmentTextFields[number], typeof text>;
const changedText = z.string().max(10_000).refine(value => !value.includes('\u0000')).nullable().optional();
const changedTextFields = Object.fromEntries(projectEquipmentTextFields.map(key => [key, changedText])) as Record<typeof projectEquipmentTextFields[number], typeof changedText>;
const decimal = z.string().regex(/^[+-]?\d{1,30}(?:\.\d{1,20})?$/).nullable().optional();
export const projectEquipmentChangesSchema = z.object({ ...changedTextFields,
  placa_motor: z.enum(['c___placa', 's___placa']).nullable().optional(), fp: decimal, fs: decimal,
  numero_cabos: z.number().int().min(0).max(2147483647).nullable().optional(),
}).strict().refine(value => Object.keys(value).length > 0 && Object.values(value).every(item => item !== undefined), 'Informe uma alteração válida nos dados técnicos.');
export type ProjectEquipmentChanges = z.infer<typeof projectEquipmentChangesSchema>;
export const saveProjectEquipmentSchema = z.object({ submissionId: uuid, projeto_id: uuid, equipamento_id: uuid,
  expected_project_updated_at: timestamp, expected_equipment_updated_at: timestamp, expected_context_version: hash,
  confirm_change: z.literal(true), changes: projectEquipmentChangesSchema,
}).strict();
export type SaveProjectEquipmentInput = z.infer<typeof saveProjectEquipmentSchema>;
export const projectEquipmentSnapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, status_pcp: text, data_real_de_entrega: timestamp.nullable(), equipamento_id: uuid.nullable(),
    tipo_equipamento_id: uuid.nullable(), updated_at: timestamp, closed: z.boolean() }).strict(),
  equipment: z.object({ id: uuid, projeto_id: uuid, tipo_equipamento_id: uuid.nullable(), updated_at: timestamp,
    ...textFields, placa_motor: z.enum(['c___placa', 's___placa']).nullable(), fp: text, fs: text, numero_cabos: z.number().int().nullable() }).strict().nullable(),
  binding_state: z.enum(['linked', 'missing', 'unlinked', 'conflicting', 'orphaned', 'shared']),
  can_edit: z.boolean(), reason: text, context_version: hash, type_mismatch: z.boolean(),
}).strict();
export type ProjectEquipmentSnapshot = z.infer<typeof projectEquipmentSnapshotSchema>;
export const projectEquipmentResultSchema = z.object({ projeto_id: uuid, equipamento_id: uuid, project_updated_at: timestamp,
  changed_fields: z.array(z.enum(projectEquipmentEditableFields)).max(projectEquipmentEditableFields.length), context_version: hash });
