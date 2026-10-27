import {readFileSync,mkdirSync,writeFileSync,appendFileSync,existsSync} from 'node:fs';
import path from 'node:path';
import {Bridge} from './engine';
import {BatchImporter} from './batch-importer';
import {entities,type Row} from './mapping';

/** Replay the mapped, credential-free records from a previous ETL quarantine.
 * It does not normalize invalid legacy values or advance source checkpoints.
 */
async function main(){
  if(existsSync('.env'))process.loadEnvFile('.env');
  const input=process.argv[2];if(!input)throw new Error('Informe o quarantine.jsonl local de uma carga anterior.');
  const entries=readFileSync(path.resolve(input),'utf8').split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line) as {table:string;record:Row});
  if(entries.some(entry=>!entities.some(entity=>entity.table===entry.table)||!entry.record||typeof entry.record!=='object'))throw new Error('Arquivo de quarentena invalido.');
  const bridge=new Bridge();const startedAt=new Date().toISOString();
  const directory=path.resolve('../.tmp/etl',`${startedAt.replace(/[:.]/g,'-')}-replay`);mkdirSync(directory,{recursive:true});
  const report={startedAt,finishedAt:'',checkpointAdvanced:false,entities:[] as {table:string;checked:number;loaded:number;unchanged:number;quarantined:number}[]};
  try{
    await bridge.withLease(async()=>{
      const importer=new BatchImporter(bridge);await importer.preload();
      for(const entity of entities){
        const rows=entries.filter(entry=>entry.table===entity.table).map(entry=>entry.record);if(!rows.length)continue;
        const stats={table:entity.table,checked:rows.length,loaded:0,unchanged:0,quarantined:0};report.entities.push(stats);
        for(let i=0;i<rows.length;i+=100){
          const result=await importer.importPage(entity,rows.slice(i,i+100),(row,error)=>{
            stats.quarantined++;appendFileSync(path.join(directory,'quarantine.jsonl'),JSON.stringify({table:entity.table,reason:error.message,record:row})+'\n');
          });stats.loaded+=result.loaded;stats.unchanged+=result.unchanged;
        }
        console.info(JSON.stringify(stats));
      }
    });
  }finally{report.finishedAt=new Date().toISOString();writeFileSync(path.join(directory,'summary.json'),JSON.stringify(report,null,2));}
  if(report.entities.some(entity=>entity.quarantined))throw new Error('Replay parcial: registros ainda invalidos permanecem em quarentena local.');
}
main().catch(error=>{console.error(error instanceof Error?error.message:'Falha de replay.');process.exitCode=1;});
