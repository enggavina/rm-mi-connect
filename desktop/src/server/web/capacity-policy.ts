import { z } from 'zod';
import { uuid } from './policy';
import { calendarDay } from './gantt';
import { ganttRevision } from './gantt-policy';
import type { CorporateCapability } from './sso-policy';

export const CAPACITY_MAX_RESOURCES = 200;
export const CAPACITY_MAX_BOOKINGS = 10000;
export const CAPACITY_READ_SCOPES: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.projects.read'];
export const capacityDaySchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => calendarDay(value) !== null && value >= '1900-01-01' && value <= '2200-12-31');
const minutes = z.number().int().min(0).max(1440);
const name = z.string().trim().min(1).max(120).refine(value => !/[\x00-\x1f\x7f]/.test(value));
export const capacityKindSchema = z.enum(['pessoa', 'maquina']);
export const capacityWeekSchema = z.array(minutes).length(7);
export const capacityExceptionsSchema = z.array(z.object({ date: capacityDaySchema, minutes, label: name }).strict()).max(366).superRefine((value, context) => {
  if (new Set(value.map(item => item.date)).size !== value.length) context.addIssue({ code: 'custom', message: 'Cada data deve ter uma única exceção.' });
});
export const capacityFiltersSchema = z.object({ start: capacityDaySchema, days: z.union([z.literal(7), z.literal(14), z.literal(28)]), project_id: uuid.nullable() }).strict().superRefine((value, context) => {
  if ((calendarDay(value.start) ?? Infinity) + value.days - 1 > calendarDay('2200-12-31')!) context.addIssue({ code: 'custom', message: 'O período ultrapassa o limite do calendário.' });
});
export type CapacityFilters = z.infer<typeof capacityFiltersSchema>;
export const saveCapacityResourceSchema = z.object({
  submissionId: uuid, id: uuid.nullable(), expected_version: ganttRevision.nullable(),
  name, kind: capacityKindSchema, active: z.boolean(), weekly_minutes: capacityWeekSchema, exceptions: capacityExceptionsSchema,
  acknowledge_overload: z.boolean(), reason: z.string().trim().min(3).max(2000),
}).strict().superRefine((value, context) => {
  if (!!value.id !== !!value.expected_version) context.addIssue({ code: 'custom', message: 'Informe a versão do recurso existente.' });
});
export const saveCapacityBookingsSchema = z.object({
  submissionId: uuid, resource_id: uuid, expected_resource_version: ganttRevision, allocation_id: uuid,
  expected_allocation_updated_at: z.string().datetime({ offset: true }), expected_project_version: ganttRevision,
  days: z.array(z.object({ date: capacityDaySchema, minutes }).strict()).min(1).max(31),
  acknowledge_overload: z.boolean(), reason: z.string().trim().min(3).max(2000),
}).strict().superRefine((value, context) => {
  if (new Set(value.days.map(item => item.date)).size !== value.days.length) context.addIssue({ code: 'custom', message: 'Uma data não pode ser alterada duas vezes no mesmo envio.' });
});
export type SaveCapacityResourceInput = z.infer<typeof saveCapacityResourceSchema>;
export type SaveCapacityBookingsInput = z.infer<typeof saveCapacityBookingsSchema>;
