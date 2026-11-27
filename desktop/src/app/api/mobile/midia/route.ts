import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { loadNativeWorkshopMedia } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const requestSchema = z.object({ operatorToken, urls: z.array(z.string().max(2048).regex(/^https:\/\/[^\p{C}]+$/u)).min(1).max(25) }).strict();
const headers = { 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };
const failure = (status: number) => Response.json({ error: 'A mídia da oficina está indisponível.' }, { status, headers });

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return failure(401);
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 125_000);
  let input: z.infer<typeof requestSchema>;
  try { input = requestSchema.parse(JSON.parse(raw ?? 'null')); }
  catch { return failure(400); }
  try {
    const { data, error } = await loadNativeWorkshopMedia(bearer, input.operatorToken, input.urls);
    if (!data) return failure(error?.code === '42501' ? 403 : error?.code === '28000' ? 401 : 503);
    return Response.json(data, { headers });
  } catch (error) {
    return failure(error instanceof WorkshopContextError && [401, 403].includes(error.status) ? error.status : 503);
  }
}
