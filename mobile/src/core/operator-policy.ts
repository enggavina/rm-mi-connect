import type { Operator } from './types';

export const CELL_ACCESS_POLICY_VERSION = 2;

export function hasCurrentCellPolicy(operator: Operator): boolean {
  return operator.cell_access_policy_version === CELL_ACCESS_POLICY_VERSION;
}

/** Refresh grants, without turning a background sync into a new login. */
export function applyOperatorContext(current: Operator, updated: Operator): Operator {
  if (!hasCurrentCellPolicy(updated) || updated.operador_id !== current.operador_id) {
    throw new Error('Contexto de permissões inválido. Identifique o operador novamente com conexão.');
  }
  return { ...updated, authenticated_at: current.authenticated_at, token_expires_at: current.token_expires_at };
}
