import { existsSync, mkdirSync, appendFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { bridgeConfig } from '../config';
import { BubbleClient } from './client';
import { Bridge } from './engine';
import { entities, fieldValue, type Entity, type Row } from './mapping';
import { isOperationalProject, scopedGroups } from './scope';

type EntityReport = { table:string; checked:number; loaded:number; unchanged:number; excluded:number; quarantined:number; sampled:boolean; errors:Record<string,number> };
function sanitized(entity:Entity,raw:Row):Row {
  const result:Row={_id:raw._id,'Modified Date':raw['Modified Date']};
  // Never persist unmapped User credentials, CPF, auth blobs or TOTP secrets.
  for(const field of Object.values(entity.fields)){const value=fieldValue(raw,field);if(value!==undefined)result[field.bubble]=value;}
  return result;
}
export async function runEtl() {
  if (existsSync('.env')) process.loadEnvFile('.env');
  const dry = process.argv.includes('--dry-run');
  const scope = process.argv.find(a=>a.startsWith('--scope='))?.slice(8) || 'active';
  if(!['active','all'].includes(scope))throw new Error('--scope deve ser active ou all.');
  const sampleArg=process.argv.find(a=>a.startsWith('--sample='))?.slice(9);
  const sample=sampleArg?Number(sampleArg):Infinity;
  if(sampleArg&&(!dry||!Number.isInteger(sample)||sample<1))throw new Error('--sample exige --dry-run e inteiro positivo.');
  const since = process.argv.find(a => a.startsWith('--since='))?.slice(8) || '1970-01-01T00:00:00.000Z';
  if (!Number.isFinite(Date.parse(since))) throw new Error('--since deve ser uma data ISO valida.');
  const until = new Date().toISOString();
  const reportDirectory=path.resolve('../.tmp/etl',until.replace(/[:.]/g,'-'));
  mkdirSync(reportDirectory,{recursive:true});
  const reportPath=path.join(reportDirectory,'summary.json');
  const report:{startedAt:string;finishedAt?:string;dryRun:boolean;scope:string;sample:number|null;entities:EntityReport[]}={startedAt:until,dryRun:dry,scope,sample:Number.isFinite(sample)?sample:null,entities:[]};
  const saveReport=()=>writeFileSync(reportPath,JSON.stringify(report,null,2));
  const bubble=new BubbleClient(bridgeConfig());const bridge=new Bridge(undefined,bubble);
  const projectIds:string[]=[];const revisionIds:string[]=[];
  await bridge.loadOptions();
  const importer = dry ? null : new (await import('./batch-importer')).BatchImporter(bridge);
  const execute=async()=>{
    if(importer)await importer.preload();
    for(const entity of entities){
      const stats:EntityReport={table:entity.table,checked:0,loaded:0,unchanged:0,excluded:0,quarantined:0,sampled:false,errors:{}};
      report.entities.push(stats);
      const quarantine=(raw:Row,error:Error)=>{
        stats.quarantined++;
        const reason=error.message;
        stats.errors[reason]=(stats.errors[reason]||0)+1;
        appendFileSync(path.join(reportDirectory,'quarantine.jsonl'),JSON.stringify({table:entity.table,bubble_id:raw._id,reason,record:sanitized(entity,raw)})+'\n');
      };
      try {
        const groups=scope==='all'?[[]]:scopedGroups(entity,projectIds,revisionIds);
        outer:for(const constraints of groups)for await(const page of bubble.pages(entity.endpoint,since,until,constraints)){
          const valid:Row[]=[];
          for(const raw of page){
            // Project lists remain complete in preflight to define the real scope.
            if(stats.checked>=sample && entity.table!=='rm_projetos'){stats.sampled=true;break;}
            stats.checked++;
            if(scope==='active'&&entity.table==='rm_projetos'&&!isOperationalProject(raw)){stats.excluded++;continue;}
            try {bridge.validate(entity,raw);valid.push(raw);}catch(error){quarantine(raw,error instanceof Error?error:new Error('Invalid record.'));}
          }
          if(importer&&valid.length){
            const result=await importer.importPage(entity,valid,quarantine);stats.loaded+=result.loaded;stats.unchanged+=result.unchanged;
          }
          for(const raw of valid){
            if(entity.table==='rm_projetos'&&typeof raw._id==='string')projectIds.push(raw._id);
            if(entity.table==='rm_registros_formulario'&&['Revisar','direcionado'].includes(String(raw.Status))&&typeof raw._id==='string')revisionIds.push(raw._id);
          }
          if(stats.sampled)break outer;
        }
        // Worker uses the same active scope and rehydrates reactivated projects.
        if(!dry&&!stats.quarantined)await bridge.rpc('rm_advance_bridge_checkpoint_v1',{p_endpoint:entity.endpoint,p_cursor_at:until});
      }catch(error){const reason=error instanceof Error?error.message:'Endpoint failure';stats.errors[reason]=(stats.errors[reason]||0)+1;}
      saveReport();
      console.info(JSON.stringify({mode:dry?'dry-run':'import',...stats,errors:Object.keys(stats.errors).length}));
    }
  };
  try {if(dry)await execute();else await bridge.withLease(execute);}
  finally {report.finishedAt=new Date().toISOString();saveReport();console.info(`Relatorio local: ${reportPath}`);}
  const failures=report.entities.reduce((sum,e)=>sum+e.quarantined+(Object.keys(e.errors).length?1:0),0);
  if(failures)throw new Error('ETL parcial: registros invalidos em quarentena local; checkpoints dos tipos com erro nao avancaram. Consulte summary.json.');
}
