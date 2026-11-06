import {createClient,type SupabaseClient} from '@supabase/supabase-js';
import {z} from 'zod';
const claimSchema=z.array(z.object({id:z.string().uuid(),lease_token:z.string().uuid(),bucket_id:z.literal('rm-documentos'),
  object_path:z.string().regex(/^web-dossier\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(pdf|jpg|png)$/).refine(path=>{
    const parts=path.split('/');return z.string().uuid().safeParse(parts[1]).success&&z.string().uuid().safeParse(parts[2]?.replace(/\.(pdf|jpg|png)$/,'')).success;
  })}).strict()).max(5);
const configured=()=>process.env.SUPABASE_URL==='https://ellpxfbsrbhblyizvbbk.supabase.co'&&!!process.env.EM_SSO_BRIDGE_SERVICE_ROLE_KEY;
function client(){
  if(!configured())return null;
  return createClient(process.env.SUPABASE_URL!,process.env.EM_SSO_BRIDGE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false},
    global:{fetch:(input,init)=>fetch(input,{...init,cache:'no-store',signal:AbortSignal.timeout(10000)})}});
}
export function createProjectDeleteCleanup(db:SupabaseClient){
  async function drain(limit=3,submissionId:string|null=null){
    if(!Number.isInteger(limit)||limit<1||limit>5)throw new Error('Invalid cleanup budget');
    if(submissionId!==null&&!z.string().uuid().safeParse(submissionId).success)throw new Error('Invalid cleanup scope');
    const claim=await db.rpc('rm_project_delete_files_claim_v1',{p_limit:limit,p_submission_id:submissionId});if(claim.error)throw new Error('Cleanup unavailable');
    const parsed=claimSchema.safeParse(claim.data);if(!parsed.success)throw new Error('Invalid cleanup claim');
    if(parsed.data.length>limit||new Set(parsed.data.map(job=>job.id)).size!==parsed.data.length||new Set(parsed.data.map(job=>job.object_path)).size!==parsed.data.length)throw new Error('Invalid cleanup claim budget');
    let completed=0;
    for(const job of parsed.data){
      let success=false;
      try{const result=await db.storage.from(job.bucket_id).remove([job.object_path]);success=!result.error||String((result.error as any).statusCode)==='404';}catch{/* Durable lease/backoff retain this job. */}
      const ack=await db.rpc('rm_project_delete_files_finish_v1',{p_id:job.id,p_lease_token:job.lease_token,p_success:success});
      if(ack.error||ack.data!==true)throw new Error('Cleanup confirmation unavailable');
      if(success)completed++;
    }
    return{claimed:parsed.data.length,completed};
  }
  return{drain};
}
export async function drainProjectDeleteFiles(limit=3,submissionId:string|null=null){const db=client();return db?createProjectDeleteCleanup(db).drain(limit,submissionId):{claimed:0,completed:0};}
type CleanupState={timer:ReturnType<typeof setInterval>;running:boolean};
const state=globalThis as typeof globalThis&{__emProjectDeleteCleanup?:CleanupState};
export function startProjectDeleteCleanup(){
  if(process.env.EM_PROJECT_DELETE_CLEANUP_ENABLED!=='true'||process.env.NEXT_PHASE==='phase-production-build'||process.env.NEXT_RUNTIME!=='nodejs'||!configured()||state.__emProjectDeleteCleanup)return;
  const item:CleanupState={timer:null as any,running:false};
  const tick=async()=>{if(item.running)return;item.running=true;try{await drainProjectDeleteFiles(3);}catch{console.error('EM project attachment cleanup will retry.');}finally{item.running=false;}};
  item.timer=setInterval(()=>{void tick();},30000);item.timer.unref?.();state.__emProjectDeleteCleanup=item;void tick();
}
