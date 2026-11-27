import { z } from 'zod'
import { isValidDateValue } from './metrics'
const nullableText = z.string().nullable()
const date = z.string().refine(isValidDateValue, 'Data inválida')
export const orderSchema = z.object({
  id: z.string().min(1), code: z.string(), equipment: z.string(), client: nullableText, stage: nullableText, status: nullableText, responsible: nullableText,
  enteredAt: date.nullable(), dueAt: date.nullable(), completedAt: date.nullable(), blockReason: nullableText, blockDeclared: z.boolean().nullable(), priority: nullableText,
  powerKw: z.number().nonnegative().nullable(), rpm: z.number().nonnegative().nullable(), serial: nullableText, locationId: nullableText, locationVerified: z.boolean(),
  model: z.enum(['motor', 'generator', 'transformer', 'drive', 'rotor', 'stator', 'housing', 'shaft']), equipmentType: nullableText.optional(), modelVerified: z.boolean().optional(), sourceUrl: z.string().refine(s => /^\/projetos\/[0-9a-f-]{36}$/i.test(s), 'Link deve apontar para um projeto EM').nullable(),
  history: z.array(z.object({ at: date, label: z.string() })),
  activities: z.array(z.object({ id: z.string().min(1), cellId: nullableText.optional(), name: nullableText, status: nullableText, blocked: z.boolean().nullable(), blockReason: nullableText, startedAt: date.nullable(), dueAt: date.nullable(), completedAt: date.nullable(), responsible: nullableText })).optional(),
  activeStageNames: z.array(z.string()).optional(), dueSource: nullableText.optional(), powerRaw: nullableText.optional(), rpmRaw: nullableText.optional(),
})
export const snapshotSchema = z.object({
  schemaVersion: z.literal(1), source: z.literal('supabase'), fetchedAt: date, referenceAt: date,
  layout: z.enum(['bma', 'management']).optional(),
  cells: z.array(z.object({ id: z.string().min(1), name: z.string().min(1), order: z.number().finite().nullable() })).optional(),
  orders: z.array(orderSchema), resources: z.array(z.object({ id: z.string(), name: z.string(), sector: z.string(), position: z.tuple([z.number(), z.number(), z.number()]), rotation: z.number(), kind: z.enum(['bench', 'support', 'test']), capacity: z.number().int().positive().nullable(), illustrative: z.boolean() })), warnings: z.array(z.string()),
}).superRefine((value, ctx) => {
  if (new Set(value.orders.map(o => o.id)).size !== value.orders.length) ctx.addIssue({ code: 'custom', message: 'IDs de projetos duplicados' })
  if (new Set(value.resources.map(r => r.id)).size !== value.resources.length) ctx.addIssue({ code: 'custom', message: 'IDs de recursos duplicados' })
  if (value.cells && new Set(value.cells.map(c => c.id)).size !== value.cells.length) ctx.addIssue({ code: 'custom', message: 'IDs de células duplicados' })
  if (value.source === 'supabase') value.orders.forEach((order, i) => {
    if (order.activities === undefined) ctx.addIssue({ code: 'custom', path: ['orders', i, 'activities'], message: 'A fonte Supabase deve declarar as atividades, mesmo quando vazias' })
  })
})
