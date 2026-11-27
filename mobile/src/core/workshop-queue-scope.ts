import type { OutboxRow } from './types';

export type QueueScope = { actor: string; workshop: string };

/** An older row can be retried by its author. The server still has to prove
 * the office from the original payload. Never fill its missing origin here. */
export function queueMatchesWorkshop(row: Pick<OutboxRow, 'actor_id' | 'workshop_id'>, scope: QueueScope): boolean {
  return row.actor_id === scope.actor && (row.workshop_id == null || row.workshop_id === scope.workshop);
}
