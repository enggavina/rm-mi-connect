'use server';
import {actionUser,mutate,type WebActionResult} from './mutation';
import {hasWebCapability} from './auth-policy';
import {deleteProjectSchema} from './project-delete-policy';
import {createProjectDeleteData} from './project-delete-data';
import {drainProjectDeleteFiles} from './project-delete-cleanup';
export async function inspectProjectDeletion(projectId:string){
  const access=await actionUser('em.projects.manage');if('ok'in access)return access;
  if(access.profile.perfil!=='administrador'||!hasWebCapability(access,'em.projects.read')||!hasWebCapability(access,'em.portal.read'))return{ok:false as const,error:'Exclusão restrita aos administradores do EM.'};
  try{return{ok:true as const,snapshot:await createProjectDeleteData(access.client,access.sso?.capabilities).getProjectDeleteSnapshot(projectId)};}
  catch{return{ok:false as const,error:'Não foi possível conferir o projeto e suas dependências. Tente novamente.'};}
}
export async function deleteProject(input:unknown):Promise<WebActionResult>{
  const access=await actionUser('em.projects.manage');if('ok'in access)return access;
  if(access.profile.perfil!=='administrador'||!hasWebCapability(access,'em.projects.read')||!hasWebCapability(access,'em.portal.read'))return{ok:false,code:'42501',error:'Exclusão restrita aos administradores do EM.'};
  const parsed=deleteProjectSchema.safeParse(input);
  if(!parsed.success)return{ok:false,code:'INVALID_INPUT',error:'Confirme a exclusão e informe uma justificativa válida.'};
  const result=await mutate(access.client,'delete_project',parsed.data,'em.projects.manage',access.sso);if(!result.ok)return result;
  const data=result.data;
  if(data.operation!=='delete_project'||data.id!==parsed.data.id||data.projeto_id!==parsed.data.id||data.record?.id!==parsed.data.id||data.record.deleted!==true
    ||typeof data.updated_at!=='string'||Number.isNaN(Date.parse(data.updated_at))||typeof data.idempotent_replay!=='boolean'
    ||typeof data.record.cleanup_pending!=='number'||!Number.isSafeInteger(data.record.cleanup_pending)||data.record.cleanup_pending<0)
    return{ok:false,code:'UNAVAILABLE',error:'Não foi possível confirmar a exclusão. Tente confirmar novamente com o mesmo protocolo.'};
  // The durable queue is committed with deletion. A failed Storage request does
  // not resurrect the project or change the original request/protocol.
  if(data.record.cleanup_pending>0)await drainProjectDeleteFiles(1,parsed.data.submissionId).catch(()=>{});
  return{ok:true,data:{operation:data.operation,id:data.id,projeto_id:data.projeto_id,updated_at:data.updated_at,idempotent_replay:data.idempotent_replay,
    record:{id:data.id,deleted:true,label:typeof data.record.label==='string'?data.record.label:'Projeto',cleanup_pending:data.record.cleanup_pending}}};
}
