import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { workshopAdoptionPlan } from '../src/server/bridge/workshop-adoption';

const declaration = () => JSON.parse(readFileSync(new URL('../../rm-mobile-supabase/workshops/adoption.json', import.meta.url), 'utf8'));
const denied = { schema_usage: false, select: false, insert: false, update: false, delete: false };
function metadata() { return { format_version: 1, source: 'postgresql_catalog', captured_at: '2026-11-17T12:00:00Z',
  tables: ['public.rm_projetos', 'public.rm_celulas', 'public.rm_clientes', 'rm_private.sso_sessions', 'storage.objects'].map(name => ({ name, columns: ['id'],
    rls_enabled: true, rls_forced: false, access: { anon: denied, authenticated: denied, service_role: denied }, foreign_keys: [], policies: [] })), routines: [] }; }

test('explicit user declaration keeps BMA as legacy source and BRJ/BBH distinct without invented central IDs', () => {
  const input = metadata(), before = JSON.stringify(input), plan = workshopAdoptionPlan(input, declaration());
  assert.equal(plan.legacy_workshop_code, 'BMA');
  assert.deepEqual(plan.workshops.map(w => [w.code, w.central_id]), [['BMA', null], ['BRJ', null], ['BBH', null]]);
  assert.ok(plan.workshops.slice(1).every(w => w.proposed_availability === 'blocked_until_isolation'));
  assert.equal(plan.central_registration_verified, false); assert.equal(plan.activation_ready, false); assert.equal(plan.isolation_proven, false);
  assert.equal(JSON.stringify(input), before);
});

test('all inventory objects remain visible and only confirmed roots get an ownership declaration', () => {
  const plan = workshopAdoptionPlan(metadata(), declaration());
  assert.equal(plan.tables.length, 5);
  assert.deepEqual(plan.tables.filter(t => t.legacy_root_owner_code === 'BMA').map(t => t.name), ['public.rm_celulas', 'public.rm_projetos']);
  for (const t of plan.tables) assert.equal(t.migration_rule, 'pending_review');
  for (const name of ['storage.objects', 'rm_private.sso_sessions', 'public.rm_clientes']) {
    assert.equal(plan.tables.find(t => t.name === name)!.legacy_root_owner_code, null);
  }
  assert.deepEqual(plan.constraints, { login_workshop_selector: false, mobile_sso: false, implicit_principal_grants: false,
    reassign_offline_queue: false, execute_sql: false, production_data_modified: false });
});

test('declaration refuses unrelated projects, implicit grants, duplicate offices and absent legacy origin', () => {
  for (const patch of [{ operational_project_ref: 'another-app' }, { authority_project_ref: 'another-authority' }, { default_workshop: 'BMA' },
    { legacy_workshop_code: 'UNKNOWN' }, { workshops: [declaration().workshops[0], declaration().workshops[0]] },
    { workshops: [{ ...declaration().workshops[0], users: ['anybody'] }] }, { confirmation: { ...declaration().confirmation, source: 'inferred_from_email' } }]) {
    assert.throws(() => workshopAdoptionPlan(metadata(), { ...declaration(), ...patch }));
  }
});

test('missing root and malformed inventories never produce a migration-ready declaration', () => {
  const source = metadata(); source.tables = source.tables.filter(t => t.name !== 'public.rm_projetos');
  assert.throws(() => workshopAdoptionPlan(source, declaration()));
  assert.throws(() => workshopAdoptionPlan({}, declaration()));
});

test('preparation CLI writes only a new review artifact, refuses overwrite and preserves input files', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'em-adoption-'));
  try {
    const source = path.join(dir, 'metadata.json'), approved = path.join(dir, 'adoption.json'), target = path.join(dir, 'plan.json');
    const original = JSON.stringify(metadata()); writeFileSync(source, original); writeFileSync(approved, JSON.stringify(declaration()));
    const command = (output: string) => spawnSync(process.execPath, [path.resolve('node_modules/tsx/dist/cli.mjs'),
      path.resolve('../rm-mobile-supabase/scripts/prepare_workshop_adoption.ts'), source, approved, output], { encoding: 'utf8' });
    assert.equal(command(target).status, 0); const result = readFileSync(target, 'utf8');
    assert.equal(JSON.parse(result).activation_ready, false); assert.equal(command(target).status, 1);
    assert.equal(readFileSync(target, 'utf8'), result); assert.equal(command(source).status, 1); assert.equal(readFileSync(source, 'utf8'), original);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
