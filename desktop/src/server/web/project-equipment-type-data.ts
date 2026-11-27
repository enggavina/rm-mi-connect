import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import type { WebRow } from './data';
import type { CorporateCapability } from './sso-policy';
import type { ProjectEquipmentSnapshot } from './project-equipment-policy';
import { uuid } from './policy';
import { readWorkshopOperations } from './workshop-operation-reader';
import type { WorkshopRead } from './workshop-read-policy';
import { linkedEquipmentTypeId } from '@/components/web/project-equipment-type-display';

const scopes: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
const typeSchema = z.object({ id: uuid, nome: z.string().nullable(), sigla: z.string().nullable() }).strict();
const unavailable = () => new Error('Não foi possível consultar o tipo de equipamento. Tente novamente.');

export function createProjectEquipmentTypeData(client: SupabaseClient, capabilities?: readonly CorporateCapability[], read?: WorkshopRead) {
  async function getProjectEquipmentType(project: WebRow, snapshot: ProjectEquipmentSnapshot | null): Promise<WebRow | null> {
    if (capabilities !== undefined && !scopes.every(scope => capabilities.includes(scope))) throw new Error('Acesso não autorizado aos dados do equipamento.');
    const typeId = linkedEquipmentTypeId(project, snapshot);
    if (!typeId || !uuid.safeParse(project.id).success || !uuid.safeParse(typeId).success) return null;
    const value = read ? await read('project_equipment_type', { project: project.id, equipment: project.equipamento_id, type: typeId })
      : await readLegacyType(typeId);
    if (value === null) return null;
    const parsed = typeSchema.safeParse(value);
    if (!parsed.success || parsed.data.id !== typeId) throw unavailable();
    return parsed.data;
  }
  async function readLegacyType(id: string) {
    try {
      const { data, error } = await client.from('rm_tipos_equipamento').select('id,nome,sigla').eq('id', id).maybeSingle();
      if (!error) return data;
    } catch { /* A transport or PostgREST error leaves the type unavailable. */ }
    throw unavailable();
  }
  return { getProjectEquipmentType };
}

export async function getProjectEquipmentType(project: WebRow, snapshot: ProjectEquipmentSnapshot | null) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(scopes);
  return createProjectEquipmentTypeData(access.client, access.sso?.capabilities, await readWorkshopOperations(access)).getProjectEquipmentType(project, snapshot);
}
