import type { ProjectEquipmentSnapshot } from '@/server/web/project-equipment-policy';

/** Equipment owns classification; a missing legacy equipment can be completed explicitly. */
export function projectEquipmentType(snapshot?: ProjectEquipmentSnapshot | null): string {
  if (!snapshot) return '';
  if (snapshot.equipment) return snapshot.equipment.tipo_equipamento_id ?? '';
  return snapshot.binding_state === 'missing' ? snapshot.project.tipo_equipamento_id ?? '' : '';
}

export function canChangeProjectEquipmentType(snapshot: ProjectEquipmentSnapshot | null | undefined, hasAllocations: boolean): boolean {
  if (!snapshot || snapshot.project.closed || hasAllocations || !['linked', 'missing'].includes(snapshot.binding_state)) return false;
  // The server evaluates all operational evidence, including a previously initialized empty route.
  return snapshot.can_change_type ?? (!hasAllocations && !snapshot.has_project_route);
}

/** Legacy projects with work but no equipment remain editable without creating a new binding. */
export function canUseProjectEquipmentBundle(snapshot: ProjectEquipmentSnapshot | null | undefined, hasAllocations: boolean): boolean {
  return !!snapshot && !snapshot.project.closed && (snapshot.binding_state === 'linked'
    || snapshot.binding_state === 'missing' && canChangeProjectEquipmentType(snapshot, hasAllocations));
}
