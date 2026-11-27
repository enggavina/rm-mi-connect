import test from 'node:test';
import assert from 'node:assert/strict';
import ExcelJS from 'exceljs';
import {allocationExportFields,allocationExportMime,allocationExportSchema,allocationExportScopes} from '../src/server/web/allocation-export-policy';
import {AllocationExportError,createAllocationExportData,type AllocationExportSnapshot} from '../src/server/web/allocation-export-data';
import {allocationWorksheetNames,allocationExcelDate,allocationExportFilename,buildAllocationWorkbook} from '../src/server/web/allocation-export-workbook';
import {handleAllocationExport} from '../src/server/web/allocation-export-route';
const id=(number:number)=>`10000000-0000-4000-8000-${String(number).padStart(12,'0')}`;
const fields=['project_number','cell_name','allocation_status','planned_hours','allocation_due','serial_number'] as const;
function snapshot():AllocationExportSnapshot{return{generated_at:'2026-11-12T02:00:00Z',fields:[...fields],row_count:2,complete:true,cells:[
 {id:id(1),name:'Montagem / teste',rows:[{allocation_id:id(11),project_id:id(101),values:{project_number:'00015',cell_name:'Montagem / teste',allocation_status:'Aguardando coleta',planned_hours:12.25,allocation_due:'2026-11-12T01:00:00Z',serial_number:'=HYPERLINK("https://example.invalid","x")'}}]},
 {id:id(2),name:'Montagem : teste',rows:[{allocation_id:id(12),project_id:id(101),values:{project_number:'00015',cell_name:'Montagem : teste',allocation_status:'Coletado',planned_hours:null,allocation_due:null,serial_number:'000001'}}]},
]};}
const selection={cell_ids:[id(1),id(2)],fields:[...fields]};
test('export selection is a closed actual-field whitelist with cells and columns required',()=>{
 assert.ok(allocationExportSchema.safeParse(selection).success);
 for(const input of [{...selection,cell_ids:[]},{...selection,fields:[]},{...selection,fields:['auth_user_id']},{...selection,fields:['numero_projeto_fake']},{...selection,cell_ids:[id(1),id(1)]},{...selection,fields:['project_number','project_number']},{...selection,cell_ids:Array.from({length:201},(_,i)=>id(i+1))},{...selection,actor:id(99)}])assert.equal(allocationExportSchema.safeParse(input).success,false);
 assert.equal(new Set(allocationExportFields.map(field=>field.key)).size,allocationExportFields.length);
 assert.equal(allocationExportFields.some(field=>/uuid|email|password|token|arquivo_url/.test(field.key)),false);
});
test('one authorized snapshot preserves allocations in distinct cells and requests only selected fields',async()=>{
 const calls:any[]=[];const client={rpc:async(name:string,args:any)=>{calls.push({name,args});return{error:null,data:snapshot()};}} as any;
 const result=await createAllocationExportData(client,allocationExportScopes).snapshot(selection);
 assert.equal(calls.length,1);assert.equal(calls[0].name,'rm_web_planning_export_snapshot_v1');assert.deepEqual(calls[0].args,{p_cell_ids:selection.cell_ids,p_fields:selection.fields});
 assert.equal(result.cells[0].rows[0].project_id,result.cells[1].rows[0].project_id);
 assert.notEqual(result.cells[0].rows[0].allocation_id,result.cells[1].rows[0].allocation_id);
 await assert.rejects(()=>createAllocationExportData(client,['em.planning.read']).snapshot(selection),error=>error instanceof AllocationExportError&&error.code==='denied');assert.equal(calls.length,1);
});
test('workshop export sends the closed request to the scoped projection', async () => {
 const client={rpc(){assert.fail('unexpected legacy export RPC');}} as any;
 const data=createAllocationExportData(client,allocationExportScopes,async(resource,args)=>{
  assert.equal(resource,'planning_export');
  assert.deepEqual(args,selection);
  return snapshot();
 });
 assert.equal((await data.snapshot(selection)).row_count,2);
});
test('incomplete, substituted or overbroad data never becomes a downloadable workbook',async()=>{
 const good=snapshot();const corruptions=[
  {...good,complete:false}, {...good,row_count:1}, {...good,fields:['project_number']},
  {...good,cells:[good.cells[1],good.cells[0]]},
  {...good,cells:good.cells.map(cell=>({...cell,rows:cell.rows.map(row=>({...row,allocation_id:id(11)}))}))},
  {...good,cells:[{...good.cells[0],rows:[{...good.cells[0].rows[0],values:{...good.cells[0].rows[0].values,token:'private'}}]},good.cells[1]]},
  {...good,cells:[{...good.cells[0],rows:[{...good.cells[0].rows[0],values:{...good.cells[0].rows[0].values,planned_hours:'12.25'}}]},good.cells[1]]},
 ];
 for(const data of corruptions)await assert.rejects(()=>createAllocationExportData({rpc:async()=>({error:null,data})} as any).snapshot(selection),AllocationExportError);
 for(const [code,expected]of [['42501','denied'],['PT413','limit'],['XX000','unavailable']] as const)await assert.rejects(()=>createAllocationExportData({rpc:async()=>({error:{code,message:'private SQL'}})} as any).snapshot(selection),error=>error instanceof AllocationExportError&&error.code===expected);
});
test('worksheet technical names handle invalid characters, duplicate case, apostrophes, emoji and reserved names',()=>{
 const names=allocationWorksheetNames(['Montagem / Teste','Montagem : Teste','MONTAGEM   TESTE',"'",'History','x'.repeat(31),'x'.repeat(35),'😀'.repeat(30),'[]:*?/\\','A'.repeat(30)+"'B","' 'Linha"]);
 assert.equal(new Set(names.map(name=>name.toLowerCase())).size,names.length);
 for(const name of names){assert.ok(name.length>0&&name.length<=31);assert.doesNotMatch(name,/[\\\/?*\[\]:\x00-\x1f]/);assert.ok(!name.startsWith("'")&&!name.endsWith("'"));assert.doesNotMatch(name,/^[\uD800-\uDBFF]$|[\uD800-\uDBFF]$/);}
 assert.equal(names[4],'Célula History');
});
test('calendar dates keep their day and timestamps/filename use Sao Paulo, including historical DST',()=>{
 assert.equal(allocationExcelDate('2026-11-12')?.toISOString(),'2026-11-12T00:00:00.000Z');
 assert.equal(allocationExcelDate('2026-11-12T01:00:00Z')?.toISOString(),'2026-11-11T22:00:00.000Z');
 assert.equal(allocationExcelDate('2018-12-10T03:00:00Z')?.toISOString(),'2018-12-10T01:00:00.000Z');
 assert.equal(allocationExcelDate('2026-02-30'),null);assert.equal(allocationExcelDate('invalid'),null);
 assert.equal(allocationExportFilename(new Date('2026-11-12T02:00:00Z')),'planejamento_alocacoes_2026-11-11.xlsx');
});
test('the generated file is a real XLSX with one sheet per cell, typed values and no deduplication by project',async()=>{
 const data=snapshot();data.cells.push({id:id(3),name:'Célula vazia',rows:[]});
 const bytes=await buildAllocationWorkbook(data);assert.equal(Buffer.from(bytes).subarray(0,2).toString(),'PK');
 const read=new ExcelJS.Workbook();await read.xlsx.load(bytes as any);
 assert.equal(read.worksheets.length,3);assert.equal(read.worksheets[0].rowCount,2);assert.equal(read.worksheets[1].rowCount,2);assert.equal(read.worksheets[2].rowCount,1);
 const first=read.worksheets[0],second=read.worksheets[1];
 assert.equal(first.columnCount,fields.length);assert.equal(first.getCell('A1').value,'Número do projeto');assert.equal(first.getCell('A2').value,'00015');assert.equal(second.getCell('A2').value,'00015');
 assert.equal(first.getCell('B2').value,data.cells[0].name);assert.equal(first.getCell('C2').value,'Aguardando coleta');assert.equal(second.getCell('C2').value,'Coletado');
 assert.equal(first.getCell('D2').value,12.25);assert.equal(first.getCell('D2').numFmt,'#,##0.00');assert.ok(first.getCell('E2').value instanceof Date);
 assert.equal((first.getCell('E2').value as Date).toISOString(),'2026-11-11T22:00:00.000Z');assert.equal(first.getCell('F2').type,ExcelJS.ValueType.String);assert.equal(first.getCell('F2').value,data.cells[0].rows[0].values.serial_number);
 assert.equal(second.getCell('F2').value,'000001');assert.equal(first.getRow(1).font?.bold,undefined);assert.equal(first.getCell('A1').font.bold,true);
 assert.equal(first.views[0].state,'frozen');assert.ok(first.autoFilter);assert.equal(read.creator,'EM · MI Electric Brasil');
 for(const sheet of read.worksheets)sheet.eachRow(row=>row.eachCell(cell=>{assert.equal(typeof cell.value==='object'&&cell.value!==null&&'formula'in cell.value,false);assert.equal(typeof cell.value==='object'&&cell.value!==null&&'hyperlink'in cell.value,false);}));
});
test('streaming writer handles 5000 rows across cells without changing row context or headers',async()=>{
 const data=snapshot();data.cells=Array.from({length:10},(_,c)=>({id:id(c+1),name:`Célula ${c}`,rows:Array.from({length:500},(_,i)=>({allocation_id:id(c*500+i+1000),project_id:id(i+100),values:{project_number:String(i).padStart(6,'0'),cell_name:`Célula ${c}`,allocation_status:'Coletado',planned_hours:i/4,allocation_due:'2026-11-12',serial_number:'S'+i}}))}));data.row_count=5000;
 const bytes=await buildAllocationWorkbook(data);const workbook=new ExcelJS.Workbook();await workbook.xlsx.load(bytes as any);
 assert.equal(workbook.worksheets.length,10);assert.equal(workbook.worksheets.reduce((sum,sheet)=>sum+sheet.rowCount-1,0),5000);assert.equal(workbook.worksheets[9].getCell('A501').value,'000499');
 await assert.rejects(()=>buildAllocationWorkbook(data,AbortSignal.abort()));
});
test('an allocation with all selected fields absent still occupies its own Excel row',async()=>{
 const data:AllocationExportSnapshot={generated_at:'2026-11-12T12:00:00Z',fields:['equipment_type'],row_count:2,complete:true,cells:[{id:id(1),name:'Legados',rows:[
  {allocation_id:id(11),project_id:id(101),values:{equipment_type:null}},
  {allocation_id:id(12),project_id:id(102),values:{equipment_type:null}},
 ]}]};
 const workbook=new ExcelJS.Workbook();await workbook.xlsx.load(await buildAllocationWorkbook(data) as any);
 assert.equal(workbook.worksheets[0].rowCount,3);assert.equal(workbook.worksheets[0].getCell('A2').value,null);assert.equal(workbook.worksheets[0].getCell('A3').value,null);
});
const origin='https://em.example.test';
function request(body:unknown=selection,extra:Record<string,string>={}){return new Request(origin+'/api/web/planning/export',{method:'POST',headers:{Origin:origin,Host:'em.example.test','Content-Type':'application/json',...extra},body:JSON.stringify(body)});}
function access(data=snapshot(),capabilities=allocationExportScopes,perfil='administrador'){return{client:{rpc:async()=>({error:null,data})},user:{id:id(90)},profile:{id:id(91),nome:'Reader',perfil},sso:{sessionHash:'opaque',bindingId:id(92),subject:'opaque',capabilities}} as any;}
test('export HTTP protects origin, session, role and all read scopes before touching data',async()=>{
 let authCalls=0;const getWebUser=async()=>{authCalls++;return access();};
 assert.equal((await handleAllocationExport(request(selection,{Origin:'https://evil.invalid'}),{getWebUser} as any)).status,403);assert.equal(authCalls,0);
 assert.equal((await handleAllocationExport(request(),{getWebUser:async()=>null})).status,401);
 for(const current of [access(undefined,['em.planning.read']),access(undefined,allocationExportScopes,'mobile')])assert.equal((await handleAllocationExport(request(),{getWebUser:async()=>current})).status,403);
});
test('export HTTP validates bounded JSON and sends a no-store XLSX attachment, never raw SQL errors',async()=>{
 const dependencies={getWebUser:async()=>({...access(),sso:undefined})};
 assert.equal((await handleAllocationExport(request({...selection,fields:[]}),dependencies)).status,400);
 assert.equal((await handleAllocationExport(request(selection,{'Content-Type':'text/plain'}),dependencies)).status,415);
 assert.equal((await handleAllocationExport(request(selection,{'Content-Length':'20000'}),dependencies)).status,413);
 const denied=await handleAllocationExport(request(),{getWebUser:async()=>({...access(),sso:undefined,client:{rpc:async()=>({error:{code:'XX000',message:'private JWT SQL'}})}})});
 assert.equal(denied.status,503);assert.doesNotMatch(await denied.text(),/JWT|SQL/);
 const response=await handleAllocationExport(request(),dependencies);assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),allocationExportMime);
 assert.match(response.headers.get('content-disposition')!,/planejamento_alocacoes_2026-11-11\.xlsx/);assert.match(response.headers.get('cache-control')!,/no-store/);assert.equal(response.headers.get('x-content-type-options'),'nosniff');
 assert.equal(Buffer.from(await response.arrayBuffer()).subarray(0,2).toString(),'PK');
});

test('export HTTP does not query legacy SQL when an SSO session is not verified',async()=>{
 const current=access();
 current.client.rpc=async()=>assert.fail('SSO export bypassed workshop authorization');
 const response=await handleAllocationExport(request(),{getWebUser:async()=>current});
 assert.equal(response.status,401);
});
