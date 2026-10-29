import test from 'node:test';
import assert from 'node:assert/strict';
import { freezeStageApprovalRequest, visibleStageActions } from '../src/components/web/stage-approval-model';

test('stage decision presentation never combines release with return approval actions', () => {
  const malformed = ['liberar', 'retornar', 'aprovar'] as const;
  assert.deepEqual(visibleStageActions('retornado', malformed), ['retornar', 'aprovar']);
  assert.deepEqual(visibleStageActions('finalizado', malformed), ['liberar']);
  assert.deepEqual(visibleStageActions('retornado', ['aprovar']), ['aprovar']);
  assert.deepEqual(visibleStageActions(null, []), []);
});

test('stage retry freezes exact actor-free operation, decision and both optimistic versions', () => {
  const original = { submissionId: 'submission', aprovacao_etapa_id: 'stage', expected_updated_at: '2026-10-29T10:20:30.123456+00:00',
    expected_cell_updated_at: '2026-10-29T10:21:30.654321+00:00', acao: 'retornar' as const, observacao: 'Conferir ajuste' };
  const frozen = freezeStageApprovalRequest(original);
  original.observacao = 'Não pode alterar o envio em voo'; original.expected_cell_updated_at = 'different';
  assert.equal(frozen.observacao, 'Conferir ajuste'); assert.equal(frozen.expected_cell_updated_at, '2026-10-29T10:21:30.654321+00:00');
  assert.equal(Object.isFrozen(frozen), true); assert.equal('operador_id' in frozen, false);
  assert.throws(() => { (frozen as any).acao = 'aprovar'; }, TypeError);
});
