export const projectMilestoneFields = ['data_inicio_peritagem', 'data_fim_peritagem', 'data_inicio_reparo', 'data_fim_reparo'] as const;
type MilestoneField = typeof projectMilestoneFields[number];
type CalendarValues = Record<MilestoneField, string | null>;

/** Validate the complete visible pairs before submitting only changed fields. */
export function projectMilestoneChanges(values: CalendarValues, project?: Record<string, unknown>):
  { error: string; changes: null } | { error: ''; changes: Partial<CalendarValues> } {
  if (values.data_inicio_peritagem && values.data_fim_peritagem && values.data_inicio_peritagem > values.data_fim_peritagem)
    return { error: 'O fim da peritagem não pode ser anterior ao início.', changes: null };
  if (values.data_inicio_reparo && values.data_fim_reparo && values.data_inicio_reparo > values.data_fim_reparo)
    return { error: 'O fim do reparo não pode ser anterior ao início.', changes: null };
  const changes: Partial<CalendarValues> = {};
  for (const field of projectMilestoneFields) if (!project || values[field] !== (project[field] ?? null)) changes[field] = values[field];
  return { error: '', changes };
}
