import { createHash } from 'node:crypto';
import { AttachmentBodyTooLarge, boundedAttachmentForm } from '@/server/web/project-dossier-upload';
import { attachmentSignatureMatches } from '@/server/web/project-dossier-policy';
import { storeImmutableDocument } from '@/server/web/project-dossier-storage';
import { WorkshopContextError } from '@/server/web/workshop-context';
import { required } from '@/server/config';
import { operatorToken } from '@/server/operation/policy';
import { authorizeWorkshopMediaUpload, operationService } from '@/server/operation/session';
import { MAX_MEDIA_UPLOAD_BODY, MAX_MEDIA_UPLOAD_METADATA, nativeMediaReceipt, nativeMediaUpload } from '@/server/operation/media-upload-policy';

export const runtime = 'nodejs';
const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
const rpcCodes: Record<string, number> = { '28000': 401, '42501': 403, '22023': 422, PT409: 409 };
function failure(status: number) {
  return Response.json({ error: 'O envio de arquivo aguarda confirmação. Preserve o protocolo no dispositivo.' }, { status, headers });
}

export async function POST(request: Request) {
  const bearer = request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_.-]{50,2800})$/i)?.[1];
  const actor = operatorToken.safeParse(request.headers.get('x-em-operator'));
  if (!bearer || !actor.success) return failure(401);
  if (!/^multipart\/form-data;\s*boundary=/i.test(request.headers.get('content-type') || '')) return failure(415);
  try {
    await operationService.authorizeNativeOperation(bearer, actor.data);
    let form: FormData;
    try { form = await boundedAttachmentForm(request, MAX_MEDIA_UPLOAD_BODY); }
    catch (error) { return failure(error instanceof AttachmentBodyTooLarge ? 413 : 422); }
    const metadata = form.get('input'), file = form.get('file');
    if ([...form.keys()].length !== 2 || form.getAll('input').length !== 1 || form.getAll('file').length !== 1
      || typeof metadata !== 'string' || Buffer.byteLength(metadata) > MAX_MEDIA_UPLOAD_METADATA || !file || typeof file === 'string') return failure(422);
    let decoded: unknown;
    try { decoded = JSON.parse(metadata); } catch { return failure(422); }
    const parsed = nativeMediaUpload.safeParse(decoded);
    if (!parsed.success || file.type !== parsed.data.mime || file.size !== parsed.data.size) return failure(422);
    const input = parsed.data;
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!attachmentSignatureMatches(bytes, input.mime) || createHash('sha256').update(bytes).digest('hex') !== input.sha256) return failure(422);
    const scope = await operationService.authorizeNativeOperation(bearer, actor.data, input.workshopOrigin);
    const reserve = await authorizeWorkshopMediaUpload(scope, input, false);
    if (reserve.error) return failure(rpcCodes[reserve.error.code] ?? 503);
    const authorized = nativeMediaReceipt(reserve.data, input);
    if (!authorized) return failure(503);
    await storeImmutableDocument(authorized.path, bytes, input.mime, input.sha256);
    const current = await operationService.authorizeNativeOperation(bearer, actor.data, input.workshopOrigin);
    const saved = await authorizeWorkshopMediaUpload(current, input, true);
    if (saved.error) return failure(rpcCodes[saved.error.code] ?? 503);
    const confirmed = nativeMediaReceipt(saved.data, input, true);
    if (!confirmed) return failure(503);
    return Response.json({ ...confirmed, url: `${required('SUPABASE_URL')}/storage/v1/object/authenticated/rm-documentos/${confirmed.path}` }, { headers });
  } catch (error) {
    return failure(error instanceof WorkshopContextError ? error.status : 503);
  }
}
