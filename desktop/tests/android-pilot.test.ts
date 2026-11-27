import assert from 'node:assert/strict';
import { test } from 'node:test';
import { androidPilotKey, androidPilotRelease as release } from '../src/shared/android-pilot-release';
import { createAndroidPilotService } from '../src/server/web/android-pilot-policy';
import type { WebAccess } from '../src/server/web/auth-policy';
import { CorporateAuthError } from '../src/server/web/sso-policy';
import { WorkshopContextError, type WorkshopContext } from '../src/server/web/workshop-context';

const client = {} as WebAccess['client'];
const user = {} as Extract<WebAccess, { state: 'authenticated' }>['user'];
const profile = { id: 'local-user', nome: 'Gestor', perfil: 'administrador' };
const sso = { sessionHash: 'session', bindingId: 'binding', subject: 'corporate-user', capabilities: ['em.portal.read' as const] };
const admin: WebAccess = { state: 'authenticated', client, user, profile, sso };
const context = { workshop: { active: true, code: 'BMA' } } as WorkshopContext;
const url = 'https://em.example/api/web/android/instalador';
const signed = `${release.platformOrigin}/storage/v1/object/sign/${release.bucket}/${androidPilotKey}?token=signed-pilot&download=${release.file}`;

test('confirms the active workshop for every installer request before signing', async () => {
  let permitted = true;
  const calls: string[] = [];
  const android = createAndroidPilotService({
    authenticate: async () => { calls.push('session'); return admin; },
    workshop: async identity => {
      calls.push('workshop');
      assert.equal(identity, sso);
      if (!permitted) throw new WorkshopContextError('WORKSHOP_FORBIDDEN');
      return context;
    },
    sign: async () => { calls.push('sign'); return signed; },
  });
  assert.equal(await android.authorize(), 200);
  const result = await android.download(new Request(url));
  assert.equal(result.status, 303);
  assert.equal(result.headers.get('location'), signed);
  assert.equal(result.headers.get('cache-control'), 'private, no-store');
  assert.equal(result.headers.get('vary'), 'Cookie');
  assert.equal(result.headers.get('referrer-policy'), 'no-referrer');
  permitted = false;
  const revoked = await android.download(new Request(url));
  assert.equal(revoked.status, 403);
  assert.equal(revoked.headers.get('location'), null);
  assert.deepEqual(calls, ['session', 'workshop', 'session', 'workshop', 'sign', 'session', 'workshop']);
});

test('rejects incomplete authentication, unrelated accounts and unavailable authorization without signing', async () => {
  const attempts = [
    [401, async () => ({ state: 'anonymous', client })],
    [401, async () => ({ state: 'mfa', client, user, profile, factors: [] })],
    [401, async () => { throw new CorporateAuthError('CORP_MFA_REQUIRED'); }],
    [403, async () => ({ state: 'inactive', client })],
    [403, async () => ({ ...admin, profile: { ...profile, perfil: 'padr_o' } })],
    [403, async () => ({ ...admin, sso: undefined })],
    [403, async () => ({ ...admin, sso: { ...sso, capabilities: [] } })],
    [503, async () => ({ state: 'unconfigured' })],
  ] satisfies Array<[number, Parameters<typeof createAndroidPilotService>[0]['authenticate']]>;
  for (const [status, authenticate] of attempts) {
    const response = await createAndroidPilotService({
      authenticate,
      workshop: async () => { assert.fail('Context read for an unauthorized session'); },
      sign: async () => { assert.fail('Unexpected signing'); },
    }).download(new Request(url));
    assert.equal(response.status, status);
    assert.equal(response.headers.get('location'), null);
  }
  const offline = await createAndroidPilotService({
    authenticate: async () => admin,
    workshop: async () => { throw new WorkshopContextError('WORKSHOP_UNAVAILABLE'); },
    sign: async () => { assert.fail('Signing while authorization is unavailable'); },
  }).download(new Request(url));
  assert.equal(offline.status, 503);
});

test('only redirects to the pinned object with a token and the correct attachment name', async () => {
  const deps = { authenticate: async () => admin, workshop: async () => context };
  const queryAttempt = await createAndroidPilotService({
    ...deps, sign: async () => { assert.fail('Unexpected signing for query parameters'); },
  }).download(new Request(url + '?version=other'));
  assert.equal(queryAttempt.status, 400);
  const urls = [null, 'invalid', signed.replace(release.platformOrigin, 'https://elsewhere.example'),
    signed.replace(release.bucket, 'rm-documentos'), signed.replace('/sign/', '/public/'),
    signed.replace(release.sha256, 'old-object'), signed.replace(release.file + '?', 'other.apk?'),
    signed.replace('&download=', '&name='), signed.replace('signed-pilot', ''), signed + '&token=duplicate', signed + '#download'];
  for (const location of urls) {
    const response = await createAndroidPilotService({ ...deps, sign: async () => location }).download(new Request(url));
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('location'), null);
  }
});
