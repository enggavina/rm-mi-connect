import type { WebAccess } from './auth-policy';
import type { WorkshopRead } from './workshop-read-policy';

type WorkshopSession = Pick<Extract<WebAccess, { state: 'authenticated' }>, 'client' | 'sso'>;

export async function readWorkshopOperations(access: WorkshopSession): Promise<WorkshopRead | undefined> {
  if (!access.sso) return undefined;
  const { ssoWorkshopRead } = await import('./sso-bridge');
  return ssoWorkshopRead(access.sso, access.client);
}
