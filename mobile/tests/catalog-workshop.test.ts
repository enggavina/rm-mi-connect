import assert from 'node:assert/strict';
import test from 'node:test';
import { readWorkshopCatalogPage, scopedCatalogTable } from '../src/core/catalog-workshop';

const id = (n: number) => `08100000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const session = { deviceToken: 'local-device-token', operatorToken: 'local-operator-token', workshopId: id(1) };
const updated_at = '2026-11-26T20:00:00.123456-03:00';
const row = { id: id(4), updated_at, nome: 'Cliente local' };
const page = { workshop_id: id(1), table: 'rm_clientes', complete: true, rows: [row] };

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
  assert.equal(scopedCatalogTable('rm_clientes'), true);
  assert.equal(scopedCatalogTable('rm_users'), false);
});

test('catalogue cannot reconcile another workshop, truncated page, or additional data in a manifest', async () => {
  for (const corrupt of [
    { ...page, workshop_id: id(21) }, { ...page, table: 'rm_forms' },
    { ...page, complete: false }, { ...page, rows: [row, row] }, { ...page, rows: [{ id: row.id, updated_at: 'invalid' }] },
  ]) await assert.rejects(readWorkshopCatalogPage(session, 'rm_clientes', null, false, async () => Response.json(corrupt)));
  await assert.rejects(readWorkshopCatalogPage(session, 'rm_clientes', null, true, async () => Response.json(page)));
  await assert.rejects(readWorkshopCatalogPage(session, 'rm_clientes', null, true, async () => Response.json(null, { status: 403 })), { code: '42501' });
});
