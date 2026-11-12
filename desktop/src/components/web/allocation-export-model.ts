import {allocationExportLimits,allocationExportMime,allocationExportSchema,type AllocationExportRequest} from '../../server/web/allocation-export-policy';
export type {AllocationExportRequest};
export type AllocationExportCell = {id:string;nome:string|null};
export type AllocationExportField = {key:string;label:string;group:'project'|'equipment'|'allocation'};

export function allocationExportRequest(cellIds:readonly string[],fieldIds:readonly string[],cells:readonly AllocationExportCell[],fields:readonly AllocationExportField[]):AllocationExportRequest{
  if(cellIds.length===0)throw new Error('Selecione pelo menos uma célula para exportar.');
  if(cellIds.length>allocationExportLimits.cells)throw new Error(`Selecione no máximo ${allocationExportLimits.cells} células por arquivo.`);
  if(fieldIds.length===0)throw new Error('Selecione pelo menos uma informação para exportar.');
  if(new Set(cellIds).size!==cellIds.length||cellIds.some(id=>!cells.some(cell=>cell.id===id)))throw new Error('Confira as células selecionadas antes de exportar.');
  if(new Set(fieldIds).size!==fieldIds.length||fieldIds.some(key=>!fields.some(field=>field.key===key)))throw new Error('Confira as informações selecionadas antes de exportar.');
  const parsed=allocationExportSchema.safeParse({cell_ids:cells.filter(cell=>cellIds.includes(cell.id)).map(cell=>cell.id),fields:fields.filter(field=>fieldIds.includes(field.key)).map(field=>field.key)});
  if(!parsed.success)throw new Error('Confira as células e as informações antes de exportar.');
  return parsed.data;
}

const xlsxMime=allocationExportMime;
function exportFilename(disposition:string|null){
  const encoded=disposition?.match(/filename\*\s*=\s*UTF-8''([^;]+)/i)?.[1];
  let value=disposition?.match(/filename\s*=\s*"([^"]+)"/i)?.[1]??disposition?.match(/filename\s*=\s*([^;\s]+)/i)?.[1];
  if(encoded){try{value=decodeURIComponent(encoded);}catch{/* Use the safe fallback below. */}}
  return value&&/^planejamento_alocacoes(?:_\d{4}-\d{2}-\d{2}(?:_\d{6})?)?\.xlsx$/.test(value)?value:'planejamento_alocacoes.xlsx';
}

export async function fetchAllocationExport(input:AllocationExportRequest,signal:AbortSignal,fetcher:typeof fetch=fetch):Promise<{blob:Blob;filename:string}>{
  const response=await fetcher('/api/web/planning/export',{method:'POST',headers:{'Content-Type':'application/json',Accept:xlsxMime},
    body:JSON.stringify(input),credentials:'same-origin',mode:'same-origin',redirect:'error',cache:'no-store',signal});
  if(!response.ok){
    if(response.status===401)throw new Error('Sua sessão expirou. Entre novamente para exportar.');
    if(response.status===403)throw new Error('Você não tem permissão para exportar estes dados.');
    if(response.status===400||response.status===422||response.status===413){
      const result=await response.json().catch(()=>null);
      if(typeof result?.error==='string'&&result.error.trim()&&result.error.length<=300)throw new Error(result.error);
    }
    throw new Error('Não foi possível gerar o Excel. Tente novamente.');
  }
  if(response.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!==xlsxMime)throw new Error('Não foi possível confirmar o arquivo Excel. Tente novamente.');
  const blob=await response.blob();
  if(blob.size===0)throw new Error('O arquivo Excel recebido está vazio. Tente novamente.');
  return{blob,filename:exportFilename(response.headers.get('content-disposition'))};
}
