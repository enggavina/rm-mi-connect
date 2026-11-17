import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { workshopScopeInventory } from '../src/server/bridge/workshop-inventory';

const table = (name: string, columns = ['id']) => ({ name, columns, rls_enabled: true, rls_forced: false,
  access: { anon: { schema_usage: false, select: false, insert: false, update: false, delete: false },
    authenticated: { schema_usage: true, select: true, insert: false, update: false, delete: false },
    service_role: { schema_usage: true, select: true, insert: true, update: true, delete: true } },
  foreign_keys: [] as { name: string; columns: string[]; target: string; target_columns: string[] }[],
  policies: [{ name: 'read', command: 'r', permissive: true, roles: ['authenticated'] }] });
const fk = (target: string, column = 'projeto_id') => ({ name: `fk_${column}`, columns: [column], target, target_columns: ['id'] });
function snapshot() {
  const projects = table('public.rm_projetos'), cells = table('public.rm_celulas');
  const records = table('public.rm_registros_formulario', ['id','projeto_id']); records.foreign_keys.push(fk(projects.name));
  const answers = table('public.rm_respostas', ['id','registro_id']); answers.foreign_keys.push(fk(records.name, 'registro_id'));
  return { format_version: 1, source: 'postgresql_catalog', captured_at: '2026-11-17T12:00:00+00:00',
    tables: [projects,cells,records,answers,table('rm_private.sso_sessions'),table('storage.objects')],
    routines: [{ name: 'public.rm_test_v1', signature: 'p_id uuid', security_definer: true,
      anon_execute: false, authenticated_execute: true, service_role_execute: true }] };
}

test('inventory preserves direct and indirect FK paths without assigning ownership or proving isolation', () => {
  const input = snapshot(), before = JSON.stringify(input), report = workshopScopeInventory(input);
  const answer = report.tables.find(t => t.name === 'public.rm_respostas')!;
  assert.deepEqual(answer.project_reference_path?.map(step => step.target), ['public.rm_registros_formulario','public.rm_projetos']);
  assert.equal(answer.cell_reference_path, null);
  assert.deepEqual(report.tables.find(t => t.name === 'public.rm_projetos')!.project_reference_path, []);
  assert.equal(report.tables.find(t => t.name === 'storage.objects')!.project_reference_path, null);
  assert.equal(report.isolation_proven, false); assert.ok(report.tables.every(t => t.review_status === 'pending'));
  assert.deepEqual(report.totals, { tables: 6, foreign_keys: 2, tables_with_scope_column: 0, tables_without_rls: 0, routines: 1, security_definer_routines: 1 });
  assert.equal(JSON.stringify(input), before);
});

test('cycles terminate, all FKs remain available and scope columns/RLS do not certify isolation', () => {
  const input = snapshot(), projects = input.tables[0], records = input.tables[2];
  projects.columns.push('record_id', 'workshop_id'); projects.foreign_keys.push(fk(records.name, 'record_id'));
  input.tables[4].rls_enabled = false;
  const report = workshopScopeInventory(input);
  assert.equal(report.totals.tables_with_scope_column, 1); assert.equal(report.totals.tables_without_rls, 1);
  assert.equal(report.isolation_proven, false);
  assert.equal(report.tables.find(t => t.name === records.name)!.foreign_keys.length, 1);
  assert.equal(report.tables.find(t => t.name === records.name)!.project_reference_path?.length, 1);
});

