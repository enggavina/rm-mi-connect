import { z } from 'zod';
import { mutationError, uuid } from './policy';

export const editableCatalogKinds = ['clients', 'cells', 'types'] as const;
export const editableCatalogKindSchema = z.enum(editableCatalogKinds);
export type EditableCatalogKind = z.infer<typeof editableCatalogKindSchema>;
const timestamp = z.string().datetime({ offset: true });
const name = z.string().trim().min(1, 'Informe o nome.').max(200);
const text = (max: number) => z.string().trim().max(max).transform(value => value || null).nullable().optional();
const index = z.number().int().min(0).max(1_000_000).nullable().optional();
const base = { submissionId: uuid, id: uuid, expected_updated_at: timestamp.nullable() };
const nonempty = <T extends Record<string, unknown>>(value: T) => Object.values(value).some(item => item !== undefined);
export const saveCatalogSchema = z.discriminatedUnion('kind', [
  z.object({ ...base, kind: z.literal('clients'), changes: z.object({ nome: name.optional(), codigo: text(80), descricao: text(4000) }).strict().refine(nonempty, 'Informe uma alteração.') }).strict(),
  z.object({ ...base, kind: z.literal('cells'), changes: z.object({ nome: name.optional(), codigo: text(80), indice: index, ordem: index }).strict().refine(nonempty, 'Informe uma alteração.') }).strict(),
  z.object({ ...base, kind: z.literal('types'), changes: z.object({ nome: name.optional(), sigla: text(30) }).strict().refine(nonempty, 'Informe uma alteração.') }).strict(),
]).superRefine((value, context) => {
  if (value.expected_updated_at === null && !value.changes.nome) context.addIssue({ code: 'custom', path: ['changes', 'nome'], message: 'Informe o nome do novo cadastro.' });
});
export const deleteCatalogSchema = z.object({ submissionId: uuid, kind: editableCatalogKindSchema, id: uuid, expected_updated_at: timestamp }).strict();
export type SaveCatalogInput = z.input<typeof saveCatalogSchema>;
export type DeleteCatalogInput = z.input<typeof deleteCatalogSchema>;

export function catalogMutationError(code?: string) {
  if (code === '23503') return { code, error: 'Este cadastro possui vínculos que impedem a alteração. Preserve os registros relacionados.' };
  if (code === '23505') return { code, error: 'Já existe um cadastro com esse nome ou o protocolo foi usado com outros dados. Confira os dados e atualize a tela.' };
  return mutationError(code);
}
