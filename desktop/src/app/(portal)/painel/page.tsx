import { PageHeading, Empty } from '@/components/web/ui';
import { requireWebUser } from '@/server/web/auth';
import { HomeModules } from '@/components/web/home-modules';
import { portalHomeModules } from '@/components/web/navigation';
import { canUseOperationValidation } from '@/server/operation/validation';

export default async function Painel() {
  const session = await requireWebUser('em.portal.read');
  const hasModules = portalHomeModules(session.sso?.capabilities).length > 0;
  return <>
    <PageHeading eyebrow="EM · MI ELECTRIC BRASIL" title="O que você precisa fazer?" description="Escolha uma funcionalidade para começar. O acompanhamento da operação e o gêmeo digital 3D estão nos atalhos do menu lateral."
      actions={canUseOperationValidation({ state: 'authenticated', ...session }) && <a href="/operacao/validacao" className="button">Validar EM Operacional</a>} />
    <HomeModules capabilities={session.sso?.capabilities} />
    {!hasModules && <section className="panel"><Empty title="Seu acesso ao portal está confirmado" detail="As áreas disponíveis dependem das funcionalidades autorizadas para sua conta na Central de Acessos." icon="settings" /></section>}
  </>;
}
