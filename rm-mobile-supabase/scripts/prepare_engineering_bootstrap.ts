import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { engineeringBootstrapSql, prepareEngineeringBootstrap } from '../../desktop/src/server/bridge/engineering-bootstrap';

const [sourcePath,lookupPath,outputPath]=process.argv.slice(2);
if(!sourcePath||!lookupPath||!outputPath)throw Error('Usage: tsx prepare_engineering_bootstrap.ts source.json lookups.json output-directory');
const plan=prepareEngineeringBootstrap(JSON.parse(readFileSync(path.resolve(sourcePath),'utf8')),
  JSON.parse(readFileSync(path.resolve(lookupPath),'utf8')));
const out=path.resolve(outputPath);mkdirSync(out,{recursive:true});
writeFileSync(path.join(out,'plan.json'),JSON.stringify(plan,null,2));
for(const [index,group]of plan.groups.entries()){
  const name=String(index+1).padStart(3,'0')+'-'+group.parent.id;
  writeFileSync(path.join(out,name+'.rehearsal.sql'),engineeringBootstrapSql(group));
  writeFileSync(path.join(out,name+'.apply.sql'),engineeringBootstrapSql(group,true));
}
console.info(JSON.stringify({version:plan.version,sourceHash:plan.sourceHash,cutoff:plan.cutoff,...plan.counts,mode:'prepared-only; rehearsal SQL rolls back; apply SQL is explicit insert-only'}));
