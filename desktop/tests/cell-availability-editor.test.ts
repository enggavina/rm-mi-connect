import test from 'node:test';
import assert from 'node:assert/strict';
import type { CellAvailabilitySnapshot } from '../src/server/web/cell-availability-data';
import { availabilityMatchesContext, cellAvailabilityAllowed, cellAvailabilityRequest, type CellAvailabilityMode } from '../src/components/web/cell-availability-model';

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const version = '2026-10-30T14:02:10.123456+00:00';
function snapshot(): CellAvailabilitySnapshot {
  return { project: { id: id(1), numero: 'OS1', status_pcp: null, data_real_de_entrega: null, updated_at: version, closed: false },
    allocation: { id: id(2), projeto_id: id(1), celula_id: id(3), celula_nome: 'Peritagem', status: 'pendente', visibilidade: true, retirada: false, indice: 7, posicao: 9, prioridade: 'alta', updated_at: version },
    can_set_visibility: true, can_retire: true, can_restore: false, visibility_reason: null, retire_reason: null, restore_reason: null, in_queue: true, context_version: 'a'.repeat(64) };
}

test('visibility changes require explicit confirmation and never send queue, route or priority modifications', () => {
  const current = snapshot(), mode: CellAvailabilityMode = { action: 'set_visibility', visibilidade: false };
  assert.throws(() => cellAvailabilityRequest(current, mode, false, id(20)), /Confirme/);
  const request = cellAvailabilityRequest(current, mode, true, id(20));
  assert.ok(request.action === 'set_visibility'); assert.equal(request.visibilidade, false); assert.equal(request.confirm_change, true);
  for (const field of ['posicao', 'indice', 'prioridade', 'celula_id', 'status', 'forms_ids', 'actor_id', 'retirada']) assert.ok(!(field in request));
  assert.equal(current.allocation.posicao, 9); assert.equal(current.allocation.indice, 7); assert.equal(current.allocation.prioridade, 'alta');
  assert.equal(cellAvailabilityAllowed(current, { action: 'set_visibility', visibilidade: true }, true), false, 'No-op availability is not a new intent.');
});

test('retirement and restoration use the same allocation identity without rematerializing its children', () => {
  const current = snapshot(), retired = cellAvailabilityRequest(current, { action: 'retire' }, true, id(20));
  assert.equal(retired.action, 'retire'); assert.equal(retired.celula_projeto_id, id(2)); assert.ok(!('visibilidade' in retired));
  current.allocation.retirada = true; current.allocation.visibilidade = false; current.can_retire = false; current.can_set_visibility = false; current.can_restore = true; current.in_queue = false;
  const restored = cellAvailabilityRequest(current, { action: 'restore' }, true, id(21));
  assert.equal(restored.action, 'restore'); assert.equal(restored.celula_projeto_id, retired.celula_projeto_id);
  assert.ok(!('forms_ids' in restored)); assert.ok(!('photos' in restored)); assert.ok(!('visibilidade' in restored), 'Restoration visibility is derived as hidden by the server.');
  assert.equal(cellAvailabilityAllowed(current, { action: 'set_visibility', visibilidade: true }, true), false);
});

test('availability retries freeze the protocol, intended action and exact timestamp/hash strings', () => {
  const current = snapshot(), mode: CellAvailabilityMode = { action: 'set_visibility', visibilidade: false };
  const request = cellAvailabilityRequest(current, mode, true, id(20));
  current.project.updated_at = 'later'; current.allocation.updated_at = 'later'; current.context_version = 'b'.repeat(64); mode.visibilidade = true;
  assert.equal(request.expected_project_updated_at, version); assert.equal(request.expected_allocation_updated_at, version); assert.equal(request.expected_context_version, 'a'.repeat(64));
  assert.equal(request.submissionId, id(20)); assert.ok(request.action === 'set_visibility'); assert.equal(request.visibilidade, false); assert.equal(Object.isFrozen(request), true);
});

test('server eligibility, closed projects and fresh SSR identity/version checks govern every availability write', () => {
  const current = snapshot();
  assert.equal(availabilityMatchesContext(current, current.project, current.allocation), true);
  for (const patch of [{ id: id(99) }, { projeto_id: id(99) }, { celula_id: id(99) }, { updated_at: 'later' }, { retirada: true }, { visibilidade: false }]) {
    assert.equal(availabilityMatchesContext(current, current.project, { ...current.allocation, ...patch }), false);
  }
  assert.equal(availabilityMatchesContext(current, { ...current.project, updated_at: 'later' }, current.allocation), false);
  assert.equal(cellAvailabilityAllowed(current, { action: 'retire' }, false), false);
  assert.equal(cellAvailabilityAllowed({ ...current, project: { ...current.project, closed: true } }, { action: 'retire' }, true), false);
  assert.throws(() => cellAvailabilityRequest({ ...current, can_retire: false }, { action: 'retire' }, true, id(20)), /não está disponível/);
  assert.throws(() => cellAvailabilityRequest(current, { action: 'restore' }, true, id(20)), /não está disponível/);
});
