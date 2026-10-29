import { redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getEngineeringMatrix } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { EngineeringTitleEditor } from '@/components/web/engineering-title-editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function NovoTituloFoto() {
  const access = await requireWebUser(['em.engineering.read', 'em.engineering.manage']); if (!canManageEngineering(access)) redirect('/acesso?motivo=permissao'); const { cells } = await getEngineeringMatrix();
  return <><a className="back-link" href="/engenharia/titulos"><Icon name="back" size={15} />Voltar para títulos de fotos</a><PageHeading eyebrow="ENGENHARIA" title="Cadastrar título de foto" description="Escolha o escopo do título antes de usá-lo no roteiro." /><section className="panel"><div className="panel-content"><EngineeringTitleEditor cells={cells} /></div></section></>;
}
