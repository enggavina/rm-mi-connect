import { z } from 'zod';
import type { SsoContext } from './auth-policy';
import { cellOperatorAccess } from './sso-bridge';

export const cellOperatorChange = z.object({
  cell: z.uuid(), operator: z.uuid(), enabled: z.enum(['grant', 'revoke']),
  revision: z.string().regex(/^(0|[1-9]\d{0,9})$/).transform(Number).pipe(z.number().int().max(2_147_483_647)),
}).strict();

const operatorRow = z.object({
  id: z.uuid(), nome: z.string().nullable(), matricula: z.string().nullable(),
  eligible: z.boolean(), automatic: z.boolean(), managed: z.boolean(), legacy: z.boolean(),
  revision: z.number().int().nonnegative(),
}).strict();
export type CellOperator = z.infer<typeof operatorRow>;
export type CellOperatorActionState = { message: string; error: boolean };

export async function getCellOperators(context: SsoContext, cell: string): Promise<CellOperator[] | null> {
  if (!z.uuid().safeParse(cell).success) return null;
  try {
    const result = await cellOperatorAccess(context, cell);
    const parsed = z.array(operatorRow).safeParse(result.data);
    return result.error || !parsed.success ? null : parsed.data;
  } catch {
    return null;
  }
}
