import {fieldValue,type Entity,type Row} from './mapping';
export class DeletedProjectImportError extends Error{constructor(){super('Registro pertencente a projeto excluído no EM; não será recriado pela importação.');this.name='DeletedProjectImportError';}}
type Rpc=(name:string,args:Row)=>Promise<unknown>;
function references(entity:Entity,raw:Row){
  const result:{table:string;id:string}[]=[];
  if(typeof raw._id==='string')result.push({table:entity.table,id:raw._id});
  for(const field of Object.values(entity.fields))if(field.ref){const value=fieldValue(raw,field);for(const id of(field.list&&Array.isArray(value)?value:[value]))if(typeof id==='string'&&id)result.push({table:field.ref,id});}
  return result;
}
export async function filterDeletedProjectRows(rpc:Rpc,entity:Entity,rawRows:Row[]){
  const groups=new Map<string,Set<string>>();
  for(const raw of rawRows)for(const ref of references(entity,raw)){let values=groups.get(ref.table);if(!values)groups.set(ref.table,values=new Set());values.add(ref.id);}
  const deleted=new Map<string,Set<string>>();
  for(const[table,values]of groups){const ids=[...values];const result=new Set<string>();for(let at=0;at<ids.length;at+=500){const page=ids.slice(at,at+500);const response=await rpc('rm_deleted_bubble_ids_v1',{p_table:table,p_ids:page});if(!Array.isArray(response)||response.some(id=>typeof id!=='string'||!page.includes(id)))throw new Error('Não foi possível conferir exclusões anteriores antes da importação.');for(const id of response)result.add(id);}deleted.set(table,result);}
  const rows=rawRows.filter(raw=>!references(entity,raw).some(ref=>deleted.get(ref.table)?.has(ref.id)));
  return{rows,excluded:rawRows.length-rows.length};
}
