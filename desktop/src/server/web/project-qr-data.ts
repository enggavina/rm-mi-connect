import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from './sso-policy';
import { projectQrIdSchema, projectQrSchema, type ProjectQrProject } from './project-qr-policy';

export const projectQrScopes: CorporateCapability[] = ['em.portal.read', 'em.projects.read'];
const unavailable = () => new Error('Não foi possível consultar a identificação deste projeto. Recarregue a página para tentar novamente.');
export function createProjectQrData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getProjectQr(projectId: string): Promise<ProjectQrProject | null> {
    if (capabilities !== undefined && !projectQrScopes.every(capability => capabilities.includes(capability))) throw new Error('Acesso não autorizado à identificação do projeto.');
    const input = projectQrIdSchema.safeParse(projectId); if (!input.success) return null;
    let result;
    try { result = await client.from('rm_projetos').select('id,numero,nome,descricao_equipamento,updated_at').eq('id', input.data).maybeSingle(); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable(); if (result.data === null) return null;
    const parsed = projectQrSchema.safeParse(result.data);
    if (!parsed.success || parsed.data.id !== input.data) throw unavailable();
    return parsed.data;
  }
  return { getProjectQr };
}
export async function getProjectQr(projectId: string) {
  const { requireWebUser } = await import('./auth'); const access = await requireWebUser(projectQrScopes);
  return createProjectQrData(access.client, access.sso?.capabilities).getProjectQr(projectId);
}
