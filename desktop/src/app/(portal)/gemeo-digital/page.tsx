import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { WorkshopClient } from '@/components/workshop/workshop-client';

export default async function GemeoDigitalPage() {
  const session = await requireWebUser('em.planning.read');
  if (!hasWebCapability(session, 'em.projects.read')) return <p className="notice">Seu acesso precisa permitir a consulta de projetos e planejamento para abrir o gêmeo digital.</p>;
  return <WorkshopClient />;
}
