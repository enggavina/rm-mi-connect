import assert from 'node:assert/strict';
import test from 'node:test';
import type { WebAccess } from '../src/server/web/auth-policy';
import { CorporateAuthError } from '../src/server/web/sso-policy';
import { WorkshopContextError } from '../src/server/web/workshop-context';
import { canUseOperationValidation, createOperationValidationReader } from '../src/server/operation/validation-policy';
import type { OperationSelection } from '../src/server/operation/policy';

const authorized: Extract<WebAccess, { state: 'authenticated' }> = {
  state: 'authenticated',
  client: {} as Extract<WebAccess, { state: 'authenticated' }>['client'],
  user: { id: '11111111-1111-4111-8111-111111111111' } as Extract<WebAccess, { state: 'authenticated' }>['user'],
  profile: { id: '2e70c7e9-3ed2-47fa-9860-9501aeac96cc', nome: 'Validador local', perfil: 'administrador' },
  sso: {
    subject: 'a9e45880-1924-4b2d-a2b1-dc12fd029bff',
    bindingId: 'ae29e9a9-9c50-4d25-81eb-6a01202bc20a',
    sessionHash: 'sessao-local',
    capabilities: ['em.portal.read', 'em.projects.read', 'em.planning.read'],
  },
};
const cellId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const otherId = '22222222-2222-4222-8222-222222222222';
const cell = { id: cellId, nome: 'Célula local' };

test('validation requires the exact corporate session and current EM abilities', async () => {
  assert.ok(canUseOperationValidation(authorized));
  const deny: WebAccess[] = [
    { state: 'inactive', client: authorized.client },
    { ...authorized, sso: undefined },
    { ...authorized, sso: { ...authorized.sso!, subject: otherId } },
    { ...authorized, sso: { ...authorized.sso!, bindingId: otherId } },
    { ...authorized, profile: { ...authorized.profile, id: otherId } },
    { ...authorized, profile: { ...authorized.profile, perfil: 'auditor' } },
    { ...authorized, sso: { ...authorized.sso!, capabilities: ['em.portal.read', 'em.projects.read'] } },
  ];
  for (const access of deny) {
    assert.ok(!canUseOperationValidation(access));
    const load = createOperationValidationReader({ authenticate: async () => access, workshopRead: () => assert.fail('called read for a denied identity') });
    assert.deepEqual(await load(), { status: 'forbidden' });
  }
});

test('corporate validation reauthenticates and calls only the dedicated projection with normalized filters', async () => {
  let authCalls = 0;
  let readCalls = 0;
  const load = createOperationValidationReader({
    authenticate: async () => { authCalls++; return authorized; },
    workshopRead: access => async (resource, args) => {
      assert.strictEqual(access, authorized);
      assert.equal(resource, 'operation_validation');
      assert.deepEqual(args, { cell_id: cellId, project_id: null, page: 2 });
      readCalls++;
      return { kind: 'projects', cell, items: [], total: 1, page: 2, page_size: 25 };
    },
  });
  const selected = { cellId: cellId.toUpperCase(), page: '2', workshop: 'BRJ' } as OperationSelection;
  const result = await load(selected);
  assert.deepEqual(result, { status: 'ok', workshop: { name: 'BMA', code: 'BMA' }, operatorName: 'Validador local',
    data: { kind: 'projects', cell, items: [], total: 1, page: 2, page_size: 25 } });
  await load(selected);
  assert.equal(authCalls, 2);
  assert.equal(readCalls, 2);
});

test('corporate validation closes on session, context and projection failures', async () => {
  const onFailure = (error: unknown, auth = false) => createOperationValidationReader({
    authenticate: async () => { if (auth) throw error; return authorized; },
    workshopRead: () => async () => { throw error; },
  });
  const anonymous = createOperationValidationReader({ authenticate: async () => ({ state: 'anonymous', client: authorized.client }),
    workshopRead: () => assert.fail('called read without a session') });
  assert.deepEqual(await anonymous(), { status: 'session' });
  assert.deepEqual(await onFailure(new CorporateAuthError('CORP_UNAUTHORIZED'), true)(), { status: 'session' });
  assert.deepEqual(await onFailure(new WorkshopContextError('WORKSHOP_FORBIDDEN'))(), { status: 'forbidden' });
  assert.deepEqual(await onFailure(new WorkshopContextError('WORKSHOP_UNAVAILABLE'))(), { status: 'unavailable' });

  const load = (payload: unknown) => createOperationValidationReader({ authenticate: async () => authorized,
    workshopRead: () => async () => payload });
  assert.deepEqual(await load(null)({ cellId }), { status: 'missing' });
  assert.deepEqual(await load({ kind: 'projects', cell: { ...cell, id: otherId }, items: [], total: 0, page: 1, page_size: 25 })({ cellId }),
    { status: 'unavailable' });
  const noRead = createOperationValidationReader({ authenticate: async () => authorized, workshopRead: () => assert.fail('called read for invalid filter') });
  assert.deepEqual(await noRead({ projectId: cellId }), { status: 'missing' });
});
