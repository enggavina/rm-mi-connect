import type {SupabaseClient} from '@supabase/supabase-js';
import {z} from 'zod';
import type {CorporateCapability} from './sso-policy';
import {allocationExportFields,allocationExportLimits,allocationExportSchema,allocationExportScopes,type AllocationExportRequest} from './allocation-export-policy';
const uuid=z.string().uuid(),scalar=z.union([z.string().max(32_767),z.number().finite(),z.null()]);
const rowSchema=z.object({allocation_id:uuid,project_id:uuid,values:z.record(z.string(),scalar)}).strict();
export const allocationExportSnapshotSchema=z.object({generated_at:z.string().datetime({offset:true}),fields:z.array(z.string()),row_count:z.number().int().min(0).max(allocationExportLimits.rows),complete:z.literal(true),
 cells:z.array(z.object({id:uuid,name:z.string().max(2000),rows:z.array(rowSchema).max(allocationExportLimits.rows)}).strict()).min(1).max(allocationExportLimits.cells)}).strict();
export type AllocationExportSnapshot=z.infer<typeof allocationExportSnapshotSchema>;
export class AllocationExportError extends Error{constructor(public readonly code:'denied'|'limit'|'unavailable'){super(code);}}
export function createAllocationExportData(client:SupabaseClient,capabilities?:readonly CorporateCapability[]){
 async function snapshot(input:AllocationExportRequest):Promise<AllocationExportSnapshot>{
  if(capabilities&&!allocationExportScopes.every(scope=>capabilities.includes(scope)))throw new AllocationExportError('denied');
  const request=allocationExportSchema.parse(input);let response;
  try{response=await client.rpc('rm_web_planning_export_snapshot_v1',{p_cell_ids:request.cell_ids,p_fields:request.fields});}catch{throw new AllocationExportError('unavailable');}
  if(response.error)throw new AllocationExportError(response.error.code==='42501'?'denied':response.error.code==='PT413'?'limit':'unavailable');
  const parsed=allocationExportSnapshotSchema.safeParse(response.data);if(!parsed.success)throw new AllocationExportError('unavailable');
  const value=parsed.data,ids=new Set<string>();
  if(value.cells.length!==request.cell_ids.length||value.fields.join('|')!==request.fields.join('|')||value.cells.some((cell,i)=>cell.id!==request.cell_ids[i])
   ||value.cells.reduce((total,cell)=>total+cell.rows.length,0)!==value.row_count)throw new AllocationExportError('unavailable');
  for(const cell of value.cells)for(const row of cell.rows){
   if(ids.has(row.allocation_id)||Object.keys(row.values).length!==request.fields.length||request.fields.some(key=>!Object.hasOwn(row.values,key)))throw new AllocationExportError('unavailable');
   ids.add(row.allocation_id);
   for(const key of request.fields){const kind=allocationExportFields.find(f=>f.key===key)!.kind,entry=row.values[key];
    if(entry!==null&&(kind==='number'?typeof entry!=='number':typeof entry!=='string'))throw new AllocationExportError('unavailable');
   }
  }
  return value;
 }
 return{snapshot};
}
