import { Suspense } from 'react';
import { PortalShell } from '@/components/web/shell';
import { requireWebUser } from '@/server/web/auth';
import Loading from './loading';
export const dynamic = 'force-dynamic';
export default async function PortalLayout({ children }: { children: React.ReactNode }) {
  const session = await requireWebUser('em.portal.read');
  return <PortalShell profile={session.profile} capabilities={session.sso?.capabilities}><Suspense fallback={<main id="conteudo" className="workspace"><Loading /></main>}><main id="conteudo" className="workspace">{children}</main></Suspense><footer className="portal-footer"><span>EM <span>·</span> MI Electric Brasil</span><span>Gestão da operação</span></footer></PortalShell>;
}
