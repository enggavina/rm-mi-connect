import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import type { CorporateCapability } from './sso-policy';
import type { WebRow } from './data';
import { pageNumber, uuid } from './policy';
import { createStageApprovalData } from './stage-approval-data';
import type { StageApprovalListItem } from './stage-approval-data';
import { allocationStage } from './project-schedule-policy';

const SLOT = 'id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,descricao,legenda,tag,numero,updated_at';
const PAGE_SIZE = 25;
const slotSchema = z.object({
  id: uuid, projeto_id: uuid, celula_id: uuid, celula_projeto_id: uuid.nullable(),
  categoria_foto: z.string().nullable(), titulo: z.string().nullable(), descricao: z.string().nullable(),
  legenda: z.string().nullable(), tag: z.string().nullable(), numero: z.number().nullable(),
  updated_at: z.string().datetime({ offset: true }),
});
export type ProjectSchedulePhoto = z.infer<typeof slotSchema> & { captured: boolean };
export type ProjectSchedulePhotos = { rows: ProjectSchedulePhoto[]; total: number; page: number; pageSize: number };
const failure = () => new Error('Não foi possível consultar os registros desta célula. Tente novamente.');
export function createProjectScheduleData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  function authorize(capability: CorporateCapability) {
    if (capabilities !== undefined && ['em.portal.read', 'em.projects.read', 'em.planning.read', capability].some(code => !capabilities.includes(code as CorporateCapability))) throw new Error('Acesso não autorizado aos registros da célula.');
  }
  async function allocation(projectId: string, allocationId: string): Promise<WebRow | null> {
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(allocationId).success) return null;
    const result = await client.from('rm_celulas_projeto').select('id,projeto_id,celula_id').eq('projeto_id', projectId).eq('id', allocationId).maybeSingle();
    if (result.error) throw failure();
    if (!result.data) return null;
    if (result.data.id !== allocationId || result.data.projeto_id !== projectId || !uuid.safeParse(result.data.celula_id).success) throw failure();
    return result.data;
  }
  async function photos(projectId: string, allocationId: string, number?: string | number): Promise<ProjectSchedulePhotos | null> {
    authorize('em.photos.read');
    const current = await allocation(projectId, allocationId);
    if (!current) return null;
    const page = pageNumber(number);
    const scoped = () => client.from('rm_fotos').select(SLOT, { count: 'exact' })
      .eq('projeto_id', projectId).eq('celula_id', current.celula_id).eq('lixeira', false)
      .or(`celula_projeto_id.eq.${allocationId},celula_projeto_id.is.null`);
    const result = await scoped().order('numero', { ascending: true, nullsFirst: false }).order('id').range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
    if (result.error) throw failure();
    const parsed = z.array(slotSchema).safeParse(result.data || []);
    if (!parsed.success) throw failure();
    const rows = parsed.data;
    if (rows.some(row => row.projeto_id !== projectId || row.celula_id !== current.celula_id
      || (row.celula_projeto_id !== null && row.celula_projeto_id !== allocationId))) throw failure();
    // Only IDs are selected to derive capture state. Media URLs never enter this DTO.
    const captured = rows.length ? await client.from('rm_fotos').select('id').eq('projeto_id', projectId)
      .eq('celula_id', current.celula_id).eq('lixeira', false)
      .or(`celula_projeto_id.eq.${allocationId},celula_projeto_id.is.null`)
      .in('id', rows.map(row => row.id)).not('foto_url', 'is', null).neq('foto_url', '') : { data: [], error: null };
    if (captured.error) throw failure();
    const captures = new Set((captured.data || []).map(row => row.id));
    return { rows: rows.map(row => ({ ...row, captured: captures.has(row.id) })), total: result.count ?? 0, page, pageSize: PAGE_SIZE };
  }
  async function stages(projectId: string, allocationId: string, number?: string | number) {
    authorize('em.approvals.read');
    const current = await allocation(projectId, allocationId);
    if (!current) return null;
    const reader = createStageApprovalData(client, capabilities);
    const items: StageApprovalListItem[] = [];
    // The existing RPC filters by project/cell. Reconcile exact/legacy allocation
    // links before paginating the displayed collection, never after slicing it.
    for (let at = 1; at <= 200; at++) {
      const result = await reader.listStageApprovals({ project: projectId, cell: current.celula_id, state: 'all', page: at });
      items.push(...result.items.filter(item => allocationStage(item, current)));
      if (at * result.page_size >= result.total) {
        const page = pageNumber(number);
        return { items: items.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE), total: items.length, page, pageSize: PAGE_SIZE };
      }
    }
    throw new Error('Esta célula excedeu o limite de etapas desta tela. Consulte as aprovações do projeto.');
  }
  return { photos, stages };
}
