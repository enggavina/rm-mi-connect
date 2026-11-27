import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { operationService } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const schema = z.object({ operatorToken, cellId: z.uuid().optional(), projectId: z.uuid().optional(),
  page: z.number().int().min(1).max(10_000).optional() }).strict();
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
const errors: Record<number, string> = {
  400: 'Selecione uma célula e um projeto válidos.',
  401: 'Identifique novamente o operador neste dispositivo.',
  403: 'Consulta indisponível para este dispositivo e operador.',
  404: 'Registro indisponível nesta oficina.',
  503: 'Não foi possível confirmar os dados da oficina. Tente novamente.',
};
const failure = (status: number) => Response.json({ error: errors[status] }, { status, headers });

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return failure(401);
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 4096);
  let input: z.infer<typeof schema>;
  try { input = schema.parse(JSON.parse(raw ?? 'null')); }
  catch { return failure(400); }
  const { operatorToken: delegation, ...selection } = input;
  if (selection.projectId && !selection.cellId) return failure(400);
  try {
    const result = await operationService.loadNativeCatalog(bearer, delegation, selection);
    return result ? Response.json(result, { headers }) : failure(404);
  } catch (error) {
    return failure(error instanceof WorkshopContextError && [401, 403].includes(error.status) ? error.status : 503);
  }
}
