import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { getProject } from '@/server/web/data';
import { requireWebUser } from '@/server/web/auth';
import { editorChoices } from '@/server/web/choices';
import { ProjectEditor } from '@/components/web/editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
export default async function EditarProjeto({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params; const { profile } = await requireWebUser(['em.projects.read', 'em.projects.manage']); if (!['administrador', 'padr_o'].includes(profile.perfil)) redirect(`/projetos/${id}`);
  const [data, choices] = await Promise.all([getProject(id), editorChoices()]); if (!data) notFound();
  return <><Link className="back-link" href={`/projetos/${id}`}><Icon name="back" size={15} />Voltar ao projeto</Link><PageHeading eyebrow={data.project.numero ? `OS ${data.project.numero}` : 'RECEBIMENTO'} title="Editar projeto" description="As alterações são conferidas com a versão atual antes de salvar, preservando o trabalho enviado pelos operadores." /><section className="panel"><div className="panel-header"><h2>Dados e prazos do projeto</h2></div><div className="panel-content"><ProjectEditor {...choices} project={data.project} hasAllocations={data.hasAllocations} /></div></section></>;
}
