import { readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { workshopAdoptionPlan } from '../../desktop/src/server/bridge/workshop-adoption';

try {
  const [metadata, declaration, output, ...extra] = process.argv.slice(2);
  if (!metadata || !declaration || !output || extra.length) throw new Error();
  const sources = [metadata, declaration].map(file => path.resolve(file)), target = path.resolve(output);
  if (sources.some(file => file.toLowerCase() === target.toLowerCase() || statSync(file).size > 8 * 1024 * 1024)) throw new Error();
  const [inventory, confirmed] = sources.map(file => JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, '')));
  const plan = workshopAdoptionPlan(inventory, confirmed);
  writeFileSync(target, JSON.stringify(plan, null, 2) + '\n', { flag: 'wx' });
  console.info(JSON.stringify({ ...plan.totals, legacy_workshop_code: plan.legacy_workshop_code,
    workshops: plan.workshops.map(item => item.code), central_registration_verified: false, activation_ready: false }));
} catch {
  console.error('Use: tsx prepare_workshop_adoption.ts metadados.json declaracao.json novo-plano.json. Nenhum SQL, vínculo ou acesso é executado; arquivos existentes não são substituídos.');
  process.exitCode = 1;
}
