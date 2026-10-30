import { notFound, redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getProjectQr } from '@/server/web/project-qr-data';
import type { ProjectQrProject } from '@/server/web/project-qr-policy';
import { ProjectQrLabel } from '@/components/web/project-qr-label';
import { PageHeading } from '@/components/web/ui';
import { EngineeringReloadLink } from '@/components/web/engineering-save';
import { Icon } from '@/components/web/icons';
import s from '@/components/web/project-qr.module.css';

export default async function IdentificacaoProjeto({ params }: { params: Promise<{ id: string }> }) {
  const [{ id: rawId }, session] = await Promise.all([params, requireWebUser(['em.portal.read', 'em.projects.read'])]);
  if (!['administrador', 'padr_o', 'auditor'].includes(session.profile.perfil)) redirect('/acesso?motivo=permissao');
  const id = rawId.toLowerCase();
  let project: ProjectQrProject | null = null, unavailable = false;
  try { project = await getProjectQr(id); } catch { unavailable = true; }
  if (!project && !unavailable) notFound();
  return <div className={s.page} data-project-qr-page>
    <div className={s.screenOnly}><a className="back-link" href={`/projetos/${id}`}><Icon name="back" size={15} />Voltar ao projeto</a><div className={s.heading}><PageHeading eyebrow="IDENTIFICAÇÃO DO PROJETO" title="Identificação por QR" description="Etiqueta para localizar o projeto no aplicativo EM." /></div></div>
    {project ? <ProjectQrLabel key={project.id} project={project} /> : <section className="panel"><div className={s.unavailable}><p className="notice" role="status">Não foi possível conferir a identificação deste projeto. <EngineeringReloadLink href={`/projetos/${id}/qr`}>Recarregar dados</EngineeringReloadLink> para tentar novamente.</p></div></section>}
  </div>;
}
