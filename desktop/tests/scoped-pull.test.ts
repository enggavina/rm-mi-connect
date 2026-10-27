import test from 'node:test';
import assert from 'node:assert/strict';
import type {SupabaseClient} from '@supabase/supabase-js';
import {Bridge} from '../src/server/bridge/engine';
import {BubbleClient,type Constraint} from '../src/server/bridge/client';
import {entities,type Entity,type Row} from '../src/server/bridge/mapping';
import {isOperationalProject} from '../src/server/bridge/scope';

const cursor='2026-01-02T00:00:00.000Z';
const modified='2026-01-03T00:00:00.000Z';
function fixture(rows:Record<string,Row[]>,projects:Row[]=[],records:Row[]=[]){
  const requests:{endpoint:string;since:string;constraints:Constraint[]}[]=[];
  const applied:string[]=[];const advanced:string[]=[];
  class Source extends BubbleClient {
    override async *pages(endpoint:string,since:string,_until:string,constraints:Constraint[]=[]){
      requests.push({endpoint,since,constraints});
      yield rows[endpoint]||[];
    }
  }
  const db={from:()=>({select:()=>({data:entities.map(e=>({endpoint:e.endpoint,cursor_at:cursor})),error:null})})} as unknown as SupabaseClient;
  class Worker extends Bridge {
    override async sourceRows(table:string){return table==='rm_projetos'?projects:records;}
    override async apply(entity:Entity,raw:Row){
      if(raw.invalid)throw new Error('invalid legacy record');
      applied.push(`${entity.endpoint}/${raw._id}`);return `local-${raw._id}`;
    }
    override async rpc(_name:string,args:Row){advanced.push(String(args.p_endpoint));return true;}
  }
  const bubble=new Source({baseUrl:'https://example.invalid/api/1.1',token:'test',syncIdField:'supabase_id',webhookAllowlist:[],webhookToken:undefined,endpointOverrides:{}});
  return {bridge:new Worker(db,bubble),requests,applied,advanced};
}
test('invalid legacy records do not block later valid records or advance their checkpoint',async()=>{
  const f=fixture({questoes:[{_id:'bad',invalid:true},{_id:'good'}]});
  const result=await f.bridge.pull();
  assert.ok(f.applied.includes('questoes/good'));
  assert.equal(f.advanced.includes('questoes'),false);
  assert.ok(f.advanced.includes('form'));
  assert.match(result.errors[0],/invalid legacy record/);
});
test('terminal project updates apply before child scope excludes them',async()=>{
  const f=fixture({projetorm:[
    {_id:'existing','Status PCP':'Finalizado para faturar','Modified Date':modified},
    {_id:'historical','Status PCP':'Cancelado','Modified Date':modified},
  ]},[{id:'local-existing',bubble_id:'existing',status_pcp:'executando'}]);
  await f.bridge.pull();
  assert.ok(f.applied.includes('projetorm/existing'));
  assert.equal(f.applied.includes('projetorm/historical'),false);
  assert.equal(f.requests.some(r=>r.endpoint==='fotosrm'),false);
});
test('reactivation hydrates old children and revision answers stay bounded',async()=>{
  const f=fixture({projetorm:[{_id:'active','Modified Date':modified}]},
    [{id:'local-active',bubble_id:'active',status_pcp:'cancelado'}],
    [{id:'reg',bubble_id:'revision',projeto_id:'local-active',status:'direcionado'},
      {id:'old',bubble_id:'approved',projeto_id:'local-active',status:'aprovado'}]);
  await f.bridge.pull();
  const photos=f.requests.find(r=>r.endpoint==='fotosrm')!;
  assert.equal(photos.since,'1970-01-01T00:00:00.000Z');
  assert.deepEqual(photos.constraints,[{key:'ProjetoRM',constraint_type:'in',value:['active']}]);
  const answers=f.requests.filter(r=>r.endpoint==='respostas');
  assert.equal(answers.length,1);
  assert.equal(answers[0].since,'1970-01-01T00:00:00.000Z');
  assert.deepEqual(answers[0].constraints,[{key:'Registro_Formulario',constraint_type:'in',value:['revision']}]);
});
test('operational scope preserves NULL status and excludes delivery or terminal states',()=>{
  assert.equal(isOperationalProject({status_pcp:null}),true);
  assert.equal(isOperationalProject({status_pcp:'finalizando_para_faturar'}),false);
  assert.equal(isOperationalProject({'Data Real de Entrega':'2026-01-01'}),false);
});
