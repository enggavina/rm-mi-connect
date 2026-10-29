import Link from 'next/link';
import { redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { editorChoices } from '@/server/web/choices';
import { ProjectEditor } from '@/components/web/editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
export default async function NovoProjeto() {
  const { profile } = await requireWebUser(['em.projects.read', 'em.projects.manage']); if (!['administrador', 'padr_o'].includes(profile.perfil)) redirect('/projetos');
  const choices = await editorChoices();
  return <><Link className="back-link" href="/projetos"><Icon name="back" size={15} />Todos os projetos</Link><PageHeading eyebrow="PLANEJAMENTO" title="Novo projeto" description="Cadastre o projeto e o equipamento. Depois, defina quais células participarão da execução." /><section className="panel"><div className="panel-header"><h2>Dados do projeto</h2></div><div className="panel-content"><ProjectEditor {...choices} /></div></section></>;
}
