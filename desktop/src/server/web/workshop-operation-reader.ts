import type { WebAccess } from './auth-policy';
import { WorkshopContextError } from './workshop-context';
import type { WorkshopRead } from './workshop-read-policy';

type WorkshopSession = Pick<Extract<WebAccess, { state: 'authenticated' }>, 'client' | 'sso'>;

/** Preserve the rollout variable for project and cell updates. */
export function workshopRootEditsEnabled() {
  return process.env.EM_WORKSHOP_OPERATION_READS === 'true';
}

export async function readWorkshopOperations(access: WorkshopSession): Promise<WorkshopRead | undefined> {
  if (!access.sso) {
    if (workshopRootEditsEnabled()) throw new WorkshopContextError('WORKSHOP_FORBIDDEN');
    return undefined;
  }
  const { ssoWorkshopRead } = await import('./sso-bridge');
  return ssoWorkshopRead(access.sso, access.client);
}
