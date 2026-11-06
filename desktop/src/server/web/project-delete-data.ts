import type {SupabaseClient} from '@supabase/supabase-js';
import {z} from 'zod';
import {projectDeleteSnapshotSchema,type ProjectDeleteSnapshot} from './project-delete-policy';
import type {CorporateCapability} from './sso-policy';
const scopes:CorporateCapability[]=['em.portal.read','em.projects.read','em.projects.manage'];
export function createProjectDeleteData(client:SupabaseClient,capabilities?:readonly CorporateCapability[]){
  async function getProjectDeleteSnapshot(projectId:string):Promise<ProjectDeleteSnapshot|null>{
    if(capabilities!==undefined&&!scopes.every(scope=>capabilities.includes(scope)))throw new Error('Acesso não autorizado à exclusão.');
    if(!z.string().uuid().safeParse(projectId).success)return null;
    let result;try{result=await client.rpc('rm_web_project_delete_snapshot_v1',{p_project_id:projectId.toLowerCase()});}catch{throw new Error('Não foi possível conferir as dependências deste projeto.');}
    if(result.error)throw new Error('Não foi possível conferir as dependências deste projeto.');
    if(result.data===null)return null;
    const parsed=projectDeleteSnapshotSchema.safeParse(result.data);
    if(!parsed.success||parsed.data.project.id!==projectId.toLowerCase()||parsed.data.can_delete&&parsed.data.reason!==null)throw new Error('Não foi possível confirmar o contexto da exclusão.');
    return parsed.data;
  }
  return{getProjectDeleteSnapshot};
}
export async function getProjectDeleteSnapshot(projectId:string){
  const {requireWebUser}=await import('./auth');const access=await requireWebUser(scopes);
  if(access.profile.perfil!=='administrador')throw new Error('Exclusão restrita aos administradores do EM.');
  return createProjectDeleteData(access.client,access.sso?.capabilities).getProjectDeleteSnapshot(projectId);
}
