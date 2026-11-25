import { z } from 'zod';

const id = z.uuid().refine(value => value === value.toLowerCase());
const calendarDay = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const answer = z.union([
  z.literal(true),
  z.string().min(1).max(4000),
  z.array(id).min(1).max(1000),
  z.object({ inicio: calendarDay, fim: calendarDay.optional() }).strict(),
]);
export type OnlineAnswer = z.infer<typeof answer>;

export const onlineFormSubmission = z.object({
  proof: z.string().min(1).max(1800),
  answers: z.record(id, answer).refine(value => {
    const count = Object.keys(value).length;
    return count >= 1 && count <= 1000;
  }),
}).strict();
export type OnlineFormSubmission = z.infer<typeof onlineFormSubmission>;

export function onlineQuestionKind(type: string) {
  switch (type) {
    case 'texto_curto': case 'texto_longo': return 'text';
    case 'numero': return 'number';
    case 'data': return 'date';
    case 'escolha__nica': case 'lista_suspensa': return 'single';
    case 'caixas_de_sele__o': case 'lista_multi_sele__o': return 'multiple';
    default: return null;
  }
}

export function canFillOnline(questions: readonly { tipo: string; obrigatorio: boolean }[]) {
  return questions.some(question => onlineQuestionKind(question.tipo))
    && questions.every(question => question.tipo === 'subt_tulo' || !question.obrigatorio || onlineQuestionKind(question.tipo));
}
