import test from 'node:test';
import assert from 'node:assert/strict';
import type { ProjectEquipmentSnapshot } from '../src/server/web/project-equipment-policy';
import { equipmentFieldGroups, projectEquipmentChanges, projectEquipmentDraft, projectEquipmentMatches, projectEquipmentRequest } from '../src/components/web/project-equipment-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T14:02:10.123456+00:00';
function snapshot(): ProjectEquipmentSnapshot {
  const texts = Object.fromEntries(equipmentFieldGroups.flatMap(group => group.fields.map(field => [field.key, null])));
  return { project: { id: id(1), numero: 'EM-031', status_pcp: 'peritagem', data_real_de_entrega: null, equipamento_id: id(2), tipo_equipamento_id: id(3), updated_at: version, closed: false },
    equipment: { ...texts, id: id(2), projeto_id: id(1), tipo_equipamento_id: id(4), updated_at: version, fabricante: '  Fabricante legado  ', descricao: 'Motor\ncom descrição livre', potencia: '10/20 HP (placa)', placa_motor: 'c___placa',
      fp: '0.12345678901234567890', fs: '1.00000000000000000001', numero_cabos: 6 } as ProjectEquipmentSnapshot['equipment'],
    binding_state: 'linked', can_edit: true, reason: null, context_version: 'a'.repeat(64), type_mismatch: true };
}

test('equipment editor sends only dirty fields and preserves exact legacy text, foreign keys and decimal precision', () => {
  const source = snapshot(), draft = projectEquipmentDraft(source); draft.modelo = '  Novo modelo / 440 V  ';
  const request = projectEquipmentRequest(source, draft, id(5)); draft.modelo = 'another value';
  assert.deepEqual(request.changes, { modelo: '  Novo modelo / 440 V  ' });
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_equipment_updated_at, version);
  assert.equal(request.expected_context_version, source.context_version); assert.equal(request.equipamento_id, id(2)); assert.equal(request.confirm_change, true);
  assert.equal(Object.isFrozen(request), true); assert.equal(Object.isFrozen(request.changes), true);
  assert.deepEqual(Object.keys(request).sort(), ['submissionId', 'projeto_id', 'equipamento_id', 'expected_project_updated_at', 'expected_equipment_updated_at', 'expected_context_version', 'confirm_change', 'changes'].sort());
  assert.equal(source.equipment?.fabricante, '  Fabricante legado  '); assert.equal(source.equipment?.fp, '0.12345678901234567890');
});

test('decimal edits retain strings and support comma only in the changed field without float coercion', () => {
  const source = snapshot(), draft = projectEquipmentDraft(source);
  draft.fp = '-123456789012345678901234567890,12345678901234567890'; draft.fs = '+1.00000000000000000001';
  assert.deepEqual(projectEquipmentChanges(source, draft), { fp: '-123456789012345678901234567890.12345678901234567890' });
  for (const invalid of ['1e3', '1.234,56', 'NaN', 'Infinity', '.5', '1.', '1'.repeat(31), '1.' + '1'.repeat(21)]) {
    assert.throws(() => projectEquipmentChanges(source, { ...draft, fp: invalid }), /decimal sem separador/);
  }
  assert.deepEqual(projectEquipmentChanges(source, { ...projectEquipmentDraft(source), fp: '', fs: '' }), { fp: null, fs: null });
});

test('unchanged historical outliers remain consultable and never enter another field patch', () => {
  const source = snapshot(); Object.assign(source.equipment!, { descricao: 'x'.repeat(12_000), fp: '1234567890123456789012345678901234567890', fs: 'NaN', fabricante: '  original  ' });
  const draft = projectEquipmentDraft(source); draft.numero_serie = 'EM-2026';
  assert.deepEqual(projectEquipmentChanges(source, draft), { numero_serie: 'EM-2026' });
  assert.throws(() => projectEquipmentChanges(source, { ...draft, descricao: 'y'.repeat(10_001) }), /10.000/);
  assert.throws(() => projectEquipmentChanges(source, { ...draft, fabricante: 'bad\u0000text' }), /10.000/);
});

test('optional clear, free electrical text and bounded cable integers remain distinct', () => {
  const source = snapshot(), draft = projectEquipmentDraft(source); draft.fabricante = ''; draft.potencia = '15 kW / 20 HP'; draft.tipo_tensao = 'Conforme placa'; draft.numero_cabos = '2147483647';
  assert.deepEqual(projectEquipmentChanges(source, draft), { fabricante: null, potencia: '15 kW / 20 HP', tipo_tensao: 'Conforme placa', numero_cabos: 2147483647 });
  for (const invalid of ['2147483648', '-1', '1.5', '1e2', 'NaN']) assert.throws(() => projectEquipmentChanges(source, { ...draft, numero_cabos: invalid }), /inteiro/);
  assert.equal(projectEquipmentChanges(source, { ...projectEquipmentDraft(source), numero_cabos: '0' }).numero_cabos, 0);
  assert.equal(projectEquipmentChanges(source, { ...projectEquipmentDraft(source), placa_motor: 's___placa' }).placa_motor, 's___placa');
  assert.throws(() => projectEquipmentChanges(source, { ...draft, placa_motor: 'AC' }), /placa/);
});

test('no-op or unresolved equipment ownership never builds a command, even with a synthetic editable flag', () => {
  const source = snapshot(), draft = projectEquipmentDraft(source); assert.deepEqual(projectEquipmentChanges(source, draft), {});
  assert.throws(() => projectEquipmentRequest(source, draft, id(5)), /Altere um dado/);
  draft.modelo = 'Atualizado';
  for (const state of ['missing', 'unlinked', 'conflicting', 'orphaned', 'shared'] as const) assert.throws(() => projectEquipmentRequest({ ...source, binding_state: state }, draft, id(5)), /vínculo/);
  for (const blocked of [{ ...source, can_edit: false }, { ...source, equipment: null }, { ...source, project: { ...source.project, closed: true } },
    { ...source, equipment: { ...source.equipment!, projeto_id: id(9) } }, { ...source, project: { ...source.project, equipamento_id: id(9) } }]) assert.throws(() => projectEquipmentRequest(blocked, draft, id(5)), /vínculo/);
});

test('the editor compares the entire SSR project context before permitting a technical update', () => {
  const source = snapshot(); assert.equal(projectEquipmentMatches(source, source.project), true);
  for (const patch of [{ id: id(9) }, { updated_at: version + '0' }, { equipamento_id: id(9) }, { tipo_equipamento_id: id(9) }, { status_pcp: 'cancelado' }, { data_real_de_entrega: version }]) assert.equal(projectEquipmentMatches(source, { ...source.project, ...patch }), false);
});
