// Run on the workstation that can complete Microsoft sign-in. Use real project
// URLs from the pilot, or fixtures in a disposable environment. The export request only reads planning data.
// npm install --prefix .tmp/em-qa --no-save playwright
// node desktop/tests/workshop-pilot.browser.cjs .tmp/oficinas-piloto.json
// node desktop/tests/workshop-pilot.browser.cjs .tmp/oficinas-piloto.json --office=BRJ
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { parseArgs } = require('node:util');

const { positionals, values } = parseArgs({ allowPositionals: true, options: { office: { type: 'string' } } });
assert.equal(positionals.length, 1, 'Informe o caminho da matriz JSON do piloto.');
const [configuration] = positionals;
const matrix = JSON.parse(readFileSync(configuration, 'utf8'));
const { chromium } = require(resolve(process.env.EM_QA_PLAYWRIGHT_PATH ?? '.tmp/em-qa/node_modules/playwright'));
const origin = new URL(matrix.origin);
assert.equal(origin.href, origin.origin + '/');
assert.ok(origin.protocol === 'https:' || (origin.protocol === 'http:' && origin.hostname === 'localhost'));
assert.ok(Array.isArray(matrix.offices) && matrix.offices.length >= 1);
const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const protocolPage = '/projetos/protocolo';
const protocolOperations = new Set(['Recebimento', 'Formulário', 'Correção de formulário', 'Registro de foto',
  'Aprovação de etapa', 'Atualização de status', 'Comentário', 'Apontamento de execução']);
let stepDescription = 'iniciar o navegador';

function location(path) {
  const url = new URL(path, origin);
  assert.equal(url.origin, origin.origin, 'A matriz só pode navegar pelo portal apontado.');
  return url.href;
}

