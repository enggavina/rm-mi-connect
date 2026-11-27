import type { WebAccess } from './auth-policy';
import type { WorkshopRead, WorkshopReadResource } from './workshop-read-policy';

type WorkshopSession = Pick<Extract<WebAccess, { state: 'authenticated' }>, 'client' | 'sso'>;

export async function readWorkshopOperations(access: WorkshopSession): Promise<WorkshopRead | undefined> {
  if (!access.sso) return undefined;
  const { ssoWorkshopRead } = await import('./sso-bridge');
  return ssoWorkshopRead(access.sso, access.client);
}

export async function readProjectDetail(client: WorkshopSession['client'], read: WorkshopRead | undefined,
  resource: WorkshopReadResource, legacyRpc: string, args: Record<string, unknown>) {
  return read ? { data: await read(resource, args), error: null } : client.rpc(legacyRpc, args);
}
