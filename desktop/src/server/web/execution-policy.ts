import { z } from 'zod';
import { uuid } from './policy';
import { ganttRevision } from './gantt-policy';
import { calendarDay, planningDay } from './gantt';
import type { CorporateCapability } from './sso-policy';

export const EXECUTION_READ_SCOPES: CorporateCapability[] = ['em.portal.read', 'em.planning.read', 'em.projects.read'];
export const EXECUTION_MAX_ALLOCATIONS = 2000, EXECUTION_MAX_SESSIONS = 4000;
export const executionStateSchema = z.enum(['running', 'paused', 'finished', 'review', 'void']);
export const executionKindSchema = z.enum(['start', 'pause', 'resume', 'finish']);
export const executionPauseReasonSchema = z.enum(['material', 'cliente', 'engenharia', 'ferramenta', 'maquina', 'manutencao', 'transporte', 'servico_externo', 'intervalo', 'outro']);
export const executionTimestampSchema = z.string().datetime({ offset: true });
export const executionMinutesSchema = z.number().int().min(0).max(1000000);
const reportedTimestamp = executionTimestampSchema.refine(value => { const day = planningDay(value); return day !== null && day >= calendarDay('1900-01-01')! && day <= calendarDay('2200-12-31')!; });
export const executionFiltersSchema = z.object({ project_id: uuid.nullable(), cell_id: uuid.nullable(), session_id: uuid.nullable(), include_closed: z.boolean() }).strict();
export type ExecutionFilters = z.infer<typeof executionFiltersSchema>;
export const reviewExecutionSessionSchema = z.object({
  submissionId: uuid, session_id: uuid, expected_version: ganttRevision,
  action: z.enum(['confirm_finished', 'void']), reported_finished_at: reportedTimestamp.nullable(),
  effort_minutes: executionMinutesSchema.nullable(), note: z.string().max(1000), reason: z.string().trim().min(3).max(2000),
}).strict().superRefine((value, context) => {
  if (value.action === 'confirm_finished' && !value.reported_finished_at) context.addIssue({ code: 'custom', path: ['reported_finished_at'], message: 'Informe quando o término foi confirmado.' });
  if (value.action === 'void' && (value.reported_finished_at !== null || value.effort_minutes !== null)) context.addIssue({ code: 'custom', message: 'Um apontamento desconsiderado não confirma término ou esforço.' });
});
export type ReviewExecutionSessionInput = z.infer<typeof reviewExecutionSessionSchema>;
