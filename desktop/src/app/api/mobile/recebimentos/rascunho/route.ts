import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { sendNativeReceivingDraft } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const args = z.discriminatedUnion('action', [z.object({ action: z.literal('read'), draftId: z.uuid().nullable() }).strict(),
  z.object({ action: z.literal('save'), draftId: z.uuid(), expectedRevision: z.number().int().nonnegative(),
    saveId: z.uuid(), payload: z.record(z.string(), z.unknown()) }).strict()]);
const schema = z.object({ operatorToken, workshopOrigin: z.uuid(), args }).strict();
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
const errors: Record<string, [number, string]> = {
  '28000': [401, 'Identifique novamente o operador.'],
  '42501': [403, 'A oficina original do rascunho precisa ser conferida.'],
  '22023': [422, 'Confira o protocolo e a versão do rascunho.'],
  PT409: [409, 'O rascunho mudou no servidor. O trabalho local foi preservado.'],
};
function failure(code: string) {
  const [status, message] = Object.hasOwn(errors, code) ? errors[code] : [503, 'O rascunho continua salvo no aparelho. Tente sincronizar novamente.'];
  return Response.json({ code: status === 503 ? 'PT503' : code, message }, { status, headers });
}

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return failure('28000');
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 1_070_000);
  let input: z.infer<typeof schema>;
  try { input = schema.parse(JSON.parse(raw ?? 'null')); }
  catch { return failure('22023'); }
  try {
    const { data, error } = await sendNativeReceivingDraft(bearer, input.operatorToken, input.workshopOrigin, input.args);
    if (error || (input.args.action === 'save' && !data)) return failure(error?.code ?? 'PT503');
    return Response.json(data, { headers });
  } catch (error) {
    return failure(error instanceof WorkshopContextError && error.status === 401 ? '28000'
      : error instanceof WorkshopContextError && error.status === 403 ? '42501' : 'PT503');
  }
}
