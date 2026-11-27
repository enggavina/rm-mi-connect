import { z } from 'zod';
import { MAX_PROJECT_ATTACHMENT_BYTES } from '../web/project-dossier-policy';

export const MAX_MEDIA_UPLOAD_METADATA = 2_110_000;
export const MAX_MEDIA_UPLOAD_BODY = MAX_PROJECT_ATTACHMENT_BYTES + MAX_MEDIA_UPLOAD_METADATA + 16 * 1024;
const uploadMime = z.enum(['image/jpeg', 'image/png', 'application/pdf']);
const uploadKind = z.enum(['photo', 'signature', 'document']);
const extensions = { 'image/jpeg': 'jpg', 'image/png': 'png', 'application/pdf': 'pdf' } as const;
const limits = { photo: 15 * 1024 ** 2, signature: 5 * 1024 ** 2, document: MAX_PROJECT_ATTACHMENT_BYTES } as const;
const kinds = { photo: ['image/jpeg', 'image/png'], signature: ['image/png'], document: Object.keys(extensions) };

export const nativeMediaUpload = z.object({ workshopOrigin: z.uuid(), submission: z.uuid(), asset: z.uuid(),
  operation: z.enum(['receiving_draft', 'rm_submit_recebimento_v1', 'rm_record_cell_photo_v1', 'rm_submit_form_inspection_v1', 'rm_submit_form_revision_v1']),
  payload: z.record(z.string(), z.unknown()), kind: uploadKind, mime: uploadMime, size: z.number().int().positive(),
  reference: z.string().min(40).max(1024).regex(/^file:\/\/\/[^\p{C}]+$/u), sha256: z.string().regex(/^[0-9a-f]{64}$/),
}).strict().refine(input => input.size <= limits[input.kind] && kinds[input.kind].includes(input.mime)
  && (input.operation !== 'receiving_draft' || (input.kind !== 'signature' && input.payload.p_receiving_draft_id === input.submission))
  && input.reference.endsWith(`/${input.asset}.${extensions[input.mime]}`));
export type NativeMediaUpload = z.infer<typeof nativeMediaUpload>;

export function nativeMediaStoragePath(input: Pick<NativeMediaUpload, 'workshopOrigin' | 'submission' | 'asset' | 'mime'>) {
  return `mobile-oficina/${input.workshopOrigin.toLowerCase()}/${input.submission.toLowerCase()}/${input.asset.toLowerCase()}.${extensions[input.mime]}`;
}

const receipt = z.object({ asset_id: z.uuid(), workshop_id: z.uuid(), submission_id: z.uuid(), path: z.string(), stored: z.boolean() }).strict();
export function nativeMediaReceipt(value: unknown, input: NativeMediaUpload, mustBeStored = false) {
  const parsed = receipt.safeParse(value);
  if (!parsed.success || (mustBeStored && !parsed.data.stored)) return null;
  return parsed.data.asset_id === input.asset && parsed.data.workshop_id === input.workshopOrigin
    && parsed.data.submission_id === input.submission && parsed.data.path === nativeMediaStoragePath(input) ? parsed.data : null;
}
