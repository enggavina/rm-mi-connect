import { PortalShell } from '@/components/web/shell';
import { requireWebUser } from '@/server/web/auth';
export const dynamic = 'force-dynamic';
export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const session = await requireWebUser('em.portal.read');
  return <PortalShell profile={session.profile} capabilities={session.sso?.capabilities}>{children}</PortalShell>;
}
