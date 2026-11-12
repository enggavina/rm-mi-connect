import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import type { WebRow } from './data';
import type { CorporateCapability } from './sso-policy';
import type { ProjectEquipmentSnapshot } from './project-equipment-policy';
import { uuid } from './policy';
import { linkedEquipmentTypeId } from '@/components/web/project-equipment-type-display';

const scopes: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
const typeSchema = z.object({ id: uuid, nome: z.string().nullable(), sigla: z.string().nullable() }).strict();
const unavailable = () => new Error('Não foi possível consultar o tipo de equipamento. Tente novamente.');

export function createProjectEquipmentTypeData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectEquipmentType(project: WebRow, snapshot: ProjectEquipmentSnapshot | null): Promise<WebRow | null> {
    if (capabilities !== undefined && !scopes.every(scope => capabilities.includes(scope))) throw new Error('Acesso não autorizado aos dados do equipamento.');
    const typeId = linkedEquipmentTypeId(project, snapshot);
    if (!typeId || !uuid.safeParse(project.id).success || !uuid.safeParse(typeId).success) return null;
    let result;
    try { result = await client.from('rm_tipos_equipamento').select('id,nome,sigla').eq('id', typeId).maybeSingle(); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = typeSchema.safeParse(result.data);
    if (!parsed.success || parsed.data.id !== typeId) throw unavailable();
    return parsed.data;
  }
  return { getProjectEquipmentType };
}

export async function getProjectEquipmentType(project: WebRow, snapshot: ProjectEquipmentSnapshot | null) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(scopes);
  return createProjectEquipmentTypeData(access.client, access.sso?.capabilities).getProjectEquipmentType(project, snapshot);
}
