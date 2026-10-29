import { PortalShell } from '@/components/web/shell';
import { requireWebUser } from '@/server/web/auth';
export const dynamic = 'force-dynamic';
export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const { profile } = await requireWebUser();
  return <PortalShell profile={profile}>{children}</PortalShell>;
}
