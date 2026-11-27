import assert from 'node:assert/strict';
import test from 'node:test';
import { readWorkshopOperatorCells } from '../src/core/operator-workshop';
import type { Operator } from '../src/core/types';

const id = (n: number) => `07600000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const operator: Operator = { operador_id: id(2), matricula: 'LOCAL', nome: 'Operador', perfil: 'padr_o',
  perfil_assinante: [], authenticated_at: new Date().toISOString(),
  celulas_vinculadas: [{ celula_id: id(4), nome: 'Local' }, { celula_id: id(5), nome: 'Outra oficina' }] };
const result = () => ({ deviceId: id(1), operatorId: operator.operador_id, workshop: { id: id(3), revision: 1 },
  expiresAt: new Date(Date.now() + 60_000).toISOString(), data: { kind: 'cells', items: [{ id: id(4), nome: 'Local' }] } });

test('native cell selection is the intersection of operator permissions and the verified workshop', async () => {
  const response = await readWorkshopOperatorCells(id(1), 'local-device-token', operator, 'local-operator-token', new AbortController().signal,
    { androidBuild: '1.2.24/27', request: async (url, init) => {
      assert.equal(url, 'https://em-web-production.up.railway.app/api/mobile/catalogo');
      assert.equal(init?.redirect, 'error');
      assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer local-device-token');
      assert.equal(new Headers(init?.headers).get('x-em-android-build'), '1.2.24/27');
      assert.deepEqual(JSON.parse(String(init?.body)), { operatorToken: 'local-operator-token' });
      return Response.json(result());
    } });
  assert.equal(response.workshopId, id(3));
  assert.deepEqual(response.operator.celulas_vinculadas.map(cell => cell.celula_id), [id(4)]);
  assert.equal(operator.celulas_vinculadas.length, 2);
});

test('native cell selection refuses another device, another operator, expired authority and access denial', async () => {
  for (const payload of [
    { ...result(), deviceId: id(8) },
    { ...result(), operatorId: id(8) },
    { ...result(), expiresAt: '2000-01-01T00:00:00Z' },
    { ...result(), data: { kind: 'cells', items: [{ id: id(4) }, { id: id(4) }] } },
  ]) {
    await assert.rejects(readWorkshopOperatorCells(id(1), '', operator, '', new AbortController().signal, { request: async () => Response.json(payload) }));
  }
  await assert.rejects(readWorkshopOperatorCells(id(1), '', operator, '', new AbortController().signal,
    { request: async (_url, init) => {
      assert.equal(new Headers(init?.headers).get('x-em-android-build'), null);
      return Response.json({}, { status: 403 });
    } }), { code: '42501' });
});
