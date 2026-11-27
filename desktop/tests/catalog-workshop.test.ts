import test from 'node:test';
import assert from 'node:assert/strict';
import { createCatalogWorkshopAuthorizer, isScopedCatalogWrite, isScopedTemplateWrite } from '../src/server/web/catalog-workshop';
import { CORPORATE_ISSUER, CorporateAuthError, type VerifiedCorporateSession } from '../src/server/web/sso-policy';
import { WorkshopContextError, type WorkshopContext } from '../src/server/web/workshop-context';
import type { SsoContext } from '../src/server/web/auth-policy';

const subject = '00000000-0000-4000-8000-000000000001';
function session(): VerifiedCorporateSession { return { accessToken: 'synthetic.jwt.signature', user: { id: subject, email: 'qa@example.invalid' }, expiresAt: Date.now() + 60_000,
  decision: { application: 'em', issuer: CORPORATE_ISSUER, subject, app_access: true, capabilities: ['em.catalogs.manage'], all_employees: false, fields: [], export_allowed: false } }; }
function sso(): SsoContext { return { subject, bindingId: subject, sessionHash: 'test-hash', capabilities: ['em.catalogs.manage'] }; }
function workshop(): WorkshopContext { return { version: 2, application: 'em', channel: 'web', authority: CORPORATE_ISSUER,
  workshop: { id: subject, code: 'BMA', name: 'BMA', active: true, revision: 1, updated_at: new Date().toISOString() },
  principals: [{ kind: 'corporate', issuer: CORPORATE_ISSUER, subject, revision: 1 }], issued_at: new Date().toISOString(), expires_at: new Date(Date.now() + 60_000).toISOString() }; }

test('only exact client/type save and delete operations require workshop confirmation', () => {
  for (const operation of ['save_catalog', 'delete_catalog']) for (const kind of ['clients', 'types']) assert.equal(isScopedCatalogWrite(operation, { kind }), true);
  for (const kind of ['cells', 'forms', 'types ', null, ['clients'], { toString: () => 'clients' }]) assert.equal(isScopedCatalogWrite('save_catalog', { kind }), false);
  assert.equal(isScopedCatalogWrite('save_project', { kind: 'clients' }), false);
});

test('every protected action reads current authority and mints for the exact request without serializing Bearer', async () => {
  const corporate = session(), context = sso(), payload = Object.freeze({ kind: 'clients', id: subject });
  const before = JSON.stringify(context); let reads = 0, mints = 0;
  const authorizer = createCatalogWorkshopAuthorizer({ reader: { async readWeb(s) { assert.equal(s, corporate); reads++; return workshop(); } },
    async mint(args) { assert.equal(args.payload, payload); assert.equal(args.sessionHash, context.sessionHash); assert.equal(args.submissionId, 'protocol'); mints++; } });
  authorizer.remember(context, corporate);
  for (let i = 0; i < 2; i++) assert.equal(await authorizer.authorize(context, 'protocol', 'save_catalog', payload, 'em.catalogs.manage'), true);
  assert.equal(reads, 2); assert.equal(mints, 2); assert.equal(JSON.stringify(context), before); assert.equal(before.includes(corporate.accessToken), false);
  await assert.rejects(authorizer.authorize({ ...context }, 'protocol', 'save_catalog', payload, 'em.catalogs.manage'), CorporateAuthError);
});

test('missing verification, wrong subject and wrong capability cannot contact workshop authority', async () => {
  const authorizer = createCatalogWorkshopAuthorizer({ reader: { async readWeb() { assert.fail('no network'); } }, async mint() { assert.fail('no permit'); } });
  assert.throws(() => authorizer.remember(sso(), { ...session(), user: { ...session().user, id: 'other' } }), CorporateAuthError);
  await assert.rejects(authorizer.authorize(sso(), 'p', 'save_catalog', { kind: 'clients' }, 'em.catalogs.manage'), CorporateAuthError);
  const context = sso(); authorizer.remember(context, session());
  await assert.rejects(authorizer.authorize(context, 'p', 'save_catalog', { kind: 'types' }, 'em.projects.manage'), CorporateAuthError);
  context.capabilities = [];
  await assert.rejects(authorizer.authorize(context, 'p', 'delete_catalog', { kind: 'types' }, 'em.catalogs.manage'), CorporateAuthError);
  assert.equal(await authorizer.authorize(context, 'p', 'save_catalog', { kind: 'cells' }, 'em.catalogs.manage'), false);
});

