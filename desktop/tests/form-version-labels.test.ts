import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { withFormVersionLabels } from '../src/server/web/form-version-labels';
const id=(n:number)=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
test('version labels distinguish the same model name without changing IDs, stored titles or adopting a version',async()=>{
  const forms=[{id:id(1),titulo:'Inspeção'},{id:id(2),titulo:'Inspeção'},{id:id(3),titulo:'Outro legado'},{id:id(4),missing:true,titulo:'Referência ausente'}];
  const original=structuredClone(forms),calls:unknown[]=[];
  const client={from(table:string){assert.equal(table,'rm_form_template_versions');return {select(columns:string){assert.equal(columns,'form_id,version');return this;},
    in(column:string,values:string[]){assert.equal(column,'form_id');calls.push(values);return this;},async order(column:string){assert.equal(column,'form_id');return {error:null,data:[{form_id:id(1),version:1},{form_id:id(2),version:2},{form_id:id(99),version:8}]};}};}} as unknown as SupabaseClient;
  const rows=await withFormVersionLabels(client,forms);
  assert.deepEqual(forms,original);assert.deepEqual(rows.map(r=>r.id),forms.map(r=>r.id));
  assert.deepEqual(rows.map(r=>r.titulo),['Inspeção · v1','Inspeção · v2','Outro legado','Referência ausente']);
  assert.equal(rows[1].titulo_modelo,'Inspeção');assert.equal(rows[1].versao_modelo,2);
  assert.deepEqual(calls,[[id(1),id(2),id(3)]]);
});
test('version lookup is bounded to referenced IDs and an empty or missing-only list performs no queries',async()=>{
  let calls=0;
  const client={from(){calls++;return {select(){return this;},in(_key:string,ids:string[]){assert.ok(ids.length<=100);return this;},async order(){return {error:null,data:[]};}};}} as unknown as SupabaseClient;
  await withFormVersionLabels(client,[]);await withFormVersionLabels(client,[{id:id(1),missing:true}]);assert.equal(calls,0);
  const forms=Array.from({length:231},(_,n)=>({id:id(n+1),titulo:'Legado'}));
  assert.deepEqual(await withFormVersionLabels(client,forms),forms);assert.equal(calls,3);
});
