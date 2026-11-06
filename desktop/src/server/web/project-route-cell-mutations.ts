import {hasWebCapability} from './auth-policy';
import type {actionUser,mutate,WebActionResult} from './mutation';
import {manageProjectRouteCellSchema,projectRouteCellResultSchema} from './project-route-cell-policy';

export function createProjectRouteCellActions(dependencies:{actionUser:typeof actionUser;mutate:typeof mutate}){
  async function manageProjectRouteCell(input:unknown):Promise<WebActionResult>{
    const access=await dependencies.actionUser('em.planning.manage');if('ok' in access)return access;
    const parsed=manageProjectRouteCellSchema.safeParse(input);
    if(!parsed.success)return {ok:false,code:'INVALID_INPUT',error:'Confira a configuração e confirme a alteração da célula.',fieldErrors:parsed.error.flatten().fieldErrors};
    const scopes=parsed.data.action==='remove'?['em.portal.read','em.projects.read','em.planning.read','em.forms.read','em.photos.read','em.approvals.read'] as const
      :['em.portal.read','em.projects.read','em.planning.read','em.forms.read'] as const;
    if(!['administrador','padr_o'].includes(access.profile.perfil)||!scopes.every(c=>hasWebCapability(access,c)))
      return {ok:false,code:'42501',error:'Seu acesso não permite alterar esta configuração do roteiro.'};
    const result=await dependencies.mutate(access.client,'manage_project_route_cell',parsed.data,'em.planning.manage',access.sso);if(!result.ok)return result;
    const record=projectRouteCellResultSchema.safeParse(result.data.record),value=parsed.data;
    if(!record.success||result.data.operation!=='manage_project_route_cell'||result.data.id!==value.celula_projeto_id
      ||result.data.projeto_id!==value.projeto_id||record.data.projeto_id!==value.projeto_id||record.data.celula_projeto_id!==value.celula_projeto_id
      ||typeof result.data.idempotent_replay!=='boolean'||typeof result.data.updated_at!=='string'||Number.isNaN(Date.parse(result.data.updated_at))
      ||record.data.action!==value.action||record.data.changed_ids.some(id=>id!==value.celula_projeto_id)
      ||value.action==='remove'&&(!record.data.retirada||record.data.forms_ids.length!==0)
      ||value.action==='forms'&&(record.data.retirada||record.data.forms_ids.length!==value.forms_ids.length||record.data.forms_ids.some(id=>!value.forms_ids.includes(id))))
      return {ok:false,code:'UNAVAILABLE',error:'Não foi possível confirmar a configuração. Tente novamente com o mesmo protocolo.'};
    return {ok:true,data:{operation:result.data.operation,id:result.data.id,projeto_id:result.data.projeto_id,updated_at:result.data.updated_at,
      idempotent_replay:result.data.idempotent_replay,record:record.data}};
  }
  return {manageProjectRouteCell};
}
