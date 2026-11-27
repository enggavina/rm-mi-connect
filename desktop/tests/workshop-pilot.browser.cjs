// Run on the workstation that can complete Microsoft sign-in. Use real project
// URLs from the pilot, or fixtures in a disposable environment. GET checks only.
// npm install --prefix .tmp/em-qa --no-save playwright
// node desktop/tests/workshop-pilot.browser.cjs .tmp/oficinas-piloto.json
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const configuration = process.argv[2];
assert.ok(configuration, 'Informe o caminho da matriz JSON do piloto.');
const matrix = JSON.parse(readFileSync(configuration, 'utf8'));
const { chromium } = require(resolve(process.env.EM_QA_PLAYWRIGHT_PATH ?? '.tmp/em-qa/node_modules/playwright'));
const origin = new URL(matrix.origin);
assert.equal(origin.href, origin.origin + '/');
assert.ok(origin.protocol === 'https:' || (origin.protocol === 'http:' && origin.hostname === 'localhost'));
assert.ok(Array.isArray(matrix.offices) && matrix.offices.length >= 1);
let stepDescription = 'iniciar o navegador';

function location(path) {
  const url = new URL(path, origin);
  assert.equal(url.origin, origin.origin, 'A matriz só pode navegar pelo portal apontado.');
  return url.href;
}

async function authenticate(page, office) {
  await page.goto(location('/login'));
  process.stdout.write(`Entre com a conta de ${office.code} na janela aberta.\n`);
  await page.waitForURL(location('/painel'), { timeout: 180_000, waitUntil: 'domcontentloaded' });
}

async function main() {
  const browser = await chromium.launch({ channel: 'chrome', headless: false });
  try {
    for (const office of matrix.offices) {
      assert.match(office.code, /^[A-Z0-9_-]+$/);
      assert.ok(Array.isArray(office.allowed) && office.allowed.length > 0);
      assert.ok(Array.isArray(office.denied));
      const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
      try {
        const page = await context.newPage();
        stepDescription = `${office.code} · autenticação Microsoft`;
        await authenticate(page, office);
        for (const [index, step] of office.allowed.entries()) {
          stepDescription = `${office.code} · consulta própria ${index + 1}`;
          const expected = location(step.path);
          const response = await page.goto(expected, { waitUntil: 'domcontentloaded' });
          assert.equal(page.url(), expected, 'A navegação foi redirecionada.');
          assert.equal(response?.status(), 200);
          await page.getByRole('heading', { name: step.heading, exact: true }).first().waitFor();
          if (step.selector) await page.locator(step.selector).first().waitFor();
          if (step.marker) await page.getByText(step.marker, { exact: true }).first().waitFor();
          if (step.absent) assert.equal(await page.getByText(step.absent, { exact: true }).count(), 0);
          if (step.image) {
            const image = page.locator(step.image).first();
            await image.scrollIntoViewIfNeeded();
            const src = await image.getAttribute('src');
            assert.match(src ?? '', /^\/api\/web\/media\/[0-9a-f-]{36}\?/);
            await page.waitForFunction(element => element.complete && element.naturalWidth > 0, await image.elementHandle());
            const preview = await context.request.get(location(src), { maxRedirects: 0 });
            assert.equal(preview.status(), 200);
            assert.match(preview.headers()['content-type'] ?? '', /^image\//);
            assert.equal(preview.headers().location, undefined);
          }
          if (step.plant === true) await page.getByRole('button', { name: 'Oficina 3D' }).waitFor();
          if (step.plant === false) assert.equal(await page.getByRole('button', { name: 'Oficina 3D' }).count(), 0);
          process.stdout.write(`PASS ${office.code} consulta própria ${index + 1}\n`);
        }
        for (const [index, value] of office.denied.entries()) {
          stepDescription = `${office.code} · consulta cruzada ${index + 1}`;
          const step = typeof value === 'string' ? { path: value } : value;
          const expected = location(step.path);
          const response = await page.goto(expected, { waitUntil: 'domcontentloaded' });
          assert.equal(page.url(), expected, 'A rota testada deve permanecer no endereço esperado.');
          if (response?.status() === 200 && step.heading) {
            // Next can emit the not-found view after sending the portal shell.
            await page.getByRole('heading', { name: step.heading, exact: true }).first().waitFor();
          } else {
            assert.ok([403, 404].includes(response?.status()), 'A consulta de outra unidade deve devolver uma recusa.');
          }
          if (step.absent) assert.equal(await page.getByText(step.absent, { exact: true }).count(), 0);
          if (step.absentSelector) assert.equal(await page.locator(step.absentSelector).count(), 0);
          process.stdout.write(`PASS ${office.code} consulta cruzada ${index + 1}\n`);
        }
      } finally {
        await context.close();
      }
    }
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  process.stderr.write(`Falha no roteiro de homologação em ${stepDescription} (${error.name}).\n`);
  process.exitCode = 1;
});
