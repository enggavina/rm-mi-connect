import type { WebAccess } from './auth-policy';
import { WorkshopContextError } from './workshop-context';
import type { WorkshopRead } from './workshop-read-policy';

type WorkshopSession = Pick<Extract<WebAccess, { state: 'authenticated' }>, 'client' | 'sso'>;

/** Activation follows origin coverage for all project and cell writers. */
export function workshopOperationReadsEnabled() {
  return process.env.EM_WORKSHOP_OPERATION_READS === 'true';
}

export function workshopGanttWritesEnabled() {
  return workshopOperationReadsEnabled() && process.env.EM_WORKSHOP_GANTT_WRITES === 'true';
}

export async function readWorkshopOperations(access: WorkshopSession): Promise<WorkshopRead | undefined> {
  if (!workshopOperationReadsEnabled()) return undefined;
  if (!access.sso) throw new WorkshopContextError('WORKSHOP_FORBIDDEN');
  const { ssoWorkshopRead } = await import('./sso-bridge');
  return ssoWorkshopRead(access.sso, access.client);
}
