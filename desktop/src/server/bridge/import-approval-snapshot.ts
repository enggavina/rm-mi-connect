import {readFileSync,mkdirSync,writeFileSync,appendFileSync,existsSync} from 'node:fs';
import path from 'node:path';
import {Bridge} from './engine';
import {BatchImporter} from './batch-importer';
import {getEntity,type Row} from './mapping';
import {isOperationalProject} from './scope';

/** One-time fallback for an authorized, read-only Bubble connector export.
 * This never advances the public Data API checkpoint or enables outbox delivery.
 */
async function main(){
  if(existsSync('.env'))process.loadEnvFile('.env');
  const input=process.argv[2];if(!input)throw new Error('Informe o JSON local exportado pelo conector Bubble live.');
  const raw:unknown=JSON.parse(readFileSync(path.resolve(input),'utf8'));
  if(!Array.isArray(raw)||raw.some(row=>!row||typeof row!=='object'||Array.isArray(row)))throw new Error('Snapshot deve ser uma lista de registros.');
  const rows=raw as Row[];const bridge=new Bridge();const entity=getEntity('rm_aprovacoes_etapas');
  const startedAt=new Date().toISOString();
  const directory=path.resolve('../.tmp/etl',`${startedAt.replace(/[:.]/g,'-')}-approval-snapshot`);mkdirSync(directory,{recursive:true});
  const report={source:'Bubble connector live snapshot',startedAt,finishedAt:'',sourceRecords:rows.length,selected:0,loaded:0,unchanged:0,quarantined:0,checkpointAdvanced:false,errors:{} as Record<string,number>};
  try{
    await bridge.withLease(async()=>{
      const projects=await bridge.sourceRows('rm_projetos','id,bubble_id,status_pcp,data_real_de_entrega');
      const active=new Set(projects.filter(row=>row.bubble_id&&isOperationalProject(row)).map(row=>String(row.bubble_id)));
      const selected=rows.filter(row=>typeof row.ProjetoRM==='string'&&active.has(row.ProjetoRM));report.selected=selected.length;
      const importer=new BatchImporter(bridge);await importer.preload();
      for(let i=0;i<selected.length;i+=100){
        const result=await importer.importPage(entity,selected.slice(i,i+100),(row,error)=>{
          report.quarantined++;report.errors[error.message]=(report.errors[error.message]||0)+1;
          appendFileSync(path.join(directory,'quarantine.jsonl'),JSON.stringify({table:entity.table,reason:error.message,record:row})+'\n');
        });report.loaded+=result.loaded;report.unchanged+=result.unchanged;
      }
    });
  }finally{
    report.finishedAt=new Date().toISOString();writeFileSync(path.join(directory,'summary.json'),JSON.stringify(report,null,2));
    console.info(JSON.stringify({...report,errors:Object.keys(report.errors).length}));
  }
  if(report.quarantined)throw new Error('Snapshot parcial: consulte a quarentena local.');
}
main().catch(error=>{console.error(error instanceof Error?error.message:'Falha de snapshot.');process.exitCode=1;});
