'use client';

import { useState } from 'react';
import type { WebRow } from '@/server/web/data';
import type { CellAvailabilitySnapshot } from '@/server/web/cell-availability-data';
import { CellEditor } from './editor';
import { CellAvailabilityEditor } from './cell-availability-editor';
import { EngineeringReloadLink } from './engineering-save';

/** The two editors cannot hold a pending attempt for the same allocation together. */
export function AllocationPlanningPanel({ projectId, allocation, cells, forms, users, snapshot, canManage, canPlan, destination, current = true }: {
  projectId: string; allocation: WebRow; cells: WebRow[]; forms: WebRow[]; users: WebRow[]; snapshot: CellAvailabilitySnapshot | null;
  canManage: boolean; canPlan: boolean; destination: string; current?: boolean;
}) {
  const [planningActive, setPlanningActive] = useState(false), [availabilityActive, setAvailabilityActive] = useState(false);
  return <div data-allocation-planning={allocation.id}>
    {canPlan && current && snapshot && !allocation.retirada && !['finalizado', 'n_a'].includes(allocation.status ?? '') && <CellEditor projectId={projectId} allocation={allocation}
      cells={cells} forms={forms} users={users} destination={destination} disabled={availabilityActive} onInteractionChange={setPlanningActive} />}
    {!current && <p className="notice" role="status">A alocação mudou durante a consulta. <EngineeringReloadLink href={destination}>Recarregar planejamento e disponibilidade</EngineeringReloadLink> antes de editar.</p>}
    {snapshot ? <CellAvailabilityEditor snapshot={snapshot} canManage={canManage && current} destination={destination} disabled={planningActive} onInteractionChange={setAvailabilityActive} />
      : <p className="notice" role="status">A disponibilidade desta célula não está mais disponível. <EngineeringReloadLink href={destination}>Recarregar a célula</EngineeringReloadLink> para conferir seu estado.</p>}
  </div>;
}
