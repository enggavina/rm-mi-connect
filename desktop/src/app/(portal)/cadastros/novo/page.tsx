import { notFound, redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { CatalogEditor } from '@/components/web/catalog-editor';
import { canManageCatalogs, catalogLabels, editableKind } from '@/components/web/catalog-model';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function NovoCadastro({ searchParams }: { searchParams: Promise<{ kind?: string | string[] }> }) {
  const kind = editableKind((await searchParams).kind); if (!kind) notFound();
  const access = await requireWebUser(['em.catalogs.read', 'em.catalogs.manage']);
  if (!canManageCatalogs(access)) redirect('/acesso?motivo=permissao');
  const label = catalogLabels[kind];
  return <><a className="back-link" href={`/cadastros?kind=${kind}`}><Icon name="back" size={15} />Voltar para {label.plural.toLocaleLowerCase('pt-BR')}</a>
    <PageHeading eyebrow="CADASTROS" title={label.create} description="Preencha os dados que serão compartilhados com a operação da oficina." />
    <section className="panel"><div className="panel-header"><h2>Dados do cadastro</h2></div><div className="panel-content"><CatalogEditor kind={kind} /></div></section>
  </>;
}
