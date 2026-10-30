import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createProjectEquipmentData } from '../src/server/web/project-equipment-data';
import { projectEquipmentTextFields, type ProjectEquipmentSnapshot } from '../src/server/web/project-equipment-policy';
import type { CorporateCapability } from '../src/server/web/sso-policy';

const id = (n: number) => `abcdefab-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T15:30:02.123456+00:00', hash = 'b'.repeat(64);
const caps: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
function snapshot(): ProjectEquipmentSnapshot {
  return { project: { id: id(1), numero: 'OS 01', status_pcp: 'em_execu_o', data_real_de_entrega: null,
    equipamento_id: id(2), tipo_equipamento_id: id(3), updated_at: version, closed: false },
    equipment: { id: id(2), projeto_id: id(1), tipo_equipamento_id: id(3), updated_at: '2026-10-30T15:30:02.000001Z',
      ...Object.fromEntries(projectEquipmentTextFields.map(key => [key, null])), placa_motor: null, fp: null, fs: null, numero_cabos: null } as ProjectEquipmentSnapshot['equipment'],
    binding_state: 'linked', can_edit: true, reason: null, context_version: hash, type_mismatch: false };
}
function fixture(data?: unknown, options: { error?: boolean; thrown?: boolean; capabilities?: CorporateCapability[] } = {}) {
  const calls: unknown[][] = [], fromCalls: string[] = [];
  const resultData = arguments.length === 0 ? snapshot() : data;
  const client = { rpc: async (...args: unknown[]) => { calls.push(args); if (options.thrown) throw Error('network private payload');
    return { data: resultData, error: options.error ? { code: 'private', message: 'private SQL details' } : null }; },
    from: (table: string) => { fromCalls.push(table); throw Error('Equipment must not query unrestricted tables'); } } as unknown as SupabaseClient;
  return { ...createProjectEquipmentData(client, options.capabilities ?? caps), calls, fromCalls };
}

test('technical reader scopes a single RPC to the canonical requested project with precise versions', async () => {
  const data = snapshot(); data.project.id = data.project.id.toUpperCase(); data.project.equipamento_id = data.project.equipamento_id!.toUpperCase();
  data.equipment!.id = data.equipment!.id.toUpperCase(); data.equipment!.projeto_id = data.equipment!.projeto_id.toUpperCase();
  const f = fixture(data), result = await f.getProjectEquipment(id(1).toUpperCase());
  assert.ok(result); assert.equal(result.project.id, id(1)); assert.equal(result.equipment!.id, id(2));
  assert.equal(result.project.updated_at, version); assert.equal(result.equipment!.updated_at, '2026-10-30T15:30:02.000001Z');
  assert.deepEqual(f.calls, [['rm_web_project_equipment_snapshot_v1', { p_project_id: id(1) }]]); assert.deepEqual(f.fromCalls, []);
});

test('technical reads retain raw historical strings and never normalize legacy values or type mismatches', async () => {
  const data = snapshot();
  data.equipment!.potencia = '["150 CV", "110 kW"]'; data.equipment!.tensao_estator = ' 220 / 380 V ';
  data.equipment!.descricao = 'x'.repeat(10001); data.equipment!.tipo_tensao = '{"legacy":"CC"}';
  data.equipment!.fp = '-0.123456789012345678901234567890'; data.equipment!.fs = 'NaN'; data.equipment!.numero_cabos = -1;
  data.equipment!.tipo_equipamento_id = id(99); data.type_mismatch = true;
  const f = fixture(data), result = await f.getProjectEquipment(id(1));
  assert.deepEqual(result, data); assert.equal(result!.can_edit, true); assert.equal(result!.equipment!.tipo_equipamento_id, id(99));
  assert.equal(result!.project.tipo_equipamento_id, id(3)); assert.equal(result!.type_mismatch, true);
});

test('technical binding failures have a null equipment body and remain read only without choosing a fallback', async () => {
  for (const binding_state of ['missing', 'unlinked', 'conflicting', 'orphaned', 'shared'] as const) {
    const data = snapshot(); data.binding_state = binding_state; data.equipment = null; data.can_edit = false;
    data.reason = 'O vínculo precisa ser revisado.'; data.type_mismatch = false;
    const f = fixture(data), result = await f.getProjectEquipment(id(1));
    assert.ok(result); assert.equal(result.binding_state, binding_state); assert.equal(result.equipment, null); assert.equal(result.can_edit, false);
    for (const patch of [{ equipment: snapshot().equipment }, { can_edit: true }, { type_mismatch: true }]) {
      await assert.rejects(fixture({ ...data, ...patch }).getProjectEquipment(id(1)), /Não foi possível consultar/);
    }
  }
});

test('closed technical records are readable and never made eligible for editing by capabilities', async () => {
  for (const change of [{ status_pcp: 'cancelado' }, { status_pcp: 'finalizando_para_faturar' }, { data_real_de_entrega: version }]) {
    const data = snapshot(); data.project = { ...data.project, ...change, closed: true }; data.can_edit = false;
    const result = await fixture(data, { capabilities: [...caps, 'em.projects.manage', 'em.engineering.manage'] }).getProjectEquipment(id(1));
    assert.ok(result); assert.equal(result.can_edit, false); assert.ok(result.equipment);
    await assert.rejects(fixture({ ...data, can_edit: true }).getProjectEquipment(id(1)), /Não foi possível consultar/);
  }
  const readOnlyUser = await fixture(snapshot(), { capabilities: caps }).getProjectEquipment(id(1));
  assert.equal(readOnlyUser!.can_edit, true, 'DTO eligibility describes the record, not user authorization');
});

test('technical reader rejects malformed, cross-project or inconsistent snapshots rather than leaking a partial body', async () => {
  const cases: unknown[] = [undefined, [], {}, { ...snapshot(), context_version: 'invalid' }, { ...snapshot(), private_audit: 'private' }];
  for (const change of [
    { id: id(99) }, { id: 'invalid' }, { equipamento_id: id(99) }, { updated_at: 'invalid' },
    { closed: true }, { data_real_de_entrega: '2026-10-30T15:30:00' },
  ]) { const data = snapshot(); data.project = { ...data.project, ...change }; cases.push(data); }
  for (const change of [
    { id: id(99) }, { projeto_id: id(99) }, { id: 'invalid' }, { updated_at: 'invalid' },
    { tipo_equipamento_id: id(99) }, { potencia: ['10', '20'] }, { fp: 0.5 }, { numero_cabos: 2.5 }, { actor_auth_user_id: id(99) },
  ]) { const data = snapshot(); data.equipment = { ...data.equipment!, ...change } as ProjectEquipmentSnapshot['equipment']; cases.push(data); }
  cases.push({ ...snapshot(), equipment: null }, { ...snapshot(), can_edit: false }, { ...snapshot(), type_mismatch: true });
  for (const data of cases) await assert.rejects(fixture(data).getProjectEquipment(id(1)), /Não foi possível consultar/);
});

test('technical reader denies missing scopes before database access and distinguishes missing from unavailable', async () => {
  for (const capabilities of [[], ['em.portal.read'], ['em.projects.read'], ['em.projects.manage', 'em.engineering.manage']] as CorporateCapability[][]) {
    const f = fixture(snapshot(), { capabilities });
    await assert.rejects(f.getProjectEquipment(id(1)), /Acesso não autorizado/); assert.deepEqual(f.calls, []);
  }
  const invalid = fixture(); assert.equal(await invalid.getProjectEquipment('invalid'), null); assert.deepEqual(invalid.calls, []);
  const missing = fixture(null); assert.equal(await missing.getProjectEquipment(id(1)), null); assert.equal(missing.calls.length, 1);
  for (const options of [{ error: true }, { thrown: true }]) {
    const f = fixture(snapshot(), options);
    await assert.rejects(f.getProjectEquipment(id(1)), error => error instanceof Error && /Não foi possível consultar/.test(error.message) && !/private/.test(error.message));
    assert.equal(f.calls.length, 1); assert.deepEqual(f.fromCalls, []);
  }
});
