import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';

const timestamp = z.string().datetime({ offset: true }), text = z.string().nullable();
const snapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, status_pcp: text, data_real_de_entrega: timestamp.nullable(), updated_at: timestamp, closed: z.boolean() }),
  allocation: z.object({ id: uuid, projeto_id: uuid, celula_id: uuid, celula_nome: text, status: text, visibilidade: z.boolean(), retirada: z.boolean(),
    indice: z.number().nullable(), posicao: z.number().nullable(), prioridade: text, updated_at: timestamp }),
  can_set_visibility: z.boolean(), can_retire: z.boolean(), can_restore: z.boolean(),
  visibility_reason: text, retire_reason: text, restore_reason: text, in_queue: z.boolean(), context_version: z.string().regex(/^[0-9a-f]{64}$/),
});
export type CellAvailabilitySnapshot = z.infer<typeof snapshotSchema>;
const readCapabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read'];
const unavailable = () => new Error('Não foi possível consultar a disponibilidade desta célula. Tente novamente.');

/** Only coarse operational eligibility is exposed; no child counts, files or identities. */
export function createCellAvailabilityData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getCellAvailability(projectId: string, allocationId: string): Promise<CellAvailabilitySnapshot | null> {
    if (capabilities !== undefined && !readCapabilities.every(capability => capabilities.includes(capability))) throw new Error('Acesso não autorizado à disponibilidade desta célula.');
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(allocationId).success) return null;
    let result;
    try { result = await client.rpc('rm_web_cell_availability_snapshot_v1', { p_project_id: projectId, p_allocation_id: allocationId }); }
    catch { throw unavailable(); }
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = snapshotSchema.safeParse(result.data); if (!parsed.success) throw unavailable();
    const snapshot = parsed.data;
    const closed = snapshot.project.data_real_de_entrega !== null || ['cancelado', 'finalizando_para_faturar'].includes(snapshot.project.status_pcp ?? '');
    const inQueue = !closed && !snapshot.allocation.retirada && !['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '');
    if (snapshot.project.id !== projectId || snapshot.allocation.id !== allocationId || snapshot.allocation.projeto_id !== projectId
      || snapshot.project.closed !== closed || snapshot.in_queue !== inQueue
      || snapshot.allocation.retirada && (snapshot.allocation.visibilidade || snapshot.can_set_visibility || snapshot.can_retire)
      || !snapshot.allocation.retirada && snapshot.can_restore
      || closed && (snapshot.can_set_visibility || snapshot.can_retire || snapshot.can_restore)) throw unavailable();
    return snapshot;
  }
  return { getCellAvailability };
}
export async function getCellAvailability(projectId: string, allocationId: string) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(readCapabilities);
  return createCellAvailabilityData(access.client, access.sso?.capabilities).getCellAvailability(projectId, allocationId);
}
