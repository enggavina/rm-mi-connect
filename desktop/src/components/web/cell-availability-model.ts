import type { CellAvailabilitySnapshot } from '@/server/web/cell-availability-data';
import type { ManageCellAvailabilityInput } from '@/server/web/cell-availability-policy';
import { freezeEngineeringRequest } from './engineering-model';

export type CellAvailabilityMode = { action: 'set_visibility'; visibilidade: boolean } | { action: 'retire' } | { action: 'restore' };
export function cellAvailabilityAllowed(snapshot: CellAvailabilitySnapshot, mode: CellAvailabilityMode, permitted: boolean) {
  if (!permitted || snapshot.project.closed) return false;
  if (mode.action === 'set_visibility') return !snapshot.allocation.retirada && snapshot.can_set_visibility && mode.visibilidade !== snapshot.allocation.visibilidade;
  return mode.action === 'retire' ? !snapshot.allocation.retirada && snapshot.can_retire : snapshot.allocation.retirada && snapshot.can_restore;
}
export function cellAvailabilityRequest(snapshot: CellAvailabilitySnapshot, mode: CellAvailabilityMode, confirmed: boolean, submissionId: string): ManageCellAvailabilityInput {
  if (!cellAvailabilityAllowed(snapshot, mode, true)) throw new Error('Esta alteração não está disponível. Recarregue a célula para conferir o estado atual.');
  if (!confirmed) throw new Error('Confirme a alteração de disponibilidade antes de continuar.');
  const common = { submissionId, projeto_id: snapshot.project.id, celula_projeto_id: snapshot.allocation.id,
    expected_project_updated_at: snapshot.project.updated_at, expected_allocation_updated_at: snapshot.allocation.updated_at,
    expected_context_version: snapshot.context_version, confirm_change: true as const };
  return freezeEngineeringRequest(mode.action === 'set_visibility' ? { ...common, action: 'set_visibility', visibilidade: mode.visibilidade } : { ...common, action: mode.action });
}
export function availabilityMatchesContext(snapshot: CellAvailabilitySnapshot, project: { id: string; updated_at?: unknown }, allocation: {
  id: string; projeto_id?: unknown; celula_id?: unknown; updated_at?: unknown; retirada?: unknown; visibilidade?: unknown;
}) {
  return snapshot.project.id === project.id && snapshot.project.updated_at === project.updated_at && snapshot.allocation.id === allocation.id
    && snapshot.allocation.projeto_id === allocation.projeto_id && snapshot.allocation.celula_id === allocation.celula_id
    && snapshot.allocation.updated_at === allocation.updated_at && snapshot.allocation.retirada === (allocation.retirada === true)
    && snapshot.allocation.visibilidade === allocation.visibilidade;
}