test('authority failure and database failure propagate without an unscoped fallback', async () => {
  for (const phase of ['reader', 'mint']) {
    const failure = new WorkshopContextError('WORKSHOP_UNAVAILABLE'), context = sso(); let minted = 0;
    const authorizer = createCatalogWorkshopAuthorizer({ reader: { async readWeb() { if (phase === 'reader') throw failure; return workshop(); } },
      async mint() { minted++; throw failure; } });
    authorizer.remember(context, session());
    await assert.rejects(authorizer.authorize(context, 'p', 'save_catalog', { kind: 'clients' }, 'em.catalogs.manage'), e => e === failure);
    assert.equal(minted, phase === 'mint' ? 1 : 0);
  }
});

test('all template operations use their own capability and fresh office context', async () => {
  const context = sso(); context.capabilities = ['em.form_templates.manage'];
  const corporate = session(); corporate.decision.capabilities = ['em.form_templates.manage'];
  const operations = ['create_form_template', 'save_form_template', 'publish_form_template', 'delete_form_template'];
  let reads = 0; const minted: string[] = [];
  const authorizer = createCatalogWorkshopAuthorizer({ reader: { async readWeb(s) { assert.equal(s, corporate); reads++; return workshop(); } },
    async mint(args) { assert.equal(args.payload.source_form_id, subject); minted.push(args.operation); } });
  authorizer.remember(context, corporate);
  for (const operation of operations) {
    assert.equal(isScopedTemplateWrite(operation), true);
    assert.equal(await authorizer.authorize(context, 'template-protocol', operation, { source_form_id: subject }, 'em.form_templates.manage'), true);
  }
  assert.deepEqual(minted, operations); assert.equal(reads, 4);
  assert.equal(isScopedTemplateWrite('publish_form_template '), false);
  assert.equal(JSON.stringify(context).includes(corporate.accessToken), false);
});

test('catalog capability cannot authorize template operations or fall back to v1', async () => {
  let reads = 0;
  const authorizer = createCatalogWorkshopAuthorizer({ reader: { async readWeb() { reads++; return workshop(); } }, async mint() { assert.fail('no permit'); } });
  const context = sso(); authorizer.remember(context, session());
  for (const operation of ['create_form_template', 'save_form_template', 'publish_form_template', 'delete_form_template']) {
    await assert.rejects(authorizer.authorize(context, 'protocol', operation, {}, 'em.catalogs.manage'), CorporateAuthError);
    await assert.rejects(authorizer.authorize(context, 'protocol', operation, {}, 'em.form_templates.manage'), CorporateAuthError);
  }
  assert.equal(reads, 0);
});

test('project bundles and cell creation and deletion use their exact workshop authority without changing edits', async () => {
  const context = sso();
  context.capabilities = ['em.catalogs.manage', 'em.projects.manage'];
  const corporate = session();
  const minted: Array<{ operation: string; payload: Record<string, unknown> }> = [];
  let reads = 0;
  const authorizer = createCatalogWorkshopAuthorizer({ reader: { async readWeb(s) { assert.equal(s, corporate); reads++; return workshop(); } },
    async mint(args) { minted.push({ operation: args.operation, payload: args.payload }); } });
  authorizer.remember(context, corporate);
  const project = { id: subject, expected_updated_at: null };
  const cell = { ...project, kind: 'cells' };
  await assert.rejects(authorizer.authorize(context, 'wrong', 'save_project_with_equipment', project, 'em.catalogs.manage'), CorporateAuthError);
  assert.equal(await authorizer.authorize(context, 'project-protocol', 'save_project_with_equipment', project, 'em.projects.manage'), true);
  assert.equal(await authorizer.authorize(context, 'edit', 'save_project_with_equipment', { ...project, expected_updated_at: new Date().toISOString() }, 'em.projects.manage'), false);
  assert.equal(await authorizer.authorize(context, 'legacy', 'save_project', project, 'em.projects.manage'), false);
  assert.equal(await authorizer.authorize(context, 'cell-protocol', 'save_catalog', cell, 'em.catalogs.manage'), true);
  const deleteCell = { ...cell, expected_updated_at: new Date().toISOString() };
  assert.equal(await authorizer.authorize(context, 'delete', 'delete_catalog', deleteCell, 'em.catalogs.manage'), true);
  assert.deepEqual(minted, [{ operation: 'save_project_with_equipment', payload: project },
    { operation: 'save_catalog', payload: cell }, { operation: 'delete_catalog', payload: deleteCell }]);
  assert.equal(reads, 3);
});
