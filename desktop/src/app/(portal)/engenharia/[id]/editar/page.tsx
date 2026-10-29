import { notFound, redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getEngineeringChoices, getEngineeringEntry } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { EngineeringEditor } from '@/components/web/engineering-editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function EditarRoteiro({ params }: { params: Promise<{ id: string }> }) {
  const access = await requireWebUser(['em.engineering.read', 'em.engineering.manage']); if (!canManageEngineering(access)) redirect('/acesso?motivo=permissao');
  const { id } = await params, entry = await getEngineeringEntry(id); if (!entry) notFound(); const choices = await getEngineeringChoices(entry);
  const cell = choices.cells.find(row => row.id === entry.matrix.celula_id), type = choices.types.find(row => row.id === entry.matrix.tipo_equipamento_id);
  return <><a className="back-link" href={`/engenharia?tipo=${entry.matrix.tipo_equipamento_id}`}><Icon name="back" size={15} />Voltar para engenharia</a><PageHeading eyebrow="ENGENHARIA" title="Editar roteiro" description={`${type?.nome || 'Tipo não disponível'} · ${cell?.nome || 'Célula não disponível'}`} /><section className="panel"><div className="panel-content"><EngineeringEditor key={`${id}:${entry.matrix.updated_at}`} snapshot={entry} choices={choices} /></div></section></>;
}
