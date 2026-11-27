import { createWebData } from './data';
import { requireWebUser } from './auth';
import { ssoWorkshopRead } from './sso-bridge';

export async function editorChoices(scope: 'project' | 'planning' = 'project') {
  const session = await requireWebUser(scope === 'project' ? 'em.projects.manage' : 'em.planning.manage');
  return createWebData(session.client, session.sso?.capabilities, session.sso && ssoWorkshopRead(session.sso, session.client)).editorChoices(scope);
}
