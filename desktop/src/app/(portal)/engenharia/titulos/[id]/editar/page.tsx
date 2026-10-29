import { notFound, redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getEngineeringMatrix, getPhotoTitle } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { EngineeringTitleEditor } from '@/components/web/engineering-title-editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function EditarTituloFoto({ params }: { params: Promise<{ id: string }> }) {
  const access = await requireWebUser(['em.engineering.read', 'em.engineering.manage']); if (!canManageEngineering(access)) redirect('/acesso?motivo=permissao'); const { id } = await params;
  const [entry, { cells }] = await Promise.all([getPhotoTitle(id), getEngineeringMatrix()]); if (!entry) notFound();
  return <><a className="back-link" href="/engenharia/titulos"><Icon name="back" size={15} />Voltar para títulos de fotos</a><PageHeading eyebrow="ENGENHARIA" title="Editar título de foto" description="O escopo e as fotos existentes permanecem preservados." /><section className="panel"><div className="panel-content"><EngineeringTitleEditor key={`${id}:${entry.updated_at}`} cells={cells} entry={entry} /></div></section></>;
}
