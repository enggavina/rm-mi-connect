import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from './sso-policy';
import { uuid } from './policy';
import { projectEquipmentSnapshotSchema, type ProjectEquipmentSnapshot } from './project-equipment-policy';

const scopes: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
const unavailable = () => new Error('Não foi possível consultar os dados técnicos do equipamento. Tente novamente.');
export function createProjectEquipmentData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectEquipment(projectId: string): Promise<ProjectEquipmentSnapshot | null> {
    if (capabilities !== undefined && !scopes.every(capability => capabilities.includes(capability))) throw new Error('Acesso não autorizado aos dados técnicos.');
    if (!uuid.safeParse(projectId).success) return null;
    projectId = projectId.toLowerCase();
    let result;
    try { result = await client.rpc('rm_web_project_equipment_snapshot_v1', { p_project_id: projectId }); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = projectEquipmentSnapshotSchema.safeParse(result.data); if (!parsed.success) throw unavailable();
    const data = parsed.data, closed = data.project.data_real_de_entrega !== null || ['cancelado', 'finalizando_para_faturar'].includes(data.project.status_pcp ?? '');
    if (data.project.id !== projectId || data.project.closed !== closed
      || data.binding_state === 'linked' && (!data.equipment || data.equipment.id !== data.project.equipamento_id || data.equipment.projeto_id !== projectId)
      || data.binding_state !== 'linked' && (data.equipment !== null || data.can_edit)
      || data.can_edit !== (data.binding_state === 'linked' && !closed)
      || data.equipment !== null && data.type_mismatch !== (data.equipment.tipo_equipamento_id !== data.project.tipo_equipamento_id)
      || data.binding_state !== 'linked' && data.type_mismatch) throw unavailable();
    return data;
  }
  return { getProjectEquipment };
}
export async function getProjectEquipment(projectId: string) {
  const { requireWebUser } = await import('./auth'); const access = await requireWebUser(scopes);
  return createProjectEquipmentData(access.client, access.sso?.capabilities).getProjectEquipment(projectId);
}
