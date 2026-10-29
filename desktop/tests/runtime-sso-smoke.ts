import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { cpSync, existsSync, unlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';

async function main() {
  const port = 3197, origin = `http://127.0.0.1:${port}`, publicOrigin = 'https://em.example.invalid';
  assert.ok(existsSync('.next/standalone/server.js'), 'Execute npm run build antes deste smoke test.');
  cpSync('public', '.next/standalone/public', { recursive: true });
  cpSync('.next/static', '.next/standalone/.next/static', { recursive: true });
  await new Promise<void>((resolve, reject) => {
    const probe = createServer(); probe.once('error', reject);
    probe.listen(port, '127.0.0.1', () => probe.close(error => error ? reject(error) : resolve()));
  });
  const env = { ...process.env };
  for (const name of Object.keys(env)) if (/SUPABASE|BUBBLE|WEBHOOK|N8N|SSO|CORPORATE|EM_PUBLIC_ORIGIN|INTERNAL_API_SECRET/.test(name)) env[name] = '';
  // Empty values override traced .env files. These are deliberately fake keys;
  // the issuer URLs remain pinned to exercise the actual configuration contract.
  Object.assign(env, {
    NODE_ENV: 'production', PORT: String(port), HOSTNAME: '127.0.0.1',
    INTERNAL_API_SECRET: randomBytes(32).toString('hex'), SYNC_OUTBOX_ENABLED: 'false',
    SUPABASE_URL: 'https://ellpxfbsrbhblyizvbbk.supabase.co', SUPABASE_ANON_KEY: 'runtime-public-placeholder', SUPABASE_SERVICE_ROLE_KEY: '',
    NEXT_PUBLIC_SUPABASE_URL: '', NEXT_PUBLIC_SUPABASE_ANON_KEY: '', NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: '',
    BUBBLE_API_BASE_URL: '', BUBBLE_API_TOKEN: '', BUBBLE_WEBHOOK_SECRET: '',
    EM_SSO_ENABLED: 'true', EM_PUBLIC_ORIGIN: publicOrigin, EM_CORPORATE_APP_SLUG: 'em',
    EM_CORPORATE_SUPABASE_URL: 'https://kxoriwvzmxhatzqcgnht.supabase.co', EM_CORPORATE_PUBLISHABLE_KEY: 'sb_publishable_runtime_placeholder',
    EM_SSO_BRIDGE_SERVICE_ROLE_KEY: '', EM_SSO_ENCRYPTION_KEY: randomBytes(32).toString('base64url'),
  });
  // Prevent any accidental call to the pinned live issuers. No successful
  // authentication or external service is needed for these denial-path checks.
  const guardPath = join(tmpdir(), `em-sso-smoke-${randomBytes(12).toString('hex')}.cjs`);
  writeFileSync(guardPath, `const originalFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  if (!['127.0.0.1', 'localhost'].includes(url.hostname) || url.port !== '${port}') {
    process.stderr.write('SSO_SMOKE_NETWORK_BLOCKED\\n');
    return Promise.reject(new Error('External network disabled in smoke test.'));
  }
  return originalFetch(input, init);
};\n`, { flag: 'wx' });
  const server = spawn(process.execPath, ['--require', guardPath, '.next/standalone/server.js'], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env });
  let diagnostics = '', launchError: Error | undefined;
  server.once('error', error => { launchError = error; });
  const capture = (value: Buffer) => { diagnostics = (diagnostics + String(value)).slice(-16_000); };
  server.stdout.on('data', capture); server.stderr.on('data', capture);
  const request = (path: string, init: RequestInit = {}) => fetch(origin + path, { ...init, redirect: 'manual', signal: init.signal ?? AbortSignal.timeout(10_000) });
  function noStore(response: Response) { assert.match(response.headers.get('cache-control') || '', /no-store/); }
  function privateAuth(response: Response) { noStore(response); assert.equal(response.headers.get('referrer-policy'), 'no-referrer'); }
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
    const login = await request('/login'), html = await login.text();
    assert.equal(login.status, 200); noStore(login);
    assert.equal(login.headers.get('referrer-policy'), 'same-origin', 'Native login POST must retain its first-party Origin header.');
    assert.match(html, /<meta name="referrer" content="same-origin"/);
    assert.match(html, /Entrar com Microsoft/); assert.match(html, /action="\/auth\/sso\/start"/);
    assert.doesNotMatch(html, /name="(?:email|password)"/);

    for (const headers of [{}, { Cookie: 'em-sso-session=forged' }] as Record<string, string>[]) {
      for (const path of ['/', '/painel', '/projetos', '/planejamento', '/cronograma', '/formularios', '/cadastros', '/cadastros/novo?kind=clients', '/cadastros/types/00000000-0000-4000-8000-000000000001/editar',
        '/engenharia', '/engenharia/novo', '/engenharia/00000000-0000-4000-8000-000000000001', '/engenharia/00000000-0000-4000-8000-000000000001/editar',
        '/engenharia/titulos', '/engenharia/titulos/novo', '/engenharia/titulos/00000000-0000-4000-8000-000000000001/editar',
        '/modelos-formularios', '/modelos-formularios/novo', '/modelos-formularios/00000000-0000-4000-8000-000000000001',
        '/modelos-formularios/publicados/00000000-0000-4000-8000-000000000001', '/login/sso-mfa']) {
        let current = path, arrived = false;
        for (let hop = 0; hop < 4; hop++) {
          const response = await request(current, { headers }); noStore(response);
          assert.ok([303, 307, 308].includes(response.status), `${path}: esperado redirecionamento, recebido ${response.status}.`);
          const location = response.headers.get('location'); assert.ok(location, path);
          const next = new URL(location, origin); assert.ok([origin, publicOrigin].includes(next.origin));
          if (next.pathname === '/login') { arrived = true; break; }
          current = next.pathname + next.search;
        }
        assert.equal(arrived, true, `${path}: sessão ausente/inválida deve terminar no login.`);
      }
      const id = '00000000-0000-4000-8000-000000000001';
      for (const path of [`/api/web/forms/${id}`, `/api/web/documents/${id}?source=docs`]) {
        const denied = await request(path, { headers }); assert.equal(denied.status, 401, path); noStore(denied);
      }
    }
    assert.equal((await request('/auth/sso/start')).status, 405);
    for (const path of ['/auth/sso/start', '/auth/logout']) {
      for (const headers of [{}, { Origin: 'null' }, { Origin: origin }, { Origin: 'https://cross-site.example.invalid', 'X-Forwarded-Host': 'cross-site.example.invalid' }] as Record<string, string>[]) {
        const denied = await request(path, { method: 'POST', headers }); assert.equal(denied.status, 403); privateAuth(denied);
      }
    }
    assert.equal((await request('/auth/logout')).status, 405);
    for (const query of ['code=unknown-code-123', 'code=unknown-code-123&returnTo=https://attacker.invalid', 'access_token=forged', 'error=access_denied&error_description=private-detail']) {
      const response = await request(`/auth/sso/callback?${query}`);
      assert.equal(response.status, 303); privateAuth(response);
      assert.equal(response.headers.get('location'), `${publicOrigin}/login?erro=sso`);
      assert.equal(await response.text(), '');
    }
    assert.doesNotMatch(diagnostics, /SSO_SMOKE_NETWORK_BLOCKED/, 'Nenhum caminho de negação deve tentar acessar serviços externos.');
    console.info('SSO runtime smoke: Microsoft-only login; portal and forged cookies denied; web APIs 401; cross-site POSTs 403; strict callback. No external requests or real credentials.');
  } catch (error) { console.error('SSO smoke falhou. Saída do processo:', diagnostics); throw error; }
  finally { server.kill(); unlinkSync(guardPath); }
}
void main().catch(error => { console.error(error); process.exitCode = 1; });