test('inventory refuses absent EM targets, mismatched FK columns, duplicates and unrelated tables', () => {
  const mutate = [
    (s: ReturnType<typeof snapshot>) => { s.tables.splice(0,1); },
    (s: ReturnType<typeof snapshot>) => { s.tables.push(s.tables[0]); },
    (s: ReturnType<typeof snapshot>) => { s.tables[2].foreign_keys[0].columns = ['not_present']; },
    (s: ReturnType<typeof snapshot>) => { s.tables[2].foreign_keys[0].target_columns = ['missing']; },
    (s: ReturnType<typeof snapshot>) => { s.tables[2].foreign_keys[0].target_columns.push('id'); },
    (s: ReturnType<typeof snapshot>) => { s.tables.push(table('public.unrelated_system')); },
    (s: ReturnType<typeof snapshot>) => { s.routines.push(s.routines[0]); },
    (s: ReturnType<typeof snapshot>) => { s.routines[0].name = 'public.unrelated'; },
  ];
  for (const change of mutate) { const input = snapshot(); change(input); assert.throws(() => workshopScopeInventory(input)); }
});

test('metadata with business content, secret fields, invalid booleans or unknown versions is refused', () => {
  const input = snapshot();
  for (const value of [{ ...input, rows: [{ password: 'must-not-enter-report' }] }, { ...input, format_version: 2 },
    { ...input, tables: [{ ...input.tables[0], credentials: 'never' }] },
    { ...input, tables: [{ ...input.tables[0], rls_enabled: 'true' }] }, { ...input, tables: [] },
    { ...input, routines: [{ ...input.routines[0], body: 'private source' }] }]) {
    assert.throws(() => workshopScopeInventory(value), /inválido ou incompleto/);
  }
});

test('external Auth FK metadata is retained without importing identity records', () => {
  const input = snapshot(), identity = table('public.rm_users', ['id','auth_user_id']);
  identity.foreign_keys.push(fk('auth.users','auth_user_id')); input.tables.push(identity);
  const user = workshopScopeInventory(input).tables.find(t => t.name === identity.name)!;
  assert.equal(user.foreign_keys[0].target, 'auth.users'); assert.equal(user.project_reference_path, null);
  assert.equal(user.review_status, 'pending');
});

test('quoted PostgreSQL catalog names remain metadata without becoming SQL', () => {
  const input = snapshot(), objects = input.tables.find(t => t.name === 'storage.objects')!;
  input.tables.push(table('storage.buckets')); objects.columns.push('bucket_id');
  objects.foreign_keys.push({ ...fk('storage.buckets','bucket_id'), name: 'objects_bucketId_fkey' });
  objects.policies[0].name = 'Read stored objects';
  assert.equal(workshopScopeInventory(input).tables.find(t => t.name === objects.name)!.foreign_keys[0].name,'objects_bucketId_fkey');
});

test('inventory CLI creates a metadata report and refuses to replace any existing file', () => {
  const dir = mkdtempSync(path.join(tmpdir(),'em-workshop-inventory-'));
  try {
    const input = path.join(dir,'source.json'), output = path.join(dir,'report.json');
    writeFileSync(input, '\uFEFF'+JSON.stringify(snapshot()));
    const args = [path.resolve('node_modules/tsx/dist/cli.mjs'),path.resolve('../rm-mobile-supabase/scripts/prepare_workshop_inventory.ts'),input,output];
    const invoke = () => spawnSync(process.execPath,args,{ encoding:'utf8',timeout:30_000 });
    const first = invoke(); assert.equal(first.status,0,first.stderr);
    assert.equal(JSON.parse(readFileSync(output,'utf8')).isolation_proven,false);
    const previous = readFileSync(output,'utf8'); const second = invoke(); assert.equal(second.status,1);
    assert.equal(readFileSync(output,'utf8'),previous); assert.ok(!second.stderr.includes('must-not-enter-report'));
    args[args.length-1] = input; const sameFile = invoke(); assert.equal(sameFile.status,1);
    assert.ok(readFileSync(input,'utf8').startsWith('\uFEFF'));
  } finally {
    assert.ok(path.resolve(dir).startsWith(path.resolve(tmpdir()) + path.sep));
    assert.match(path.basename(dir), /^em-workshop-inventory-[a-zA-Z0-9]+$/);
    rmSync(dir,{recursive:true,force:true});
  }
});
