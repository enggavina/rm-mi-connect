import type {getWebUser} from './auth';
import {hasWebCapability,sameOriginPost} from './auth-policy';
import {CorporateAuthError} from './sso-policy';
import {AllocationExportError,createAllocationExportData} from './allocation-export-data';
import {allocationExportLimits,allocationExportMime,allocationExportSchema,allocationExportScopes} from './allocation-export-policy';
import {allocationExportFilename,buildAllocationWorkbook} from './allocation-export-workbook';
import {readWorkshopOperations} from './workshop-operation-reader';
import {WorkshopContextError} from './workshop-context';
const headers={'Cache-Control':'private, no-store','Vary':'Cookie','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
const fail=(status:number,error:string)=>Response.json({error},{status,headers});
class BodyTooLarge extends Error{}
async function boundedJson(request:Request){
 const length=request.headers.get('content-length');if(length&&(!/^\d+$/.test(length)||Number(length)>allocationExportLimits.bodyBytes))throw new BodyTooLarge();
 if(!request.body)throw new Error('Empty body');const reader=request.body.getReader();let size=0;const chunks:Uint8Array[]=[];
 try{while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>allocationExportLimits.bodyBytes){await reader.cancel();throw new BodyTooLarge();}chunks.push(part.value);}}
 finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.byteLength;}
 return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export async function handleAllocationExport(request:Request,dependencies:{getWebUser:typeof getWebUser;buildWorkbook?:typeof buildAllocationWorkbook}):Promise<Response>{
 if(!sameOriginPost(request.headers.get('origin'),request.headers.get('host')))return fail(403,'Origem da solicitação não autorizada.');
 try{
  const access=await dependencies.getWebUser(allocationExportScopes);if(!access)return fail(401,'Autenticação necessária.');
  if(!['administrador','padr_o','auditor'].includes(access.profile.perfil)||!allocationExportScopes.every(scope=>hasWebCapability(access,scope)))return fail(403,'Acesso à exportação não autorizado.');
  if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')return fail(415,'Envie uma seleção de células e campos.');
  let input:unknown;try{input=await boundedJson(request);}catch(error){return fail(error instanceof BodyTooLarge?413:400,'Não foi possível ler a seleção de células e campos.');}
  const parsed=allocationExportSchema.safeParse(input);if(!parsed.success)return fail(400,'Selecione ao menos uma célula e um campo válido, sem repetições.');
  const snapshot=await createAllocationExportData(access.client,access.sso?.capabilities,await readWorkshopOperations(access,'sso')).snapshot(parsed.data);
  const bytes=await(dependencies.buildWorkbook??buildAllocationWorkbook)(snapshot,request.signal);
  return new Response(bytes as Uint8Array<ArrayBuffer>,{status:200,headers:{...headers,'Content-Type':allocationExportMime,
   'Content-Disposition':`attachment; filename="${allocationExportFilename(new Date(snapshot.generated_at))}"`}});
 }catch(error){
  if(error instanceof CorporateAuthError)return fail(error.status,error.message);
  if(error instanceof WorkshopContextError)return fail(error.status,error.message);
  if(error instanceof AllocationExportError){if(error.code==='denied')return fail(403,'Uma célula ou projeto não está disponível para exportação.');if(error.code==='limit')return fail(422,'A seleção excede o limite de exportação. Selecione menos células ou campos.');}
  return fail(503,'Não foi possível gerar o Excel. Tente novamente.');
 }
}
