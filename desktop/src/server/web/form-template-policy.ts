import { z } from 'zod';
import { mutationError, uuid } from './policy';
import { formTemplateContentBytes } from '../../shared/form-template-size';
export { formTemplateContentBytes } from '../../shared/form-template-size';

export const FORM_TEMPLATE_MAX_BYTES = 800_000;
export const questionTypes = ['texto_curto','texto_longo','escolha__nica','caixas_de_sele__o','lista_suspensa','lista_multi_sele__o','foto','foto_antes_depois','data','hora','subt_tulo','colaborador','assinatura','cliente','numero'] as const;
export const questionDimensions = ['_hmico','ceusus','mili_ohms','mega_ohms','volts','kilowatts','amperes','rota__es_por_minuto','hertz','porcentagem','kilo_ohms','watts','cent_metro','dec_metro','metro','mil_metro','mili_amperes','centimetros_c_bicos','micr_metros','milimetros_por_segundo'] as const;
export const questionSubtypes = ['intervalo_de_datas','intervalo_de_hor_rios'] as const;
export const formTypes = ['ordem_de_servico','teste_eletrico_inicial','teste_eletrico_final','ficha_delineamento'] as const;
export const collaboratorProfiles = ['cliente','auditor','vendedor','mobile','padr_o','administrador'] as const;
/** Decimal text is never converted to Number, preserving fractional order. */
export function validTemplateIndex(value: string): boolean {
  if (value.length > 60 || !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value)) return false;
  const [integer, fraction = ''] = value.replace(/^[+-]/, '').split('.');
  const whole = BigInt(integer || '0');
  return whole < 1_000_000_000n || (whole === 1_000_000_000n && !/[1-9]/.test(fraction));
}
export const templateIndexSchema = z.string().refine(validTemplateIndex, 'Use um índice decimal de até 60 caracteres, com módulo até 1.000.000.000.');
const optionalText = z.string().nullable();
export const formTemplateItemSchema = z.object({ id: uuid, indice: templateIndexSchema, descricao: z.string(), description: optionalText }).strict();
export const formTemplateQuestionSchema = z.object({
  id: uuid, indice: templateIndexSchema, enunciado: z.string(), title: optionalText,
  subtitulo: optionalText, tag: optionalText, tipo: z.enum(questionTypes),
  subtipo: z.enum(questionSubtypes).nullable(), dimensoes: z.enum(questionDimensions).nullable(),
  obrigatorio: z.boolean(), colaborador_filtro_perfil: z.enum(collaboratorProfiles).nullable(),
  items: z.array(formTemplateItemSchema).max(5000),
}).strict();
export const formTemplateContentSchema = z.object({
  titulo: z.string(), descricao: optionalText, title: optionalText, description: optionalText,
  tipo: z.enum(formTypes).nullable(), questions: z.array(formTemplateQuestionSchema).max(1000),
}).strict().superRefine((content, context) => {
  let totalItems = 0; const ids = new Set<string>();
  const add = (id: string, path: (string | number)[]) => {
    if (ids.has(id)) context.addIssue({ code: 'custom', path, message: 'Cada questão e opção deve ter um identificador exclusivo.' });
    ids.add(id);
  };
  content.questions.forEach((question, q) => {
    add(question.id, ['questions', q, 'id']); totalItems += question.items.length;
    question.items.forEach((item, i) => add(item.id, ['questions', q, 'items', i, 'id']));
  });
  if (totalItems > 5000) context.addIssue({ code: 'custom', path: ['questions'], message: 'Use até 5.000 opções no formulário.' });
  if (formTemplateContentBytes(content) > FORM_TEMPLATE_MAX_BYTES) context.addIssue({ code: 'custom', path: [], message: 'O conteúdo excede o limite de 800.000 bytes.' });
});
const base = { submissionId: uuid, id: uuid };
const version = z.string().datetime({ offset: true });
export const createFormTemplateSchema = z.object({ ...base, source_form_id: uuid.nullable(), kind: z.enum(['new','copy','version']) }).strict()
  .refine(value => value.kind === 'new' ? value.source_form_id === null : value.source_form_id !== null, 'Escolha um formulário de origem para copiar ou criar versão.');
export const saveFormTemplateSchema = z.object({ ...base, expected_updated_at: version, content: formTemplateContentSchema }).strict();
export const publishFormTemplateSchema = z.object({ ...base, expected_updated_at: version }).strict();
export type FormTemplateContent = z.infer<typeof formTemplateContentSchema>;
export type FormTemplateQuestion = z.infer<typeof formTemplateQuestionSchema>;
export type FormTemplateItem = z.infer<typeof formTemplateItemSchema>;
export type CreateFormTemplateInput = z.input<typeof createFormTemplateSchema>;
export type SaveFormTemplateInput = z.input<typeof saveFormTemplateSchema>;
export type PublishFormTemplateInput = z.input<typeof publishFormTemplateSchema>;
export function formTemplateMutationError(code?: string) {
  if (code === '23505') return { code, error: 'Esta versão ou protocolo já existe. Atualize os dados antes de iniciar outra publicação.' };
  if (code === '23503') return { code, error: 'O formulário de origem ou um vínculo necessário não está disponível.' };
  return mutationError(code);
}
