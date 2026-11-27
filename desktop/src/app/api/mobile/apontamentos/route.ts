import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { loadNativeWorkshopExecution } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const input = z.object({ operatorToken, workshopOrigin: z.uuid(), allocation: z.uuid() }).strict();
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
const statuses: Record<string, number> = { '28000': 401, '42501': 403, '22023': 422, P0002: 404, PT413: 413 };
function unavailable(code: string) {
  const status = Object.hasOwn(statuses, code) ? statuses[code] : 503;
  return Response.json({ code: status === 503 ? 'PT503' : code, message: 'Não foi possível confirmar os apontamentos desta etapa.' }, { status, headers });
}

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return unavailable('28000');
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 4096);
  let value: z.infer<typeof input>;
  try { value = input.parse(JSON.parse(raw ?? 'null')); }
  catch { return unavailable('22023'); }
  try {
    const { data, error } = await loadNativeWorkshopExecution(bearer, value.operatorToken, value.workshopOrigin, value.allocation);
    return data && !error ? Response.json(data, { headers }) : unavailable(error?.code ?? 'PT503');
  } catch (error) {
    return unavailable(error instanceof WorkshopContextError && error.status === 403 ? '42501'
      : error instanceof WorkshopContextError && error.status === 401 ? '28000' : 'PT503');
  }
}
