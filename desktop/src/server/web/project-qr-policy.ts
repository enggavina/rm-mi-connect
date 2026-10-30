import { z } from 'zod';

/** Project identity only: no alias, URL, customer data, credential or bearer token. */
export const projectQrIdSchema = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  .transform(value => value.toLowerCase());
export const projectQrSchema = z.object({ id: projectQrIdSchema, numero: z.string().nullable(), nome: z.string().nullable(),
  descricao_equipamento: z.string().nullable(), updated_at: z.string().datetime({ offset: true }) }).strict();
export type ProjectQrProject = z.infer<typeof projectQrSchema>;
export function projectQrValue(projectId: string): string { return projectQrIdSchema.parse(projectId); }
