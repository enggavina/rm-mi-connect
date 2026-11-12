import test from 'node:test';
import assert from 'node:assert/strict';
import {allocationExportRequest,fetchAllocationExport,type AllocationExportField} from '../src/components/web/allocation-export-model';

const id=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const cells=[{id:id(1),nome:'Montagem'},{id:id(2),nome:'Testes'},{id:id(3),nome:'Pintura'}];
const fields:AllocationExportField[]=[{key:'project_number',label:'Número do projeto',group:'project'},{key:'equipment_type',label:'Tipo de equipamento',group:'equipment'},{key:'allocation_status',label:'Status da célula',group:'allocation'}];
const mime='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

test('export selection requires cells and information and preserves each selected cell context',()=>{
  assert.throws(()=>allocationExportRequest([],['project_number'],cells,fields),/pelo menos uma célula/);
  assert.throws(()=>allocationExportRequest([id(1)],[],cells,fields),/pelo menos uma informação/);
  for(const selected of [[id(1),id(1)],['unknown']])assert.throws(()=>allocationExportRequest(selected,['project_number'],cells,fields),/Confira as células/);
  for(const selected of [['project_number','project_number'],['uuid']])assert.throws(()=>allocationExportRequest([id(1)],selected,cells,fields),/Confira as informações/);
  const input=allocationExportRequest([id(2),id(1)],['allocation_status','project_number'],cells,fields);
  assert.deepEqual(input,{cell_ids:[id(1),id(2)],fields:['project_number','allocation_status']});
  assert.ok(!input.cell_ids.includes(id(3)));assert.ok(!input.fields.includes('equipment_type'));
  const tooMany=Array.from({length:201},(_,i)=>({id:id(i+1),nome:`Célula ${i+1}`}));
  assert.throws(()=>allocationExportRequest(tooMany.map(cell=>cell.id),['project_number'],tooMany,fields),/máximo 200 células/);
});

test('download posts only selected IDs and fields to the same-origin server without business rows',async()=>{
  const input=allocationExportRequest([id(1),id(2)],fields.map(field=>field.key),cells,fields),controller=new AbortController();
  const calls:{url:unknown;init:RequestInit|undefined}[]=[];
  const file=await fetchAllocationExport(input,controller.signal,(async(url,init)=>{calls.push({url,init});return new Response(new Uint8Array([80,75,3,4]),{headers:{'Content-Type':mime,'Content-Disposition':'attachment; filename="planejamento_alocacoes_2026-11-12.xlsx"'}});}) as typeof fetch);
  assert.equal(file.filename,'planejamento_alocacoes_2026-11-12.xlsx');assert.equal(file.blob.size,4);
  assert.equal(calls.length,1);assert.equal(calls[0].url,'/api/web/planning/export');
  assert.equal(calls[0].init?.method,'POST');assert.equal(calls[0].init?.credentials,'same-origin');assert.equal(calls[0].init?.mode,'same-origin');
  assert.equal(calls[0].init?.redirect,'error');assert.equal(calls[0].init?.cache,'no-store');assert.equal(calls[0].init?.signal,controller.signal);
  assert.deepEqual(JSON.parse(calls[0].init?.body as string),input);
});

test('download never treats login, API errors, wrong formats or empty responses as workbooks',async()=>{
  const input={cell_ids:[id(1)],fields:['project_number' as const]},signal=new AbortController().signal;
  const responses=[
    {status:401,error:'private authentication details',message:/sessão expirou/},
    {status:403,error:'private policy details',message:/não tem permissão/},
    {status:422,error:'Selecione uma célula permitida.',message:/Selecione uma célula permitida/},
    {status:500,error:'private SQL details',message:/Não foi possível gerar/},
  ];
  for(const row of responses)await assert.rejects(fetchAllocationExport(input,signal,(async()=>new Response(JSON.stringify({error:row.error}),{status:row.status,headers:{'Content-Type':'application/json'}})) as typeof fetch),row.message);
  for(const response of [new Response('<html>login</html>',{headers:{'Content-Type':'text/html'}}),new Response('',{headers:{'Content-Type':mime}})]){
    await assert.rejects(fetchAllocationExport(input,signal,(async()=>response) as typeof fetch),/arquivo Excel/);
  }
});

test('download filenames cannot introduce paths or a different file type',async()=>{
  const input={cell_ids:[id(1)],fields:['project_number' as const]},signal=new AbortController().signal;
  for(const disposition of ['attachment; filename="../../private.html"','attachment; filename="export.xls"',"attachment; filename*=UTF-8''..%2F..%2Fscript.html"]){
    const file=await fetchAllocationExport(input,signal,(async()=>new Response('PK',{headers:{'Content-Type':mime,'Content-Disposition':disposition}})) as typeof fetch);
    assert.equal(file.filename,'planejamento_alocacoes.xlsx');
  }
  const filename=await fetchAllocationExport(input,signal,(async()=>new Response('PK',{headers:{'Content-Type':mime,'Content-Disposition':"attachment; filename*=UTF-8''planejamento_alocacoes_2026-11-12.xlsx"}})) as typeof fetch);
  assert.equal(filename.filename,'planejamento_alocacoes_2026-11-12.xlsx');
});
