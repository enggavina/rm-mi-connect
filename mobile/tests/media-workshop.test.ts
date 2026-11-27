import assert from 'node:assert/strict';
import test from 'node:test';
import { readWorkshopMedia, workshopMediaCacheKey } from '../src/core/media-workshop';

const origin = 'https://example.supabase.co';
const session = { deviceToken: 'example-device', operatorToken: 'example-operator', workshopId: 'example-workshop' };
const reference = `${origin}/storage/v1/object/public/rm-fotos/device/photo.jpg`;
const resolved = `${origin}/storage/v1/object/sign/rm-fotos/device/photo.jpg?token=example`;

test('native media pairs the exact request with its confirmed workshop and keeps cached operators separate', async () => {
  const read = await readWorkshopMedia(session, [reference, `${reference}.removed`], origin, async (url, options) => {
    assert.match(String(url), /\/api\/mobile\/midia$/);
    assert.equal(options?.redirect, 'error');
    assert.equal(new Headers(options?.headers).get('Authorization'), `Bearer ${session.deviceToken}`);
    assert.deepEqual(JSON.parse(String(options?.body)), { operatorToken: session.operatorToken, urls: [reference, `${reference}.removed`] });
    return Response.json({ workshop_id: session.workshopId, files: [{ reference, url: resolved }] });
  });
  assert.deepEqual([...read], [[reference, resolved]]);
  assert.notEqual(workshopMediaCacheKey('bma', 'one', reference), workshopMediaCacheKey('brj', 'one', reference));
  assert.notEqual(workshopMediaCacheKey('bma', 'one', reference), workshopMediaCacheKey('bma', 'two', reference));
});

test('native media refuses an unrelated workshop, an unrequested file or direct storage address', async () => {
  const entries = [
    { workshop_id: 'different', files: [{ reference, url: resolved }] },
    { workshop_id: session.workshopId, files: [{ reference: `${reference}.other`, url: resolved }] },
    { workshop_id: session.workshopId, files: [{ reference, url: reference }] },
  ];
  for (const entry of entries) {
    await assert.rejects(readWorkshopMedia(session, [reference], origin, async () => Response.json(entry)));
  }
});
