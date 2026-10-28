/** Bounded inbox backfill for projects already installed in EM.
 * Bubble is GET-only. No worker, outbound event, account or synthetic data is created.
 * Run from repository root: node desktop/node_modules/tsx/dist/cli.mjs
 *   rm-mobile-supabase/scripts/import_mobile_history.ts [--apply]
 */
import { mkdirSync, writeFileSync, appendFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { Bridge } from '../../desktop/src/server/bridge/engine';
import { BubbleClient } from '../../desktop/src/server/bridge/client';
import { bridgeConfig } from '../../desktop/src/server/config';
import { BatchImporter } from '../../desktop/src/server/bridge/batch-importer';
import { getEntity, fieldValue, type Row } from '../../desktop/src/server/bridge/mapping';
import { chunkIds, isOperationalProject, scopedGroups } from '../../desktop/src/server/bridge/scope';

async function main() {
  process.loadEnvFile('desktop/.env');
  if(new URL(process.env.SUPABASE_URL!).hostname!=='ellpxfbsrbhblyizvbbk.supabase.co')throw new Error('Unexpected destination project.');
  const apply=process.argv.includes('--apply');
  const replayArg=process.argv.find(value=>value.startsWith('--replay-from='))?.slice(14);
  const replay=new Map<string,string[]>();
  if(replayArg){
    const source=path.resolve(replayArg),prefix=path.resolve('.tmp/etl')+path.sep;
    if(!source.startsWith(prefix))throw new Error('Replay source must be a report directory within .tmp/etl.');
    for(const line of readFileSync(path.join(source,'quarantine.jsonl'),'utf8').split(/\r?\n/).filter(Boolean)){
      const entry=JSON.parse(line);
      if(!['rm_documentos','rm_respostas'].includes(entry.table)||typeof entry.bubble_id!=='string')throw new Error('Unexpected replay metadata.');
      replay.set(entry.table,[...(replay.get(entry.table)||[]),entry.bubble_id]);
    }
  }
  const until=new Date().toISOString();
  const directory=`.tmp/etl/${until.replace(/[:.]/g,'-')}-mobile-history`;
  mkdirSync(directory,{recursive:true});
  const report={startedAt:until,finishedAt:'',apply,projectCount:0,recordCount:0,entities:[] as Row[]};
  const save=()=>writeFileSync(`${directory}/summary.json`,JSON.stringify(report,null,2));
  const readOnlyFetch:typeof fetch=(input,init)=>{
    if(init?.method && init.method!=='GET')throw new Error('This backfill permits only GET requests to Bubble.');
    return fetch(input,init);
  };
  const bridge=new Bridge(undefined,new BubbleClient(bridgeConfig(),readOnlyFetch));
  const projects=(await bridge.sourceRows('rm_projetos','id,bubble_id,status_pcp,data_real_de_entrega'))
    .filter(row=>row.bubble_id&&isOperationalProject(row));
  const projectIds=projects.map(row=>String(row.bubble_id));
  const localProjects=new Set(projects.map(row=>String(row.id)));
  const records=(await bridge.sourceRows('rm_registros_formulario','id,bubble_id,projeto_id'))
    .filter(row=>row.bubble_id&&localProjects.has(String(row.projeto_id)));
  report.projectCount=projects.length;report.recordCount=records.length;save();
  const execute=async()=>{
    const importer=new BatchImporter(bridge);await importer.preload();
    // Existing project rows may have the same Bubble timestamp: enrich only fields
    // previously unmapped, without resetting timestamps or replaying local changes.
    const projectEntity=getEntity('rm_projetos');
    const details=['descricao_equipamento','arquivo_nota_fiscal_url','documento_proposta_url','nome_parceiro',
      'descricao_cod_escopo','descricao_status_relatorio','centro_de_resultado','unidade_de_negocio_bu','bid_date',
      'prazo_execucao','data_nota_entrada','data_inicio_delineamento','data_final_delineamento',
      'data_envio_para_comercial','data_renegociada','estimado','new_offer','replanejamento_motivo','gestor_responsavel_id'];
    const projectReport={table:'rm_projetos',checked:0,loaded:0,quarantined:0};report.entities.push(projectReport);
    for(const ids of (replayArg?[]:chunkIds(projectIds)))for await(const page of bridge.bubble.pages('projetorm','1970-01-01T00:00:00Z',until,[{key:'_id',constraint_type:'in',value:ids}])){
      for(const raw of page){
        projectReport.checked++;
        const local=projects.find(row=>row.bubble_id===raw._id)!;
        if(!apply)continue; // Translating a missing FK may import its dependency.
        const pending=await bridge.db.from('rm_sync_outbox').select('id').eq('record_id',local.id).neq('status','completed').limit(1);
        if(pending.error)throw new Error('Unable to verify pending project edits.');
        if(pending.data?.length){projectReport.quarantined++;continue;}
        const patch:Row={};
        for(const key of details){const field=projectEntity.fields[key],value=fieldValue(raw,field);if(value!==undefined)patch[key]=await bridge.translate(field,value);}
        if(Object.keys(patch).length&&apply){const result=await bridge.db.from('rm_projetos').update(patch).eq('id',local.id);if(result.error)throw new Error(result.error.message);projectReport.loaded++;}
      }
    }
    save();console.info(JSON.stringify(projectReport));
    for(const table of ['rm_cadastro_fotos','rm_comentarios','rm_logs_aprovacao','rm_docs','rm_documentos','rm_respostas']){
      if(replayArg&&!replay.has(table))continue;
      const entity=getEntity(table),stats={table,checked:0,loaded:0,unchanged:0,quarantined:0,errors:{} as Record<string,number>};
      report.entities.push(stats);
      const quarantine=(raw:Row,error:Error)=>{
        stats.quarantined++;stats.errors[error.message]=(stats.errors[error.message]||0)+1;
        appendFileSync(`${directory}/quarantine.jsonl`,JSON.stringify({table,bubble_id:raw._id,reason:error.message})+'\n');
      };
      const recordIds=records.map(row=>String(row.bubble_id));
      const groups=replayArg?chunkIds([...new Set(replay.get(table))]).map(ids=>[{key:'_id',constraint_type:'in',value:ids}])
        :scopedGroups(entity,projectIds,recordIds);
      for(const constraints of groups){
        for await(const page of bridge.bubble.pages(entity.endpoint,'1970-01-01T00:00:00Z',until,constraints)){
          if(replayArg&&page.some(raw=>table==='rm_respostas'?!recordIds.includes(String(raw.Registro_Formulario)):!projectIds.includes(String(raw.Projeto))))throw new Error('Replayed record moved outside the authorized project scope.');
          stats.checked+=page.length;
          if(apply){const result=await importer.importPage(entity,page,quarantine);stats.loaded+=result.loaded;stats.unchanged+=result.unchanged;}
          else for(const raw of page){try{bridge.validate(entity,raw);}catch(error){quarantine(raw,error instanceof Error?error:new Error('Invalid record'));}}
          save();
        }
      }
      console.info(JSON.stringify({...stats,errors:Object.keys(stats.errors).length}));save();
    }
  };
  try{if(apply)await bridge.withLease(execute);else await execute();}
  finally{report.finishedAt=new Date().toISOString();save();console.info(`Aggregate report: ${directory}/summary.json`);}
}
main().catch(error=>{console.error(error instanceof Error?error.message:'Mobile history import failed');process.exitCode=1;});
