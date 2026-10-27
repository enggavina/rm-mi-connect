import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

async function main() {
const port = 3199;
const origin = `http://127.0.0.1:${port}`;
const secret = 'local-smoke-token-for-phase-two-route';
const server = spawn(process.execPath, ['.next/standalone/server.js'], {
  windowsHide: true, stdio: ['ignore','pipe','pipe'],
  env: { ...process.env, PORT:String(port),HOSTNAME:'127.0.0.1',INTERNAL_API_SECRET:secret },
});
let diagnostics = '';
server.stdout.on('data', value => { diagnostics += String(value); });
server.stderr.on('data', value => { diagnostics += String(value); });
try {
  let ready = false;
  for (let i=0;i<60;i++) {
    if (server.exitCode !== null) throw new Error('Servidor encerrou antes do smoke test.');
    try { const response = await fetch(`${origin}/api/health`); ready=response.ok; } catch {}
    if (ready) break;
    await new Promise(resolve=>setTimeout(resolve,500));
  }
  assert.equal(ready,true,'Servidor não iniciou em 30 segundos.');
  const health = await fetch(`${origin}/api/health`); assert.equal(health.status,200); assert.equal((await health.json()).status,'ok');
  const home = await fetch(origin); assert.equal(home.status,200); assert.match(await home.text(),/A operação continua/);
  for (const path of ['/api/webhooks/bubble','/api/sync/run','/api/reports/generate-pdf','/api/reports/compile-s3','/api/auth/totp']) {
    const denied = await fetch(origin+path,{method:'POST'}); assert.equal(denied.status,401,path);
  }
  for (const path of ['/api/reports/generate-pdf','/api/reports/compile-s3','/api/auth/totp']) {
    const reserved=await fetch(origin+path,{method:'POST',headers:{Authorization:`Bearer ${secret}`}}); assert.equal(reserved.status,501,path);
  }
  console.info('Runtime smoke: home/health 200, 5 protected routes 401, 3 phase-two routes 501.');
} catch (error) { console.error('Smoke falhou. Saída do processo:',diagnostics); throw error; }
finally { server.kill(); }
}
void main().catch(error=>{ console.error(error); process.exitCode=1; });
