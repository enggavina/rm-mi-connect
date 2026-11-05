import { projectEquipmentDisplay, type WebRow } from '@/server/web/data';
import type { ProjectEquipmentSnapshot } from '@/server/web/project-equipment-policy';
import { projectEquipmentMatches } from './project-equipment-model';

/** The separate equipment snapshot may be stale or ambiguous; keep the legacy value unless it is a verified match. */
export function projectEquipmentDisplayFromSnapshot(project: WebRow, snapshot: ProjectEquipmentSnapshot | null): string | null {
  if (!snapshot || snapshot.binding_state !== 'linked' || !snapshot.equipment || !projectEquipmentMatches(snapshot, {
    id: project.id, updated_at: project.updated_at, equipamento_id: project.equipamento_id,
    tipo_equipamento_id: project.tipo_equipamento_id, status_pcp: project.status_pcp, data_real_de_entrega: project.data_real_de_entrega,
  })) return projectEquipmentDisplay(project);
  return projectEquipmentDisplay(project, snapshot.equipment);
}
