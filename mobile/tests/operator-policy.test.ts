import test from 'node:test';
import assert from 'node:assert/strict';
import { applyOperatorContext, hasCurrentCellPolicy } from '../src/core/operator-policy';
import type { Operator } from '../src/core/types';

const operator: Operator = {
  operador_id: 'operator-a', matricula: 'A', nome: 'Operator A', perfil: 'mobile', perfil_assinante: [],
  celulas_vinculadas: [{ celula_id: 'cell-a', nome: 'A' }], cell_access_policy_version: 2,
  authenticated_at: '2026-10-27T12:00:00Z', token_expires_at: '2026-11-03T12:00:00Z',
};

test('old cached tablet-based permissions require a new online identification', () => {
  assert.equal(hasCurrentCellPolicy({ ...operator, cell_access_policy_version: undefined }), false);
  assert.equal(hasCurrentCellPolicy(operator), true);
});
test('permission refresh removes grants without extending the operator session', () => {
  const refreshed = applyOperatorContext(operator, { ...operator, celulas_vinculadas: [],
    authenticated_at: '2026-10-28T12:00:00Z', token_expires_at: '2026-11-04T12:00:00Z' });
  assert.deepEqual(refreshed.celulas_vinculadas, []);
  assert.equal(refreshed.authenticated_at, operator.authenticated_at);
  assert.equal(refreshed.token_expires_at, operator.token_expires_at);
});
test('permission refresh cannot switch operator or accept the legacy policy', () => {
  assert.throws(() => applyOperatorContext(operator, { ...operator, operador_id: 'operator-b' }));
  assert.throws(() => applyOperatorContext(operator, { ...operator, cell_access_policy_version: undefined }));
});
