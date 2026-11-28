import assert from 'node:assert/strict';
import test from 'node:test';
import { needsWorkshopCatalogReconciliation, operatorCatalogKey, operatorScopedCatalogTable, readWorkshopCatalogPage, visibleOperatorCatalogRows } from '../src/core/catalog-workshop';
import type { Operator } from '../src/core/types';

const id = (n: number) => `08100000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const session = { deviceToken: 'local-device-token', operatorToken: 'local-operator-token', operatorId: id(2), workshopId: id(1) };
const updated_at = '2026-11-26T20:00:00.123456-03:00';
const row = { id: id(4), updated_at, nome: 'Cliente local' };
const page = { workshop_id: id(1), table: 'rm_clientes', complete: true, rows: [row] };

test('new authorized allocations refresh the operator manifest during the same pull', () => {
  const now = Date.now();
  const previous = now - 60_000;
  const manifest = new Set([id(7)]);
  assert.equal(needsWorkshopCatalogReconciliation('rm_celulas_projeto', previous, now, manifest, new Set([id(7), id(8)])), true);
  assert.equal(needsWorkshopCatalogReconciliation('rm_celulas_projeto', previous, now, manifest, new Set([id(7)])), false);
  assert.equal(needsWorkshopCatalogReconciliation('rm_celulas_projeto', previous, now, null, new Set()), true);
  assert.equal(needsWorkshopCatalogReconciliation('rm_clientes', previous, now, null, new Set([id(8)])), false);
});

test('scope-first catalogue preserves exact row versions and does not ask the client to choose an office', async () => {
  const result = await readWorkshopCatalogPage(session, 'rm_clientes', { at: updated_at, id: id(3) }, false,
    async (url, init) => {
      assert.equal(url, 'https://em-web-production.up.railway.app/api/mobile/sincronizacao');
      assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer local-device-token');
      assert.deepEqual(JSON.parse(String(init?.body)), {
        operatorToken: 'local-operator-token', table: 'rm_clientes', after: { at: updated_at, id: id(3) }, idsOnly: false,
      });
      return Response.json(page);
    });
  assert.deepEqual(result, { rows: [row], complete: true });
  assert.equal(operatorScopedCatalogTable('rm_clientes'), false);
  assert.equal(operatorScopedCatalogTable('rm_celulas_projeto'), true);
  assert.notEqual(operatorCatalogKey(id(1), id(2), 'rm_celulas'), operatorCatalogKey(id(1), id(3), 'rm_celulas'));
});

test('catalogue cannot reconcile another workshop, truncated page, or additional data in a manifest', async () => {
  for (const corrupt of [
    { ...page, workshop_id: id(21) }, { ...page, table: 'rm_forms' },
    { ...page, complete: false }, { ...page, rows: [row, row] }, { ...page, rows: [{ id: row.id, updated_at: 'invalid' }] },
  ]) await assert.rejects(readWorkshopCatalogPage(session, 'rm_clientes', null, false, async () => Response.json(corrupt)));
  await assert.rejects(readWorkshopCatalogPage(session, 'rm_clientes', null, true, async () => Response.json(page)));
  await assert.rejects(readWorkshopCatalogPage(session, 'rm_clientes', null, true, async () => Response.json(null, { status: 403 })), { code: '42501' });
});

test('switching operators retains shared offline rows and applies each membership and manifest independently', () => {
  const grants = (operator: number, cell: number): Operator => ({ operador_id: id(operator), matricula: 'LOCAL', nome: 'Local',
    perfil: 'mobile', perfil_assinante: [], authenticated_at: updated_at, celulas_vinculadas: [{ celula_id: id(cell), nome: 'Local' }] });
  const rows = [{ id: id(7), celula_id: id(11) }, { id: id(8), celula_id: id(12) }];
  assert.deepEqual(visibleOperatorCatalogRows('rm_celulas_projeto', rows, grants(2, 11), [id(7), id(8)]), [rows[0]]);
  assert.deepEqual(visibleOperatorCatalogRows('rm_celulas_projeto', rows, grants(3, 12), [id(8)]), [rows[1]]);
  assert.deepEqual(visibleOperatorCatalogRows('rm_celulas_projeto', rows, grants(2, 11), []), []);
  assert.deepEqual(visibleOperatorCatalogRows('rm_celulas_projeto', rows, grants(2, 11), null), [rows[0]]);
  assert.equal(rows.length, 2);
});
