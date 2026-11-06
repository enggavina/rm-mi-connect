import type {SupabaseClient} from '@supabase/supabase-js';
import {z} from 'zod';
import {uuid} from './policy';
import type {CorporateCapability} from './sso-policy';

const text=z.string().nullable(),timestamp=z.string().datetime({offset:true});
export const projectRouteCellSnapshotSchema=z.object({
  project:z.object({id:uuid,numero:text,status_pcp:text,data_real_de_entrega:timestamp.nullable(),updated_at:timestamp,closed:z.boolean()}),
  allocation:z.object({id:uuid,projeto_id:uuid,celula_id:uuid,celula_nome:text,status:text,retirada:z.boolean(),updated_at:timestamp,forms_ids:z.array(uuid).max(2000)}),
  forms:z.array(z.object({id:uuid,titulo:text,ativo:z.boolean(),assigned:z.boolean(),can_remove:z.boolean(),reason:text})).max(2000),
  context_version:z.string().regex(/^[a-f0-9]{64}$/),can_edit_forms:z.boolean(),forms_reason:text,
  can_remove_cell:z.boolean(),remove_reason:text,removal_counts:z.object({photos:z.number().int().nonnegative(),rules:z.number().int().nonnegative(),reviewer_assignments:z.number().int().nonnegative()}),complete:z.boolean(),
});
export type ProjectRouteCellSnapshot=z.infer<typeof projectRouteCellSnapshotSchema>;
export const routeCellReadCapabilities:CorporateCapability[]=['em.portal.read','em.projects.read','em.planning.read','em.forms.read'];
const unavailable=()=>new Error('Não foi possível conferir a configuração desta célula. Recarregue o roteiro.');
export function createProjectRouteCellData(client:SupabaseClient,capabilities?:readonly CorporateCapability[]){
  async function getProjectRouteCell(projectId:string,allocationId:string,includeChoices=false):Promise<ProjectRouteCellSnapshot|null>{
    if(capabilities!==undefined&&(!routeCellReadCapabilities.every(c=>capabilities.includes(c))||includeChoices&&!capabilities.includes('em.planning.manage')))
      throw new Error('Acesso não autorizado à configuração da célula.');
    if(!uuid.safeParse(projectId).success||!uuid.safeParse(allocationId).success)return null;
    projectId=projectId.toLowerCase();allocationId=allocationId.toLowerCase();
    let result;try{result=await client.rpc('rm_web_project_route_cell_snapshot_v1',{p_project_id:projectId,p_allocation_id:allocationId,p_include_choices:includeChoices});}catch{throw unavailable();}
    if(result.error)throw unavailable();if(result.data===null)return null;
    const parsed=projectRouteCellSnapshotSchema.safeParse(result.data);if(!parsed.success)throw unavailable();const value=parsed.data;
    const closed=!!value.project.data_real_de_entrega||['cancelado','finalizando_para_faturar'].includes(value.project.status_pcp??'');
    if(value.project.id!==projectId||value.allocation.id!==allocationId||value.allocation.projeto_id!==projectId||value.project.closed!==closed
      ||new Set(value.forms.map(f=>f.id)).size!==value.forms.length||new Set(value.allocation.forms_ids).size!==value.allocation.forms_ids.length
      ||value.forms.some(f=>f.assigned!==value.allocation.forms_ids.includes(f.id))
      ||value.complete&&value.allocation.forms_ids.some(id=>!value.forms.some(f=>f.id===id))
      ||(closed||value.allocation.retirada||!value.complete)&&(value.can_edit_forms||value.can_remove_cell)
      ||value.can_edit_forms&&value.allocation.forms_ids.length>500)throw unavailable();
    return {...value,forms:includeChoices?value.forms:value.forms.filter(f=>f.assigned)};
  }
  return {getProjectRouteCell};
}
export async function getProjectRouteCell(projectId:string,allocationId:string){
  const {requireWebUser}=await import('./auth');const access=await requireWebUser(routeCellReadCapabilities);
  const choices=['administrador','padr_o'].includes(access.profile.perfil)&&(!access.sso||access.sso.capabilities.includes('em.planning.manage'));
  return createProjectRouteCellData(access.client,access.sso?.capabilities).getProjectRouteCell(projectId,allocationId,choices);
}
