import assert from 'node:assert/strict';
import test from 'node:test';
import { androidProtocolQuery, checkAndroidProtocol } from '../src/server/web/android-protocol';
import { workshopReadCapabilities } from '../src/server/web/workshop-read-policy';

const protocol = '00000000-0000-4000-8000-00000000000a';
const project = '00000000-0000-4000-8000-00000000000b';
const receipt = { protocol, operation: 'rm_submit_recebimento_v1', project_id: project, project_number: null,
  phase: 'opened', recorded_at: '2026-11-27T21:40:00+00:00', last_retry_at: null, form_record_id: null };

test('the Android lookup uses an exact normalized protocol and verifies the receipt before rendering', () => {
  assert.equal(androidProtocolQuery.parse(` ${protocol.toUpperCase()} `), protocol);
  assert.equal(androidProtocolQuery.safeParse([protocol, project]).success, false);
  assert.equal(androidProtocolQuery.safeParse(protocol.slice(0, -1)).success, false);
  assert.deepEqual(checkAndroidProtocol(receipt, protocol), receipt);
  assert.equal(checkAndroidProtocol(null, protocol), null);
  assert.throws(() => checkAndroidProtocol(receipt, project));
  assert.throws(() => checkAndroidProtocol({ ...receipt, operation: 'rm_record_cell_photo_v1' }, protocol));
  assert.throws(() => checkAndroidProtocol({ ...receipt, payload: { note: 'private' } }, protocol));
});

test('the workshop reader requires history and each requested module permission', () => {
  const required = ['em.portal.read', 'em.projects.read', 'em.history.read'];
  assert.deepEqual(workshopReadCapabilities('android_protocol', { forms: false, photos: false }), required);
  assert.deepEqual(workshopReadCapabilities('android_protocol', { forms: true, photos: true, approvals: true, planning: false }),
    [...required, 'em.forms.read', 'em.photos.read', 'em.approvals.read']);
});
