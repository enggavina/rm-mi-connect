import type { SupabaseClient } from '@supabase/supabase-js';
import type { CorporateCapability } from './sso-policy';
import type { WebRow } from './data';
import { pageNumber, uuid } from './policy';
import { createStageApprovalData } from './stage-approval-data';
import type { StageApprovalListItem } from './stage-approval-data';
import { allocationStage } from './project-schedule-policy';

const PAGE_SIZE = 25;
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
  return { stages };
}
