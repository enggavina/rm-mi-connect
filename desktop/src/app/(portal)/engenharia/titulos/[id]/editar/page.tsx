import { notFound, redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getEngineeringMatrix, getPhotoTitle } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { EngineeringTitleEditor } from '@/components/web/engineering-title-editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function EditarTituloFoto({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const access = await requireWebUser(['em.engineering.read', 'em.engineering.manage']); if (!canManageEngineering(access)) redirect('/acesso?motivo=permissao'); const { id } = await params;
  const [entry, { cells }] = await Promise.all([getPhotoTitle(id), getEngineeringMatrix()]); if (!entry) notFound();
  const deleting = (await searchParams).acao === 'excluir';
  return <><a className="back-link" href="/engenharia/titulos"><Icon name="back" size={15} />Voltar para títulos de fotos</a><PageHeading eyebrow="ENGENHARIA" title={deleting ? 'Excluir título de foto' : 'Editar título de foto'} description="O escopo e as fotos existentes permanecem preservados." /><section className="panel"><div className="panel-content"><EngineeringTitleEditor key={`${id}:${entry.updated_at}:${deleting}`} cells={cells} entry={entry} initialDeleting={deleting} /></div></section></>;
}
