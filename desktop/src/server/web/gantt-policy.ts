import { z } from 'zod';
import { uuid } from './policy';
import { calendarDay } from './gantt';

export const GANTT_MAX_ITEMS = 2000;
export const GANTT_MAX_LINKS = 4000;
export const ganttRevision = z.string().regex(/^[0-9a-f]{64}$/);
const timestamp = z.string().datetime({ offset: true });
const day = z.string().refine(value => calendarDay(value) !== null && value >= '1900-01-01' && value <= '2200-12-31', 'Informe uma data válida entre 1900 e 2200.');
const identity = (value: string) => value.toLowerCase();

export const ganttFiltersSchema = z.object({
  project_id: uuid.nullable(), cell_id: uuid.nullable(), include_closed: z.boolean(),
}).strict().superRefine((value, context) => {
  if (value.project_id && value.cell_id) context.addIssue({ code: 'custom', message: 'Escolha um projeto ou uma célula.' });
  if (value.project_id && !value.include_closed) context.addIssue({ code: 'custom', message: 'A visão do projeto deve incluir o roteiro completo.' });
});
export type GanttFilters = z.infer<typeof ganttFiltersSchema>;

export const ganttLinkInputSchema = z.object({
  predecessor_id: uuid, successor_id: uuid, lag_days: z.number().int().min(0).max(3650),
}).strict().superRefine((value, context) => {
  if (identity(value.predecessor_id) === identity(value.successor_id)) {
    context.addIssue({ code: 'custom', message: 'Uma etapa não pode depender dela mesma.' });
  }
});

const dateChanges = z.object({ data_inicio: day.nullable().optional(), data_limite: day.nullable().optional() }).strict()
  .superRefine((value, context) => {
    if (!Object.keys(value).length) context.addIssue({ code: 'custom', message: 'Informe a alteração de prazo.' });
    if (value.data_inicio && value.data_limite && value.data_inicio > value.data_limite) {
      context.addIssue({ code: 'custom', path: ['data_limite'], message: 'O prazo não pode ser anterior ao início.' });
    }
  });

/** Exact revisions and submission IDs survive retries; the caller never supplies an actor. */
export const saveGanttPlanSchema = z.object({
  submissionId: uuid,
  reason: z.string().trim().min(3).max(2000),
  projects: z.array(z.object({ id: uuid, expected_updated_at: timestamp, expected_plan_version: ganttRevision }).strict()).min(1).max(GANTT_MAX_ITEMS),
  items: z.array(z.object({ id: uuid, expected_updated_at: timestamp, changes: dateChanges }).strict()).max(GANTT_MAX_ITEMS),
  dependencies: z.object({ projeto_id: uuid, links: z.array(ganttLinkInputSchema).max(GANTT_MAX_LINKS) }).strict().optional(),
  baseline: z.object({ projeto_id: uuid, label: z.string().trim().min(1).max(120) }).strict().optional(),
}).strict().superRefine((value, context) => {
  const projects = new Set(value.projects.map(project => identity(project.id)));
  if (projects.size !== value.projects.length) context.addIssue({ code: 'custom', path: ['projects'], message: 'Projeto repetido.' });
  if (new Set(value.items.map(item => identity(item.id))).size !== value.items.length) {
    context.addIssue({ code: 'custom', path: ['items'], message: 'Etapa repetida.' });
  }
  if (!value.items.length && !value.dependencies && !value.baseline) {
    context.addIssue({ code: 'custom', message: 'Informe uma alteração ou uma referência do plano.' });
  }
  for (const key of ['dependencies', 'baseline'] as const) {
    const part = value[key];
    if (part && !projects.has(identity(part.projeto_id))) context.addIssue({ code: 'custom', path: [key], message: 'O projeto precisa fazer parte da revisão enviada.' });
  }
  if (value.dependencies && value.projects.length !== 1) {
    context.addIssue({ code: 'custom', path: ['dependencies'], message: 'Edite as dependências no contexto de um único projeto.' });
  }
  if (value.baseline && (value.projects.length !== 1 || value.items.length > 0 || value.dependencies)) {
    context.addIssue({ code: 'custom', path: ['baseline'], message: 'Salve as alterações antes de criar uma referência do projeto.' });
  }
  if (value.dependencies) {
    const links = value.dependencies.links;
    if (new Set(links.map(link => `${identity(link.predecessor_id)}:${identity(link.successor_id)}`)).size !== links.length) {
      context.addIssue({ code: 'custom', path: ['dependencies', 'links'], message: 'Dependência repetida.' });
    }
    // SQL remains authoritative, including links outside a filtered cell view.
    const outgoing = new Map<string, string[]>(), indegree = new Map<string, number>();
    for (const link of links) {
      const from = identity(link.predecessor_id), to = identity(link.successor_id);
      outgoing.set(from, [...(outgoing.get(from) ?? []), to]);
      if (!indegree.has(from)) indegree.set(from, 0);
      indegree.set(to, (indegree.get(to) ?? 0) + 1);
    }
    const queue = [...indegree.keys()].filter(id => indegree.get(id) === 0);
    let visited = 0;
    for (let cursor = 0; cursor < queue.length; cursor++) {
      visited++;
      for (const next of outgoing.get(queue[cursor]) ?? []) {
        indegree.set(next, indegree.get(next)! - 1);
        if (!indegree.get(next)) queue.push(next);
      }
    }
    if (visited !== indegree.size) context.addIssue({ code: 'custom', path: ['dependencies', 'links'], message: 'As dependências formam um ciclo.' });
  }
});
export type SaveGanttPlanInput = z.infer<typeof saveGanttPlanSchema>;
export type GanttLinkInput = z.infer<typeof ganttLinkInputSchema>;
