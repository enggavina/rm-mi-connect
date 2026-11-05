import test from 'node:test';
import assert from 'node:assert/strict';
import { projectEquipmentDisplayFromSnapshot } from '../src/components/web/project-equipment-display';
import type { ProjectEquipmentSnapshot } from '../src/server/web/project-equipment-policy';

const project = { id: 'project', updated_at: 'v1', equipamento_id: 'equipment', tipo_equipamento_id: null, status_pcp: null, data_real_de_entrega: null, descricao_equipamento: null };
const snapshot = { project: { ...project }, equipment: { id: 'equipment', projeto_id: 'project', descricao: 'Motor' }, binding_state: 'linked' } as unknown as ProjectEquipmentSnapshot;

test('project detail uses only a current, unambiguous bidirectional snapshot and preserves legacy text', () => {
  assert.equal(projectEquipmentDisplayFromSnapshot(project, snapshot), 'Motor');
  assert.equal(projectEquipmentDisplayFromSnapshot({ ...project, descricao_equipamento: 'Legado' }, snapshot), 'Legado');
  assert.equal(projectEquipmentDisplayFromSnapshot(project, null), null);
  assert.equal(projectEquipmentDisplayFromSnapshot({ ...project, updated_at: 'v2' }, snapshot), null);
  assert.equal(projectEquipmentDisplayFromSnapshot(project, { ...snapshot, binding_state: 'shared' }), null);
  assert.equal(projectEquipmentDisplayFromSnapshot(project, { ...snapshot, equipment: { ...snapshot.equipment!, projeto_id: 'other' } }), null);
  assert.equal(projectEquipmentDisplayFromSnapshot(project, { ...snapshot, equipment: { ...snapshot.equipment!, id: 'other' } }), null);
});
