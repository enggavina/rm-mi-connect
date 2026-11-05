import test from 'node:test';
import assert from 'node:assert/strict';
import { canChangeProjectEquipmentType, canUseProjectEquipmentBundle, projectEquipmentType } from '../src/components/web/project-equipment-type-model';
import type { ProjectEquipmentSnapshot } from '../src/server/web/project-equipment-policy';

const snapshot = (overrides: Record<string, unknown> = {}) => ({ project: { tipo_equipamento_id: 'legacy', closed: false },
  equipment: { tipo_equipamento_id: 'canonical' }, binding_state: 'linked', ...overrides } as unknown as ProjectEquipmentSnapshot);

test('equipment classification is canonical even when legacy project classification disagrees', () => {
  assert.equal(projectEquipmentType(snapshot()), 'canonical');
  assert.equal(projectEquipmentType(snapshot({ equipment: { tipo_equipamento_id: null } })), '');
  assert.equal(projectEquipmentType(snapshot({ equipment: null, binding_state: 'missing' })), 'legacy');
  assert.equal(projectEquipmentType(snapshot({ equipment: null, binding_state: 'shared' })), '');
});

test('legacy projects missing equipment preserve project-only edits when they already have operational work', () => {
  assert.equal(canUseProjectEquipmentBundle(snapshot({ binding_state: 'missing', equipment: null, has_project_route: true, can_change_type: false }), true), false);
  assert.equal(canUseProjectEquipmentBundle(snapshot({ binding_state: 'missing', equipment: null, can_change_type: true }), false), true);
  assert.equal(canUseProjectEquipmentBundle(snapshot({ has_project_route: true, can_change_type: false }), true), true);
  assert.equal(canUseProjectEquipmentBundle(snapshot({ binding_state: 'shared' }), false), false);
  assert.equal(canUseProjectEquipmentBundle(null, false), false);
});

test('initialized empty routes and existing operational evidence preserve classification', () => {
  assert.equal(canChangeProjectEquipmentType(snapshot({ has_project_route: true }), false), false);
  assert.equal(canChangeProjectEquipmentType(snapshot({ can_change_type: false }), false), false);
  assert.equal(canChangeProjectEquipmentType(snapshot(), true), false);
  assert.equal(canChangeProjectEquipmentType(snapshot({ can_change_type: true }), true), false);
  assert.equal(canChangeProjectEquipmentType(snapshot({ can_change_type: true }), false), true);
  assert.equal(canChangeProjectEquipmentType(snapshot({ project: { closed: true }, can_change_type: true }), false), false);
  assert.equal(canChangeProjectEquipmentType(snapshot({ binding_state: 'shared', can_change_type: true }), false), false);
  assert.equal(canChangeProjectEquipmentType(null, false), false);
});
