import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { BubbleClient, type Config } from '../src/server/bridge/client';
import { Bridge } from '../src/server/bridge/engine';
import { getEntity, normalizeUrl, type Row } from '../src/server/bridge/mapping';
import { allowedWebhook, matchesBearer, readJson } from '../src/server/security';
import { POST as report } from '../src/app/api/reports/generate-pdf/route';

const config: Config = { baseUrl:'https://bubble.example/api/1.1',token:'test',syncIdField:'supabase_id',webhookAllowlist:[],webhookToken:undefined,endpointOverrides:{} };
const json = (body: unknown) => new Response(JSON.stringify(body),{headers:{'Content-Type':'application/json'}});

test('paginated pull follows every cursor and pins the time window',async () => {
  const urls: URL[] = [];
  const client = new BubbleClient(config,async input => {
    const url = new URL(String(input)); urls.push(url);
    return json({response:{results:urls.length===1?[{_id:'one'},{_id:'two'}]:[{_id:'three'}],remaining:urls.length===1?1:0}});
  });
  const rows: Row[]=[]; for await (const page of client.pages('form','2026-01-01','2026-01-02')) rows.push(...page);
  assert.equal(rows.length,3); assert.equal(urls[1].searchParams.get('cursor'),'2');
  assert.deepEqual(JSON.parse(urls[1].searchParams.get('constraints')!)[1],{key:'Modified Date',constraint_type:'less than',value:'2026-01-02'});
});
test('malformed nonadvancing page fails instead of silently advancing checkpoint',async () => {
  const client = new BubbleClient(config,async()=>json({response:{results:[],remaining:8}}));
  await assert.rejects(async()=>{for await(const page of client.pages('form','a','b')) void page;},/sem progresso/);
});
test('ambiguous create is reconciled by stable UUID before retry',async () => {
  let created=false; const methods:string[]=[];
  const client = new BubbleClient(config,async (_input,init) => {
    methods.push(init?.method || 'GET');
    if (!init?.method) return json({response:{results:created?[{_id:'remote'}]:[]}});
    if (init.method==='POST') {created=true; throw new Error('response lost');}
    return new Response(null,{status:204});
  });
  await assert.rejects(client.write('form',null,'uuid',{Titulo:'A'}),/response lost/);
  assert.equal(await client.write('form',null,'uuid',{Titulo:'A'}),'remote');
  assert.deepEqual(methods,['GET','POST','GET','PATCH']);
});
test('duplicate reconciliation key refuses to pick arbitrary Bubble row',async()=>{
  const client=new BubbleClient(config,async()=>json({response:{results:[{_id:'a'},{_id:'b'}]}}));
  await assert.rejects(client.write('form',null,'uuid',{}),/duplicada/);
});
test('unexpected outbox target is a failure and cannot be acknowledged complete',async()=>{
  const finished: Row[]=[];let claimed=false;
  const db={rpc:async(name:string,args:Row)=>{
    if(name==='rm_claim_sync_events_v1'){const data=claimed?[]:[{id:1,record_id:'record',target_system:'bubble_data_api',entity_type:'unknown'}];claimed=true;return {data,error:null};}
    if(name==='rm_finish_sync_event_v1'){finished.push(args);return {data:true,error:null};}
    throw new Error(name);
  }} as unknown as SupabaseClient;
  const result=await new Bridge(db,new BubbleClient(config)).outbox();
  assert.deepEqual(result,{completed:0,failed:1});assert.match(String(finished[0].p_error),/não suportado/);
});
test('read-only bridge mode never invokes outbox until explicitly enabled',async()=>{
  const old=process.env.SYNC_OUTBOX_ENABLED; delete process.env.SYNC_OUTBOX_ENABLED;
  let sends=0;
  class ReadOnlyFixture extends Bridge {
    override async withLease<T>(run:()=>Promise<T>){return run();}
    override async outbox(){sends++;return {completed:1,failed:0};}
    override async pull(){return {imported:0,errors:[]};}
  }
  try {
    const bridge=new ReadOnlyFixture({} as SupabaseClient,new BubbleClient(config));
    assert.equal((await bridge.cycle()).outbox.completed,0);assert.equal(sends,0);
    process.env.SYNC_OUTBOX_ENABLED='true';await bridge.cycle();assert.equal(sends,1);
  } finally {if(old===undefined)delete process.env.SYNC_OUTBOX_ENABLED;else process.env.SYNC_OUTBOX_ENABLED=old;}
});
test('receipt bundle exports equipment and every photo after the project',async()=>{
  const writes:string[]=[];
  class Fixture extends Bridge {
    override async exportRow(table:string,id:string){writes.push(`${table}/${id}`);return `remote-${id}`;}
    override async related(table:string){return table==='rm_equipamentos'?[{id:'eq'}]:[{id:'photo1'},{id:'photo2'}];}
  }
  const client=new BubbleClient(config,async()=>new Response(null,{status:204}));
  await new Fixture({} as SupabaseClient,client).processEvent({target_system:'bubble_data_api',entity_type:'Recebimento_Bundle',record_id:'project'});
  assert.deepEqual(writes,['rm_projetos/project','rm_equipamentos/eq','rm_fotos/photo1','rm_fotos/photo2']);
});
test('form bundle patches its Bubble answer list after individual exports',async()=>{
  let finalBody:Row={};
  class Fixture extends Bridge {
    override async exportRow(_table:string,id:string){return `remote-${id}`;}
    override async related(){return [{id:'answer1'},{id:'answer2'}];}
  }
  const client=new BubbleClient(config,async(_url,init)=>{finalBody=JSON.parse(String(init?.body));return new Response(null,{status:204});});
  await new Fixture({} as SupabaseClient,client).processEvent({target_system:'bubble_data_api',entity_type:'Registro_Formulario_Revision',record_id:'record'});
  assert.deepEqual(finalBody.Respostas,['remote-answer1','remote-answer2']);
});
test('private secrets fail closed and webhook URLs require exact HTTPS allowlist',()=>{
  assert.equal(matchesBearer('Bearer '+ 'x'.repeat(32),'x'.repeat(32)),true);
  assert.equal(matchesBearer('Bearer short','short'),false);
  assert.equal(matchesBearer(null,undefined),false);
  assert.equal(allowedWebhook('https://hooks.example/path',['https://hooks.example/path']),true);
  assert.equal(allowedWebhook('https://hooks.example/path/evil',['https://hooks.example/path']),false);
  assert.equal(allowedWebhook('http://localhost/admin',['http://localhost/admin']),false);
});
test('streamed JSON enforces body cap without trusting Content-Length',async()=>{
  const request=new Request('https://local',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({large:'x'.repeat(100)})});
  await assert.rejects(readJson(request,32),/limite/);
});
test('future report route returns 401 or explicit 501, never fake success',async()=>{
  const old=process.env.INTERNAL_API_SECRET; process.env.INTERNAL_API_SECRET='z'.repeat(32);
  try {
    assert.equal(report(new Request('https://local',{method:'POST'})).status,401);
    assert.equal(report(new Request('https://local',{method:'POST',headers:{Authorization:'Bearer '+'z'.repeat(32)}})).status,501);
  } finally { if(old===undefined) delete process.env.INTERNAL_API_SECRET;else process.env.INTERNAL_API_SECRET=old; }
});
test('canonical slugs and protocol-relative media are preserved',()=>{
  assert.equal(getEntity('Questoes').fields.tipo.option,'tipo_quest_o');
  assert.equal(getEntity('Respostas').fields.itens_questoes_ids.bubble,'Itens Questoes');
  assert.equal(normalizeUrl('//cdn.example/photo.jpg'),'https://cdn.example/photo.jpg');
  assert.throws(()=>normalizeUrl('file:///secret'),/HTTP/);
});
