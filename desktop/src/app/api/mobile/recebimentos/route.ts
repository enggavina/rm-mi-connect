import { NextResponse } from 'next/server';
import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { sendNativeReceiving } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const command = z.object({
  submission: z.uuid(),
  phase: z.enum(['open', 'complete']),
  operatorToken,
  payload: z.record(z.string(), z.unknown()),
}).strict();

const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
const errors: Record<string, [number, string]> = {
  '28000': [401, 'Identifique novamente o operador responsável neste dispositivo.'],
  '42501': [403, 'O recebimento está fora da oficina autorizada ou tem origem pendente de revisão.'],
  '22023': [422, 'Confira os dados do protocolo original de recebimento.'],
  'P0002': [404, 'Projeto indisponível.'],
  'PT409': [409, 'O recebimento precisa ser conferido. O protocolo original permanece salvo.'],
  'PT410': [410, 'O projeto foi encerrado. Preserve o protocolo original para conferência.'],
};
function failure(code: string) {
  const [status, message] = Object.hasOwn(errors, code) ? errors[code]
    : [503, 'Não foi possível confirmar o envio. Tente novamente com o mesmo protocolo.'];
  return NextResponse.json({ code: status === 503 ? 'PT503' : code, message }, { status, headers });
}

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return failure('28000');
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 2_110_000);
  let input: z.infer<typeof command>;
  try { input = command.parse(JSON.parse(raw ?? 'null')); }
  catch { return failure('22023'); }
  try {
    const { data, error } = await sendNativeReceiving(bearer, input.operatorToken, input.submission, input.phase, input.payload);
    if (error || !data) return failure(error?.code ?? 'PT503');
    return NextResponse.json(data, { headers });
  } catch (error) {
    if (error instanceof WorkshopContextError) {
      if (error.status === 401) return failure('28000');
      if (error.status === 403) return failure('42501');
    }
    return failure('PT503');
  }
}
