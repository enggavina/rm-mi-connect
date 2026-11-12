import type { WebRow } from '@/server/web/data';
import type { ProjectEquipmentSnapshot } from '@/server/web/project-equipment-policy';
import { projectEquipmentMatches } from './project-equipment-model';
import { equipmentTypeLabel } from './engineering-model';

/** Reading a type never falls back to the legacy classification on the project. */
export function linkedEquipmentTypeId(project: WebRow, snapshot: ProjectEquipmentSnapshot | null): string | null {
  if (!snapshot || snapshot.binding_state !== 'linked' || !snapshot.equipment || !projectEquipmentMatches(snapshot, {
    id: project.id, updated_at: project.updated_at, equipamento_id: project.equipamento_id,
    tipo_equipamento_id: project.tipo_equipamento_id, status_pcp: project.status_pcp, data_real_de_entrega: project.data_real_de_entrega,
  }) || snapshot.equipment.id !== project.equipamento_id || snapshot.equipment.projeto_id !== project.id) return null;
  return snapshot.equipment.tipo_equipamento_id || null;
}

export function projectEquipmentTypeDisplay(project: WebRow, snapshot: ProjectEquipmentSnapshot | null, type: WebRow | null): string {
  const typeId = linkedEquipmentTypeId(project, snapshot);
  return typeId && type?.id === typeId ? equipmentTypeLabel(type) : 'Não informado';
}
