import { notFound, redirect } from 'next/navigation';
import { getCatalogEntry } from '@/server/web/data';
import { requireWebUser } from '@/server/web/auth';
import { CatalogEditor } from '@/components/web/catalog-editor';
import { canManageCatalogs, catalogLabels, editableKind } from '@/components/web/catalog-model';
import { Empty, PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function EditarCadastro({ params }: { params: Promise<{ kind: string; id: string }> }) {
  const route = await params; const kind = editableKind(route.kind); if (!kind) notFound();
  const access = await requireWebUser(['em.catalogs.read', 'em.catalogs.manage']);
  if (!canManageCatalogs(access)) redirect('/acesso?motivo=permissao');
  const entry = await getCatalogEntry(kind, route.id); if (!entry) notFound();
  const label = catalogLabels[kind];
  return <><a className="back-link" href={`/cadastros?kind=${kind}`}><Icon name="back" size={15} />Voltar para {label.plural.toLocaleLowerCase('pt-BR')}</a>
    <PageHeading eyebrow="CADASTROS" title={`Editar ${label.singular}`} description={entry.nome} />
    <section className="panel"><div className="panel-header"><h2>Dados do cadastro</h2></div><div className="panel-content">{typeof entry.updated_at === 'string' ? <CatalogEditor key={`${entry.id}:${entry.updated_at}`} kind={kind} entry={entry} /> : <Empty title="Não foi possível carregar este cadastro" detail="Recarregue a página para consultar os dados atuais." />}</div></section>
  </>;
}
