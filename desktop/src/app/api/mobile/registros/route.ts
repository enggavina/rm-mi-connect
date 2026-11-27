import { z } from 'zod';
import { operatorToken, readOperationText } from '@/server/operation/policy';
import { sendNativeWorkshopMutation } from '@/server/operation/session';
import { WorkshopContextError } from '@/server/web/workshop-context';

const commands = ['rm_submit_form_inspection_v1', 'rm_submit_form_revision_v1', 'rm_record_cell_photo_v1',
  'rm_transition_stage_approval_v1', 'rm_update_cell_status_v1', 'rm_add_cell_comment_v1', 'rm_record_execution_event_v1'] as const;
const schema = z.object({ operatorToken, submission: z.uuid(), operation: z.enum(commands), payload: z.record(z.string(), z.unknown()) }).strict();
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
const errors: Record<string, [number, string]> = {
  '28000': [401, 'Identifique novamente o operador responsável neste dispositivo.'],
  '42501': [403, 'O registro está fora da oficina autorizada ou precisa de conferência.'],
  '22023': [422, 'Confira os dados do protocolo original.'],
  'P0002': [404, 'Registro indisponível.'],
  'PT409': [409, 'O registro mudou. O protocolo original permanece salvo.'],
  'PT410': [410, 'O projeto foi encerrado. Preserve o protocolo para conferência.'],
  'PT422': [422, 'Confira os dados do protocolo original.'],
};
function failure(code: string) {
  const [status, message] = Object.hasOwn(errors, code) ? errors[code] : [503, 'Não foi possível enviar o registro. Tente com o mesmo protocolo.'];
  return Response.json({ code: status === 503 ? 'PT503' : code, message }, { status, headers });
}

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  if (!bearer) return failure('28000');
  const raw = await readOperationText(request, /^application\/json(?:\s*;|$)/i, 2_110_000);
  let input: z.infer<typeof schema>;
  try { input = schema.parse(JSON.parse(raw ?? 'null')); }
  catch { return failure('22023'); }
  try {
    const { data, error } = await sendNativeWorkshopMutation(bearer, input.operatorToken, input.submission, input.operation, input.payload);
    return error || !data ? failure(error?.code ?? 'PT503') : Response.json(data, { headers });
  } catch (error) {
    return failure(error instanceof WorkshopContextError && error.status === 401 ? '28000'
      : error instanceof WorkshopContextError && error.status === 403 ? '42501' : 'PT503');
  }
}
