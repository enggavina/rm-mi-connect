import { z } from 'zod';

const uuid = z.string().uuid().transform(value => value.toLowerCase()), timestamp = z.string().datetime({ offset: true }), text = z.string().nullable();
const optionalId = z.preprocess(value => value === '' || value === undefined ? null : value, uuid.nullable());
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const date = new Date(`${value}T12:00:00Z`);
  return value.slice(0, 4) !== '0000' && Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}, 'Confira a data.');
const optionalDay = z.preprocess(value => value === '' || value === undefined ? null : value, day.nullable());
const search = z.string().trim().max(200).refine(value => !value.includes('\u0000')).default('');
const page = z.preprocess(value => value === undefined || value === '' ? 1 : typeof value === 'string' && /^[1-9]\d{0,5}$/.test(value) ? Number(value) : value, z.number().int().min(1).max(100_000));
const common = { search, author_id: optionalId, from_date: optionalDay, to_date: optionalDay };
const period = (value: { from_date: string | null; to_date: string | null }, context: z.RefinementCtx) => {
  if (value.from_date && value.to_date && value.from_date > value.to_date) context.addIssue({ code: 'custom', path: ['to_date'], message: 'A data final deve ser igual ou posterior à inicial.' });
};
export const projectCommentFiltersSchema = z.object({ ...common, cell_id: optionalId, page }).strict().superRefine(period);
export const projectDocumentFiltersSchema = z.object({ ...common, source: z.enum(['all', 'documents', 'docs']).default('all'),
  status: z.enum(['all', 'No prazo', 'Vencido', 'other']).default('all'), page }).strict().superRefine(period);
export type ProjectCommentFilters = z.infer<typeof projectCommentFiltersSchema>;
export type ProjectDocumentFilters = z.infer<typeof projectDocumentFiltersSchema>;

const author = z.object({ id: uuid, nome: text, matricula: text }).strict();
const resultCommon = { project_id: uuid, total: z.number().int().nonnegative(), unfiltered_total: z.number().int().nonnegative(),
  page: z.number().int().positive(), page_size: z.literal(25) };
export const projectCommentPageSchema = z.object({ ...resultCommon,
  filters: z.object({ search: z.string(), author_id: uuid.nullable(), cell_id: uuid.nullable(), from_date: day.nullable(), to_date: day.nullable() }).strict(),
  items: z.array(z.object({ id: uuid, projeto_id: uuid, celula_id: uuid.nullable(), cadastrado_por_id: uuid.nullable(), evento: text,
    created_at: timestamp, author_name: text, author_registration: text, cell_name: text }).strict()).max(25),
  facets: z.object({ authors: z.array(author).max(10_000), cells: z.array(z.object({ id: uuid, nome: text }).strict()).max(10_000) }).strict(),
}).strict();
export const projectDocumentPageSchema = z.object({ ...resultCommon,
  filters: z.object({ search: z.string(), author_id: uuid.nullable(), source: z.enum(['all', 'documents', 'docs']),
    status: z.enum(['all', 'No prazo', 'Vencido', 'other']), from_date: day.nullable(), to_date: day.nullable() }).strict(),
  items: z.array(z.object({ id: uuid, source: z.enum(['documents', 'docs']), projeto_id: uuid, nome: text, descricao: text,
    tipo_arquivo: text, tipo_documento: text, status: text, data_vencimento: timestamp.nullable(), created_by: uuid.nullable(),
    author_name: text, author_registration: text, created_at: timestamp, has_file: z.boolean(), visivel_cliente: z.boolean().nullable() }).strict()).max(25),
  facets: z.object({ authors: z.array(author).max(10_000), statuses: z.array(z.object({ value: z.enum(['No prazo', 'Vencido', 'other']), label: z.string() }).strict()).max(3) }).strict(),
}).strict();
export type ProjectCommentPage = z.infer<typeof projectCommentPageSchema>;
export type ProjectDocumentPage = z.infer<typeof projectDocumentPageSchema>;
