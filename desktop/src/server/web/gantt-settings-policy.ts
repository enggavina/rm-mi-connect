import { z } from 'zod';
import { uuid } from './policy';
import { calendarDay } from './gantt';
import { ganttRevision } from './gantt-policy';

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => calendarDay(value) !== null
  && value >= '1900-01-01' && value <= '2200-12-31', 'Informe uma data válida entre 1900 e 2200.');
const label = z.string().trim().min(1).max(120).refine(value => !/[\x00-\x1f\x7f]/.test(value));
export const ganttCalendarSchema = z.object({
  weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7),
  exceptions: z.array(z.object({ date: day, working: z.boolean(), label }).strict()).max(366),
}).strict().superRefine((value, context) => {
  if (new Set(value.weekdays).size !== value.weekdays.length) context.addIssue({ code: 'custom', path: ['weekdays'], message: 'Dia da semana repetido.' });
  if (new Set(value.exceptions.map(item => item.date)).size !== value.exceptions.length) context.addIssue({ code: 'custom', path: ['exceptions'], message: 'Uma data não pode ter duas exceções.' });
});
export const ganttMilestoneSchema = z.object({ id: uuid, label, date: day }).strict();
export const ganttMilestonesSchema = z.array(ganttMilestoneSchema).max(100).superRefine((value, context) => {
  if (new Set(value.map(item => item.id.toLowerCase())).size !== value.length) context.addIssue({ code: 'custom', message: 'Marco repetido.' });
});
export type GanttCalendar = z.infer<typeof ganttCalendarSchema>;
export type GanttMilestone = z.infer<typeof ganttMilestoneSchema>;
export const DEFAULT_GANTT_CALENDAR: GanttCalendar = { weekdays: [1, 2, 3, 4, 5, 6, 7], exceptions: [] };
export const ganttProjectSettingsSchema = z.object({
  projeto_id: uuid, calendar: ganttCalendarSchema, milestones: ganttMilestonesSchema,
  updated_at: z.string().datetime({ offset: true }),
});
export type GanttProjectSettings = z.infer<typeof ganttProjectSettingsSchema>;
export const saveGanttSettingsSchema = z.object({
  submissionId: uuid, projeto_id: uuid,
  expected_updated_at: z.string().datetime({ offset: true }), expected_plan_version: ganttRevision,
  calendar: ganttCalendarSchema, milestones: ganttMilestonesSchema,
  reason: z.string().trim().min(3).max(2000),
}).strict();
export type SaveGanttSettingsInput = z.infer<typeof saveGanttSettingsSchema>;
