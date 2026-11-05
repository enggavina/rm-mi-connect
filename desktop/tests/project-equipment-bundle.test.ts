import test from 'node:test';
import assert from 'node:assert/strict';
import { saveProjectSchema, saveProjectWithEquipmentSchema } from '../src/server/web/policy';

const project = '5fe36000-0000-4000-8000-000000000001';
const equipment = '6fe36000-0000-4000-8000-000000000001';
const submission = 'afe36000-0000-4000-8000-000000000001';
const initial = { submissionId: submission, id: project, expected_updated_at: null,
  changes: { nome: 'Projeto' }, equipment: { id: equipment, expected_updated_at: null, expected_context_version: null,
    changes: { descricao: 'Motor', fabricante: 'Fabricante', potencia: '55 kW', placa_motor: 'c___placa' } } };

test('project/equipment bundle classifies equipment by ID and never duplicates classification in project changes', () => {
  assert.equal(saveProjectWithEquipmentSchema.safeParse(initial).success, true);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...initial, changes: { ...initial.changes, descricao_equipamento: 'Duplicado' } }).success, false);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...initial, changes: { ...initial.changes, tipo_equipamento_id: project } }).success, false);
  assert.equal(saveProjectSchema.safeParse({ submissionId: submission, id: project, expected_updated_at: null, changes: { tipo_equipamento_id: equipment } }).success, true);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...initial, equipment: { ...initial.equipment, tipo_equipamento_id: project } }).success, true);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...initial, equipment: { ...initial.equipment, tipo_equipamento_id: 'Motor' } }).success, false);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...initial, equipment: { ...initial.equipment, changes: { tipo_equipamento_id: project } } }).success, false);
});

test('project-only and equipment-only edits preserve omitted fields and reject unknown equipment', () => {
  const current = { ...initial, expected_updated_at: '2026-11-05T14:00:00Z',
    equipment: { ...initial.equipment, expected_updated_at: '2026-11-05T14:00:00Z', expected_context_version: 'a'.repeat(64) } };
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...current, changes: {} }).success, true);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...current, equipment: { ...current.equipment, changes: {} } }).success, true);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...current, equipment: { ...current.equipment, changes: { descricao_equipamento: 'forbidden' } } }).success, false);
  assert.equal(saveProjectWithEquipmentSchema.safeParse({ ...current, equipment: { ...current.equipment, changes: { potencia: ['55'] } } }).success, false);
});
