import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Bridge } from '../src/server/bridge/engine';
import { BubbleClient, type Config } from '../src/server/bridge/client';
import { getEntity, fieldUrl, type Row } from '../src/server/bridge/mapping';
import { scopedGroups } from '../src/server/bridge/scope';

const config: Config = {baseUrl:'https://example.invalid/api/1.1',token:'fixture',syncIdField:'supabase_id',webhookAllowlist:[],webhookToken:undefined,endpointOverrides:{}};
test('new local events use their matching Bubble entities without running a worker',async()=>{
  const exported:string[]=[];
  class Fixture extends Bridge {
    override async exportRow(table:string,id:string){exported.push(`${table}/${id}`);return id;}
    override async row():Promise<Row>{return {projeto_id:'project'};}
    override async related(table:string):Promise<Row[]>{assert.equal(table,'rm_celulas_projeto');return [{id:'cell'}];}
  }
  const bridge=new Fixture({} as SupabaseClient,new BubbleClient(config));
  await bridge.processEvent({target_system:'bubble_data_api',entity_type:'Celula_Projeto_Status',record_id:'cell'});
  await bridge.processEvent({target_system:'bubble_data_api',entity_type:'Comentario_Celula',record_id:'comment'});
  await bridge.processEvent({target_system:'bubble_data_api',entity_type:'Aprovacao_Etapa_Transition',record_id:'stage',
    payload:{affected_approval_ids:['stage','reverse'],log_id:'log',comentario_id:'reason'}});
  assert.deepEqual(exported,['rm_celulas_projeto/cell','rm_comentarios/comment','rm_aprovacoes_etapas/stage',
    'rm_aprovacoes_etapas/reverse','rm_celulas_projeto/cell','rm_logs_aprovacao/log','rm_comentarios/reason']);
});
test('documents and comments scope to their actual project fields',()=>{
  for(const [table,field] of [['rm_docs','Projeto_rm'],['rm_documentos','Projeto'],['rm_comentarios','Projeto'],['rm_logs_aprovacao','Projeto_RM']]){
    assert.deepEqual(scopedGroups(getEntity(table),['project'],[]),[[{key:field,constraint_type:'in',value:['project']}]]);
  }
  assert.equal(getEntity('rm_projetos').fields.descricao_equipamento.bubble,'Descricao_Equipamento');
  assert.equal(getEntity('rm_projetos').fields.arquivo_nota_fiscal_url.url,true);
  assert.equal(getEntity('rm_docs').fields.bubble_unique_id.inboundOnly,true);
  const document=getEntity('rm_documentos');
  assert.equal(document.fields.s3_key.bubble,'PDF');
  assert.equal(fieldUrl(document.fields.arquivo_url,'Report archive.pdf'),null);
  assert.equal(fieldUrl(document.fields.arquivo_url,'//cdn.example/report.pdf'),'https://cdn.example/report.pdf');
});
