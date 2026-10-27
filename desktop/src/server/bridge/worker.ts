import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { Bridge } from './engine';

export async function runWorker() {
  if (existsSync('.env')) process.loadEnvFile('.env');
  const once = process.argv.includes('--once');
  let stopping = false;
  process.once('SIGTERM', () => { stopping = true; });
  process.once('SIGINT', () => { stopping = true; });
  const interval = Math.max(5000, Number(process.env.SYNC_POLL_INTERVAL_MS) || 15000);
  do {
    try { const result = await new Bridge().cycle(); console.info(JSON.stringify({ event:'bridge_cycle', ...result })); if (once && (result.outbox.failed || result.inbox.errors.length)) process.exitCode = 1; }
    catch (error) { console.error(JSON.stringify({ event:'bridge_failure', message:error instanceof Error ? error.message : 'falha' })); if (once) process.exitCode = 1; }
    if (!once && !stopping) await new Promise(resolve => setTimeout(resolve, interval));
  } while (!once && !stopping);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) void runWorker();
