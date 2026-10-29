import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { cpSync, existsSync } from 'node:fs';
import { createServer } from 'node:net';
import assert from 'node:assert/strict';

async function main() {
  const port = 3199, origin = `http://127.0.0.1:${port}`;
  const secret = randomBytes(32).toString('hex');
  assert.ok(existsSync('.next/standalone/server.js'), 'Execute npm run build antes de npm run test:smoke.');
  // Match the Docker image: Next's standalone output does not include these assets itself.
  cpSync('public', '.next/standalone/public', { recursive: true });
  cpSync('.next/static', '.next/standalone/.next/static', { recursive: true });
  await new Promise<void>((resolve, reject) => {
    const probe = createServer(); probe.once('error', reject);
    probe.listen(port, '127.0.0.1', () => probe.close(error => error ? reject(error) : resolve()));
  });
  const env = { ...process.env };
  for (const name of Object.keys(env)) if (/SUPABASE|BUBBLE|WEBHOOK|N8N/.test(name)) env[name] = '';
  // Empty values are deliberate: deleting them would let Next load real values from a traced .env.
  Object.assign(env, {
    NODE_ENV: 'production', PORT: String(port), HOSTNAME: '127.0.0.1', INTERNAL_API_SECRET: secret,
    SUPABASE_URL: '', SUPABASE_ANON_KEY: '', SUPABASE_SERVICE_ROLE_KEY: '',
    NEXT_PUBLIC_SUPABASE_URL: '', NEXT_PUBLIC_SUPABASE_ANON_KEY: '', NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: '',
    BUBBLE_API_BASE_URL: '', BUBBLE_API_TOKEN: '', BUBBLE_WEBHOOK_SECRET: '', SYNC_OUTBOX_ENABLED: 'false',
  });
  const server = spawn(process.execPath, ['.next/standalone/server.js'], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env });
  let diagnostics = '', launchError: Error | undefined;
  server.once('error', error => { launchError = error; });
  const capture = (value: Buffer) => { diagnostics = (diagnostics + String(value)).slice(-16_000); };
  server.stdout.on('data', capture); server.stderr.on('data', capture);
  const request = (path: string, init: RequestInit = {}) => fetch(origin + path, { ...init, redirect: 'manual', signal: init.signal ?? AbortSignal.timeout(10_000) });
  try {
    let ready = false;
    const deadline = Date.now() + 30_000;
    while (Date.now() < deadline) {
      if (launchError) throw launchError;
      if (server.exitCode !== null) throw new Error('Servidor encerrou antes do smoke test.');
      try { ready = (await request('/api/health', { signal: AbortSignal.timeout(1000) })).ok; } catch {}
      if (ready) break;
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    assert.equal(ready, true, 'Servidor não iniciou em 30 segundos.');
    const health = await request('/api/health');
    assert.equal(health.status, 200); assert.equal((await health.json()).status, 'ok');

    const login = await request('/login'), html = await login.text();
    assert.equal(login.status, 200);
    assert.match(html, /MI Electric Brasil/); assert.match(html, /\bEM\b/);
    assert.match(html, /name="email"/); assert.match(html, /name="password"/);
    assert.match(login.headers.get('cache-control') || '', /no-store/);
    assert.equal((await request('/mi-electric-brasil.svg')).status, 200, 'Logo público ausente no standalone.');
    const css = html.match(/<link[^>]+href="([^"]+\.css(?:\?[^"]*)?)"[^>]*>/)?.[1];
    assert.ok(css, 'O login precisa carregar o CSS da plataforma.');
    const cssUrl = new URL(css, origin); assert.equal(cssUrl.origin, origin);
    assert.equal((await request(cssUrl.pathname + cssUrl.search)).status, 200, 'CSS ausente no standalone.');

    for (const path of ['/', '/painel', '/projetos', '/planejamento', '/cronograma', '/formularios', '/cadastros', '/login/mfa']) {
      let current = path, arrived = false;
      for (let hop = 0; hop < 4; hop++) {
        const response = await request(current);
        assert.ok([303, 307, 308].includes(response.status), `${path}: esperado redirecionamento de autenticação, recebido ${response.status}.`);
        const location = response.headers.get('location'); assert.ok(location, path);
        const next = new URL(location, origin); assert.equal(next.origin, origin, 'Redirecionamento deve permanecer na plataforma.');
        if (next.pathname === '/login') { arrived = true; break; }
        current = next.pathname + next.search;
      }
      assert.equal(arrived, true, `${path}: sessão ausente deve terminar no login.`);
    }

    const recordId = '00000000-0000-4000-8000-000000000001';
    for (const path of [`/api/web/forms/${recordId}`, `/api/web/documents/${recordId}?source=docs`]) {
      const denied = await request(path); assert.equal(denied.status, 401, path);
      assert.match(denied.headers.get('cache-control') || '', /no-store/);
    }
    assert.equal((await request('/auth/logout')).status, 405, 'GET não pode encerrar uma sessão.');
    assert.equal((await request('/auth/logout', { method: 'POST', headers: { Origin: 'https://cross-site.example.invalid' } })).status, 403);
    assert.equal((await request('/auth/logout', { method: 'POST' })).status, 403, 'Logout sem Origin deve ser negado.');
    for (const path of ['/api/webhooks/bubble', '/api/sync/run', '/api/reports/generate-pdf', '/api/reports/compile-s3', '/api/auth/totp']) {
      assert.equal((await request(path, { method: 'POST' })).status, 401, path);
    }
    for (const path of ['/api/reports/generate-pdf', '/api/reports/compile-s3', '/api/auth/totp']) {
      assert.equal((await request(path, { method: 'POST', headers: { Authorization: `Bearer ${secret}` } })).status, 501, path);
    }
    console.info('Runtime smoke: health/login/assets 200; portal sem sessão → login; APIs web/internas 401; logout 405/403; rotas reservadas 501. Sem credenciais reais.');
  } catch (error) { console.error('Smoke falhou. Saída do processo:', diagnostics); throw error; }
  finally { server.kill(); }
}
void main().catch(error => { console.error(error); process.exitCode = 1; });
