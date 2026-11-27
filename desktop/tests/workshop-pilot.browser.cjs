// Run on the workstation that can complete Microsoft sign-in. Use real project
// URLs from the pilot, or fixtures in a disposable environment. GET checks only.
// npm install --prefix .tmp/em-qa --no-save playwright
// node desktop/tests/workshop-pilot.browser.cjs .tmp/oficinas-piloto.json
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
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

function signedMedia(response, legacyImage) {
  assert.equal(response.status(), 303);
  const copy = new URL(response.headers().location);
  assert.equal(copy.origin, 'https://ellpxfbsrbhblyizvbbk.supabase.co');
  if (legacyImage !== undefined) {
    assert.match(legacyImage, /^rm-(?:fotos|assinaturas)\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(?:jpg|png)$/);
    assert.equal(copy.pathname, `/storage/v1/object/sign/${legacyImage}`);
  } else assert.match(copy.pathname, /^\/storage\/v1\/object\/sign\/rm-documentos\/(acervo-oficina|mobile-oficina|web-dossier)\//);
  assert.equal(copy.searchParams.size, 1);
  assert.ok(copy.searchParams.get('token'));
  return copy;
}

function receiptChecks(receipt, ownOffice) {
  if (!receipt) return [];
  const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
  assert.match(receipt.projectId, uuid);
  assert.ok(typeof receipt.search === 'string' && receipt.search.trim().length > 0 && receipt.search.length <= 100);
  assert.ok(['receiving', 'planning'].includes(receipt.phase));
  const projectPath = `/projetos/${receipt.projectId}`;
  const link = `a[href="${projectPath}"]`;
  const q = new URLSearchParams({ q: receipt.search });
  const steps = [{ path: `/projetos?${q}`, heading: 'Projetos', selector: link }];
  if (receipt.phase === 'receiving') {
    if (receipt.withoutOs) q.set('reason', 'without_number');
    steps.unshift({ path: `/recebimentos?${q}`, heading: 'Recebimentos',
      selector: receipt.withoutOs ? `${link}.table-title:text-is("Recebimento sem OS")` : link });
  } else {
    assert.match(receipt.cellId, uuid);
    assert.match(receipt.allocationId, uuid);
    assert.match(receipt.start, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(new Date(receipt.start).toISOString().slice(0, 10), receipt.start);
    for (const [scope, extra] of [['general', {}], ['cell', { cell: receipt.cellId }], ['project', { project: receipt.projectId }]]) {
      const filters = new URLSearchParams({ view: 'gantt', scope, start: receipt.start, ...extra });
      if (scope !== 'project' && receipt.includeClosed) filters.set('closed', 'yes');
      steps.push({ path: `/cronograma?${filters}`, heading: 'Cronograma',
        selector: `[data-gantt-row="${receipt.allocationId}"]`, scope,
        previewAllocation: receipt.preview === true && scope === 'project' ? receipt.allocationId : undefined });
    }
  }
  if (ownOffice) return steps;
  return [{ path: projectPath, heading: '404', absentSelector: link }, ...steps.map(({ path, heading, selector, scope }) => {
    const direct = scope === 'project' || scope === 'cell';
    return { path, heading: direct ? '404' : heading, absentSelector: selector, searchOnly: !direct };
  })];
}

async function verifyGanttPreview(page, allocation) {
  const sameOrigin = url => url.origin === origin.origin;
  let blockedWrites = 0;
  const preventWrite = route => {
    if (route.request().method() === 'GET') return route.continue();
    blockedWrites++;
    return route.abort();
  };
  await page.route(sameOrigin, preventWrite);
  try {
    await page.locator(`[data-gantt-row-title="${allocation}"]`).click();
    const details = page.getByRole('complementary', { name: 'Planejamento da etapa selecionada' });
    const start = details.getByLabel('Início previsto da etapa', { exact: true });
    const due = details.getByLabel('Prazo da etapa', { exact: true });
    const original = [await start.inputValue(), await due.inputValue()];
    assert.ok(original.every(date => /^\d{4}-\d{2}-\d{2}$/.test(date)));
    await details.getByRole('button', { name: 'Adiar 1 dia', exact: true }).click();
    const review = page.getByRole('region', { name: 'Revisão das alterações do Gantt' });
    await review.waitFor();
    assert.notDeepEqual([await start.inputValue(), await due.inputValue()], original);
    await review.getByRole('button', { name: 'Descartar prévia', exact: true }).click();
    await review.waitFor({ state: 'hidden' });
    assert.deepEqual([await start.inputValue(), await due.inputValue()], original);
    assert.equal(blockedWrites, 0);
  } finally {
    await page.unroute(sameOrigin, preventWrite);
  }
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
      assert.ok(Array.isArray(office.allowed));
      assert.ok(Array.isArray(office.denied));
      const receipt = receiptChecks(office.receipt, true);
      const otherReceipts = matrix.offices.filter(other => other !== office).flatMap(other => receiptChecks(other.receipt, false));
      assert.ok(office.allowed.length + receipt.length > 0);
      const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
      try {
        const page = await context.newPage();
        stepDescription = `${office.code} · autenticação Microsoft`;
        await authenticate(page, office);
        for (const [index, step] of [...office.allowed, ...receipt].entries()) {
          stepDescription = `${office.code} · consulta própria ${index + 1}`;
          const expected = location(step.path);
          const response = await page.goto(expected, { waitUntil: 'domcontentloaded' });
          assert.equal(page.url(), expected, 'A navegação foi redirecionada.');
          assert.equal(response?.status(), 200);
          await page.getByRole('heading', { name: step.heading, exact: true }).first().waitFor();
          if (step.selector) {
            const state = step.selectorState ?? 'visible';
            assert.ok(['visible', 'attached'].includes(state));
            await page.locator(step.selector).first().waitFor({ state });
          }
          if (step.scope) {
            await page.locator(step.selector).getByRole('button', { name: /Abrir datas/ }).waitFor();
            await page.getByRole('navigation', { name: 'Escopo do Gantt' })
              .locator(`a[href$="scope=${step.scope}"][aria-current="page"]`).waitFor();
          }
          if (step.previewAllocation) await verifyGanttPreview(page, step.previewAllocation);
          if (step.marker) await page.getByText(step.marker, { exact: true }).first().waitFor();
          if (step.absent) assert.equal(await page.getByText(step.absent, { exact: true }).count(), 0);
          if (step.image) {
            const image = page.locator(step.image).first();
            const sections = await page.locator('details.record-section').all();
            for (const section of sections) {
              if (await image.count()) break;
              if (!(await section.evaluate(element => element.open))) await section.locator('summary').click();
            }
            await image.scrollIntoViewIfNeeded();
            const src = await image.getAttribute('src');
            assert.match(src ?? '', /^\/api\/web\/media\/[0-9a-f-]{36}\?/);
            await page.waitForFunction(element => element.complete && element.naturalWidth > 0, await image.elementHandle());
            const preview = await context.request.get(location(src), { maxRedirects: 0 });
            if (preview.status() === 303) signedMedia(preview, step.legacyImage);
            else {
              assert.equal(step.legacyImage, undefined);
              assert.equal(preview.status(), 200);
              assert.match(preview.headers()['content-type'] ?? '', /^image\//);
              assert.equal(preview.headers().location, undefined);
            }
            await preview.dispose();
          }
          if (step.document) {
            const doc = typeof step.document === 'string' ? { path: step.document, type: 'docx' } : step.document;
            const link = await context.request.get(location(doc.path), { maxRedirects: 0 });
            if (doc.unavailable) {
              assert.equal(link.status(), 404);
              assert.equal(link.headers().location, undefined);
              assert.equal((await link.json()).error, 'Este documento ainda não possui um arquivo disponível para leitura.');
            } else {
              const mime = { docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', pdf: 'application/pdf' }[doc.type];
              assert.ok(mime, 'Tipo de documento não suportado na matriz.');
              const copy = signedMedia(link);
              assert.ok(copy.pathname.toLowerCase().endsWith(`.${doc.type}`));
              const file = await context.request.get(copy.href, { maxRedirects: 0 });
              assert.equal(file.status(), 200);
              assert.equal(file.headers()['content-type']?.split(';')[0], mime);
              const body = await file.body();
              const magic = doc.type === 'pdf' ? Buffer.from('%PDF-') : Buffer.from('504b0304', 'hex');
              assert.deepEqual(body.subarray(0, magic.length), magic);
              if (doc.sha256) assert.equal(createHash('sha256').update(body).digest('hex'), doc.sha256);
              await file.dispose();
            }
            await link.dispose();
          }
          if (step.plant === true) await page.getByRole('button', { name: 'Oficina 3D' }).waitFor();
          if (step.plant === false) assert.equal(await page.getByRole('button', { name: 'Oficina 3D' }).count(), 0);
          process.stdout.write(`PASS ${office.code} consulta própria ${index + 1}\n`);
        }
        for (const [index, value] of [...office.denied, ...otherReceipts].entries()) {
          stepDescription = `${office.code} · consulta cruzada ${index + 1}`;
          const step = typeof value === 'string' ? { path: value } : value;
          const expected = location(step.path);
          const response = await page.goto(expected, { waitUntil: 'domcontentloaded' });
          assert.equal(page.url(), expected, 'A rota testada deve permanecer no endereço esperado.');
          if (step.searchOnly) assert.equal(response?.status(), 200);
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
