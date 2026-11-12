import ExcelJS from 'exceljs';
import {PassThrough} from 'node:stream';
import {allocationExportFields,type AllocationExportField} from './allocation-export-policy';
import type {AllocationExportSnapshot} from './allocation-export-data';

function cutName(value:string,length:number){let result='';for(const char of value){if(result.length+char.length>length)break;result+=char;}return result;}
export function allocationWorksheetNames(names:readonly string[]):string[]{
 const used=new Set<string>();return names.map((name,index)=>{
  let base=name.replace(/[\\\/?*\[\]:\x00-\x1f]/g,' ').replace(/^[\s']+|[\s']+$/g,'');
  if(!base)base=`Célula ${index+1}`;if(base.toLowerCase()==='history')base='Célula History';
  let result=cutName(base,31).replace(/[\s']+$/g,''),number=1;
  while(used.has(result.toLowerCase())){const suffix=` (${++number})`;result=cutName(base,31-suffix.length)+suffix;}
  used.add(result.toLowerCase());return result;
 });
}
export function allocationExcelDate(value:string):Date|null{
 let parts:number[];
 if(/^\d{4}-\d{2}-\d{2}$/.test(value))parts=value.split('-').map(Number).concat([0,0,0]);
 else{
  const instant=new Date(value);if(!Number.isFinite(instant.valueOf()))return null;
  const formatted=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(instant);
  const number=(type:string)=>Number(formatted.find(part=>part.type===type)?.value);
  parts=['year','month','day','hour','minute','second'].map(number);
 }
 const [year,month,day,hour,minute,second]=parts;
 if(year<1900||year>9999)return null;
 const result=new Date(Date.UTC(year,month-1,day,hour,minute,second));
 return result.getUTCFullYear()===year&&result.getUTCMonth()===month-1&&result.getUTCDate()===day?result:null;
}
export function allocationExportFilename(at:Date){
 const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(at);
 return `planejamento_alocacoes_${day}.xlsx`;
}
/** Row commit releases cell objects; only the bounded snapshot and ZIP bytes remain. */
export async function buildAllocationWorkbook(snapshot:AllocationExportSnapshot,signal?:AbortSignal):Promise<Uint8Array>{
 const stream=new PassThrough(),chunks:Buffer[]=[];let size=0,streamError:Error|undefined;
 stream.on('error',error=>{streamError=error;});
 stream.on('data',(chunk:Buffer)=>{size+=chunk.length;if(size>64*1024*1024){streamError=new Error('Export too large');stream.destroy(streamError);}else chunks.push(chunk);});
 const workbook=new ExcelJS.stream.xlsx.WorkbookWriter({stream,useStyles:true,useSharedStrings:false});
 workbook.creator='EM · MI Electric Brasil';workbook.created=new Date(snapshot.generated_at);workbook.modified=workbook.created;
 const names=allocationWorksheetNames(snapshot.cells.map(cell=>cell.name));
 try{
  for(const [index,cell] of snapshot.cells.entries()){
   if(signal?.aborted)throw new Error('Export cancelled');
   const sheet=workbook.addWorksheet(names[index],{views:[{state:'frozen',ySplit:1}],properties:{defaultRowHeight:18}});
   const fields=snapshot.fields.map(key=>allocationExportFields.find(field=>field.key===key as AllocationExportField)!);
   sheet.columns=fields.map(field=>({header:field.label,key:field.key,width:field.width,style:{font:{name:'Calibri',size:11},
    alignment:{vertical:'top',wrapText:field.width>=35},...(field.kind==='number'?{numFmt:'#,##0.00'}:field.kind==='date'?{numFmt:'dd/mm/yyyy'}:field.kind==='datetime'?{numFmt:'dd/mm/yyyy hh:mm'}:{})}}));
   sheet.autoFilter={from:{row:1,column:1},to:{row:Math.max(1,cell.rows.length+1),column:fields.length}};
   const header=sheet.getRow(1);header.height=32;
   header.eachCell(entry=>{entry.font={name:'Calibri',size:11,bold:true,color:{argb:'FFFFFFFF'}};entry.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF173B56'}};entry.alignment={vertical:'middle',wrapText:true};});header.commit();
   for(const source of cell.rows){
    if(signal?.aborted||streamError)throw streamError??new Error('Export cancelled');
    const row=sheet.addRow(fields.map(field=>{
     const value=source.values[field.key];
     if(value===null)return null;
     if(field.kind==='date'||field.kind==='datetime')return allocationExcelDate(value as string)??value;
     // Strings remain strings, including formula-looking input and identifiers
     // with leading zeros. No formulas, macros, hyperlinks or external fetches.
     return value;
    }));
    // Keep one physical row per allocation even when every selected field is
    // absent on a legacy project. An all-null row must not disappear from XLSX.
    row.height=18;row.commit();
   }
   sheet.commit();
  }
  await workbook.commit();if(streamError)throw streamError;
  return new Uint8Array(Buffer.concat(chunks));
 }catch(error){stream.destroy();throw error;}
}
