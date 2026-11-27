import assert from 'node:assert/strict';
import test from 'node:test';
import { nativeMediaReceipt, nativeMediaStoragePath, nativeMediaUpload } from '../src/server/operation/media-upload-policy';
import { isNativeWorkshopMedia, workshopMediaTarget } from '../src/server/web/workshop-media';

const id = (suffix: number) => `00000000-0000-4000-8000-${String(suffix).padStart(12, '0')}`;
const invoice = { workshopOrigin: id(4), submission: id(5), asset: id(6), operation: 'rm_submit_recebimento_v1',
  payload: {}, kind: 'document', mime: 'application/pdf', size: 318, sha256: '8'.repeat(64), reference: `file:///local/rm-media/${id(6)}.pdf` };

test('native media rejects a mismatched local file, kind or oversized upload', () => {
  assert.ok(nativeMediaUpload.safeParse(invoice).success);
  for (const input of [{ ...invoice, asset: id(7) }, { ...invoice, kind: 'photo' }, { ...invoice, size: 30 * 1024 ** 2 },
    { ...invoice, reference: `https://example.invalid/${id(6)}.pdf` }]) assert.equal(nativeMediaUpload.safeParse(input).success, false);
});

test('media issuance requires the exact workshop, protocol and server path to confirm immutable storage', () => {
  const input = nativeMediaUpload.parse(invoice), path = nativeMediaStoragePath(input);
  const receipt = { workshop_id: id(4), submission_id: id(5), asset_id: id(6), path, stored: true };
  assert.deepEqual(nativeMediaReceipt(receipt, input, true), receipt);
  for (const entry of [{ ...receipt, stored: false }, { ...receipt, path: `mobile-oficina/${id(99)}/${id(5)}/${id(6)}.pdf` },
    { ...receipt, workshop_id: id(10) }]) assert.equal(nativeMediaReceipt(entry, input, true), null);
  const origin = 'https://example.supabase.co';
  const stored = `${origin}/storage/v1/object/authenticated/rm-documentos/${path}`;
  assert.equal(isNativeWorkshopMedia(stored, origin), true);
  assert.deepEqual(workshopMediaTarget(stored, origin, 'document'), { kind: 'storage', origin, bucket: 'rm-documentos', path });
  assert.equal(isNativeWorkshopMedia(stored.replace('/authenticated/', '/public/'), origin), false);
  assert.equal(isNativeWorkshopMedia(stored.replace('/mobile-oficina/', '/other/../mobile-oficina/'), origin), false);
});
