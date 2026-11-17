import { readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { workshopScopeInventory } from '../../desktop/src/server/bridge/workshop-inventory';

try {
  const [input, output, ...extra] = process.argv.slice(2);
  if (!input || !output || extra.length) throw new Error();
  const source = path.resolve(input), target = path.resolve(output);
  if (source.toLowerCase() === target.toLowerCase() || statSync(source).size > 8 * 1024 * 1024) throw new Error();
  const report = workshopScopeInventory(JSON.parse(readFileSync(source, 'utf8').replace(/^\uFEFF/, '')));
  // A report must not replace a previous inventory or any user file.
  writeFileSync(target, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  console.info(JSON.stringify({ ...report.totals, isolation_proven: false }));
} catch {
  console.error('Não foi possível gerar o inventário. Use: tsx prepare_workshop_inventory.ts metadados.json novo-relatorio.json. Nenhum acesso ou oficina foi concedido.');
  process.exitCode = 1;
}