async function verifyAllocationExport(context, own, others) {
  assert.match(own.cellId, uuid);
  assert.ok(typeof own.marker === 'string' && own.marker.trim() && own.marker.length <= 200);
  const exportCell = cellId => context.request.post(location('/api/web/planning/export'), {
    headers: { Origin: origin.origin },
    data: { cell_ids: [cellId], fields: ['cell_name', 'equipment_description'] },
    maxRedirects: 0,
  });
  const response = await exportCell(own.cellId);
  try {
    assert.equal(response.status(), 200);
    assert.match(response.headers()['content-type'] ?? '', /^application\/vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet/);
    const workbook = new (require('exceljs').Workbook)();
    await workbook.xlsx.load(await response.body());
    const cells = new Set();
    for (const sheet of workbook.worksheets) {
      sheet.eachRow(row => row.eachCell(cell => cells.add(cell.text)));
    }
    assert.ok(cells.has(own.marker), 'A planilha não contém a célula autorizada.');
    for (const other of others) {
      assert.match(other.cellId, uuid);
      assert.notEqual(other.cellId, own.cellId);
      assert.notEqual(other.marker, own.marker);
      assert.ok(!cells.has(other.marker), 'A planilha contém uma célula de outra oficina.');
    }
  } finally {
    await response.dispose();
  }
  for (const other of others) {
    const denied = await exportCell(other.cellId);
    try {
      assert.equal(denied.status(), 403);
      assert.equal(denied.headers()['content-disposition'], undefined);
    } finally {
      await denied.dispose();
    }
  }
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

async function verifyAndroidInstaller(page, expected) {
  assert.match(expected.file, /^em-mi-electric-brasil-(\d+\.\d+\.\d+)-piloto\.apk$/);
  const version = expected.file.match(/\d+\.\d+\.\d+/)[0];
  assert.match(expected.sha256, /^[0-9a-f]{64}$/);
  assert.ok(Number.isInteger(expected.bytes) && expected.bytes > 0 && expected.bytes <= 52428800);
  const link = page.getByRole('link', { name: 'Baixar APK', exact: true });
  await link.waitFor();
  const path = '/api/web/android/instalador';
  assert.equal(await link.getAttribute('href'), path);
  const signed = await page.request.get(location(path), { maxRedirects: 0 });
  assert.equal(signed.status(), 303);
  const cache = (signed.headers()['cache-control'] ?? '').split(',').map(value => value.trim());
  assert.ok(cache.includes('private') && cache.includes('no-store'));
  const url = new URL(signed.headers().location);
  assert.equal(url.origin, 'https://ellpxfbsrbhblyizvbbk.supabase.co');
  assert.equal(url.pathname, `/storage/v1/object/sign/rm-aplicativo-android/${version}/${expected.sha256}/${expected.file}`);
  assert.equal(url.searchParams.size, 2);
  assert.ok(url.searchParams.get('token'));
  assert.equal(url.searchParams.get('download'), expected.file);
  const download = await page.request.get(url.href, { maxRedirects: 0, timeout: 120_000 });
  assert.equal(download.status(), 200);
  assert.match(download.headers()['content-disposition'] ?? '', /^attachment/i);
  const file = await download.body();
  assert.equal(file.length, expected.bytes);
  assert.equal(createHash('sha256').update(file).digest('hex'), expected.sha256);
  await download.dispose();
  await signed.dispose();
}

function receiptChecks(receipt, ownOffice) {
  if (!receipt) return [];
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

function androidProtocols(office) {
  if (office.androidProtocols === undefined) return [];
  assert.ok(Array.isArray(office.androidProtocols));
  for (const result of office.androidProtocols) {
    assert.match(result.code, uuid);
    assert.match(result.projectId, uuid);
    assert.ok(protocolOperations.has(result.operation));
    assert.ok(result.phase === 'confirmed' || (result.phase === 'opened' && result.operation === 'Recebimento'));
    assert.ok(result.projectNumber === null || (typeof result.projectNumber === 'string' && result.projectNumber.trim()));
    assert.ok(result.replayed === undefined || typeof result.replayed === 'boolean');
    if (result.formRecordId !== undefined) {
      assert.match(result.formRecordId, uuid);
      assert.ok(result.operation === 'Formulário' || result.operation === 'Correção de formulário');
    }
  }
  return office.androidProtocols;
}

async function verifyAndroidProtocol(page, result, ownOffice) {
  const expected = location(protocolPage + '?' + new URLSearchParams({ protocolo: result.code }));
  if (ownOffice) {
    const response = await page.goto(location(protocolPage), { waitUntil: 'domcontentloaded' });
    assert.equal(response?.status(), 200);
    await page.getByRole('textbox', { name: 'Protocolo do Android', exact: true }).fill(result.code);
    const [submitted] = await Promise.all([
      page.waitForResponse(res => res.url() === expected && res.request().method() === 'GET'),
      page.getByRole('button', { name: 'Consultar', exact: true }).click(),
    ]);
    assert.equal(submitted.status(), 200);
    await page.waitForURL(expected, { waitUntil: 'domcontentloaded' });
  } else {
    assert.equal((await page.goto(expected, { waitUntil: 'domcontentloaded' }))?.status(), 200);
  }
  assert.equal(page.url(), expected, 'A consulta de protocolo foi redirecionada.');
  await page.getByRole('heading', { name: 'Protocolo do Android', exact: true }).waitFor();
  const project = page.getByRole('link', { name: 'Abrir projeto', exact: true });
  const form = page.getByRole('link', { name: 'Abrir formulário', exact: true });
  const retry = page.getByText('Último reenvio confirmado', { exact: true });
  if (!ownOffice) {
    await page.getByText('Protocolo não encontrado', { exact: true }).waitFor();
    assert.equal(await project.count(), 0);
    assert.equal(await form.count(), 0);
    assert.equal(await retry.count(), 0);
    return;
  }
  await page.getByRole('heading', { name: result.operation, exact: true }).waitFor();
  await page.getByText(result.phase === 'opened' ? 'Abertura confirmada · conclusão pendente' : 'Envio confirmado', { exact: true }).waitFor();
  await page.getByText(result.code, { exact: true }).waitFor();
  await page.getByText(result.projectNumber === null ? 'Recebimento sem OS' : `OS ${result.projectNumber}`, { exact: true }).waitFor();
  assert.equal(await project.getAttribute('href'), `/projetos/${result.projectId}`);
  if (result.formRecordId) assert.equal(await form.getAttribute('href'), `/formularios/${result.formRecordId}`);
  if (result.replayed === true) await retry.waitFor();
  if (result.replayed === false) assert.equal(await retry.count(), 0);
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

async function expandReviewSections(page, target) {
  for (const section of await page.locator('details.record-section').all()) {
    if (await target.count()) break;
    if (!(await section.evaluate(element => element.open))) await section.locator('summary').click();
  }
}

async function main() {
  const codes = matrix.offices.map(office => office.code);
  for (const code of codes) assert.match(code, /^[A-Z0-9_-]+$/);
  assert.equal(new Set(codes).size, codes.length, 'Use uma entrada por oficina na matriz.');
  if (values.office !== undefined) assert.ok(codes.includes(values.office), 'A oficina selecionada não está na matriz.');
  const protocols = matrix.offices.map(androidProtocols);
  const allCodes = protocols.flat().map(({ code }) => code);
  assert.equal(new Set(allCodes).size, allCodes.length, 'Cada protocolo deve identificar uma única unidade na matriz.');
  const browser = await chromium.launch({ channel: 'chrome', headless: false });
  try {
    const sessions = [];
    for (const [officeIndex, office] of matrix.offices.entries()) {
      if (values.office !== undefined && values.office !== office.code) continue;
      assert.ok(Array.isArray(office.allowed));
      assert.ok(Array.isArray(office.denied));
      const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
      const page = await context.newPage();
      stepDescription = `${office.code} · autenticação Microsoft`;
      await authenticate(page, office);
      sessions.push({ officeIndex, office, context, page });
    }
    for (const { officeIndex, office, context, page } of sessions) {
      const receipt = receiptChecks(office.receipt, true);
      const otherReceipts = matrix.offices.filter(other => other !== office).flatMap(other => receiptChecks(other.receipt, false));
      const ownProtocols = protocols[officeIndex];
      const foreignProtocols = protocols.filter((_, index) => index !== officeIndex).flat();
      assert.ok(office.allowed.length + receipt.length + ownProtocols.length > 0);
      if (office.allocationExport) {
        stepDescription = `${office.code} · exportação de alocações`;
        const otherExports = matrix.offices.filter(other => other !== office && other.allocationExport)
          .map(other => other.allocationExport);
        await verifyAllocationExport(context, office.allocationExport, otherExports);
        process.stdout.write(`PASS ${office.code} exportação de alocações\n`);
      }
      for (const [index, result] of ownProtocols.entries()) {
        stepDescription = `${office.code} · protocolo Android próprio ${index + 1}`;
        await verifyAndroidProtocol(page, result, true);
        process.stdout.write(`PASS ${office.code} protocolo Android próprio ${index + 1}\n`);
      }
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
        if (step.androidInstaller) await verifyAndroidInstaller(page, step.androidInstaller);
        if (step.marker) await page.getByText(step.marker, { exact: true }).first().waitFor();
        if (step.absent) assert.equal(await page.getByText(step.absent, { exact: true }).count(), 0);
        if (step.formAnswer !== undefined) {
          assert.ok(typeof step.formAnswer === 'string' && step.formAnswer.trim());
          const answer = page.locator('.answer-value').getByText(step.formAnswer, { exact: true }).first();
          await expandReviewSections(page, answer);
          await answer.waitFor();
        }
        if (step.image) {
          const image = page.locator(step.image).first();
          await expandReviewSections(page, image);
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
      for (const [index, result] of foreignProtocols.entries()) {
        stepDescription = `${office.code} · protocolo Android cruzado ${index + 1}`;
        await verifyAndroidProtocol(page, result, false);
        process.stdout.write(`PASS ${office.code} protocolo Android cruzado ${index + 1}\n`);
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
