import { notFound } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getEngineeringChoices, getEngineeringEntry } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { EngineeringDetail } from '@/components/web/engineering-detail';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function ConsultarRoteiro({ params }: { params: Promise<{ id: string }> }) {
  const access = await requireWebUser('em.engineering.read'); const { id } = await params; const entry = await getEngineeringEntry(id); if (!entry) notFound();
  const choices = await getEngineeringChoices(entry); const cell = choices.cells.find(row => row.id === entry.matrix.celula_id), type = choices.types.find(row => row.id === entry.matrix.tipo_equipamento_id);
  return <><a className="back-link" href={`/engenharia?tipo=${entry.matrix.tipo_equipamento_id}`}><Icon name="back" size={15} />Voltar para engenharia</a><PageHeading eyebrow="ENGENHARIA" title={cell?.nome || 'Configuração do roteiro'} description={type?.nome || 'Tipo de equipamento não disponível'} actions={canManageEngineering(access) ? <a className="button" href={`/engenharia/${id}/editar`}><Icon name="edit" size={15} />Editar roteiro</a> : undefined} /><EngineeringDetail entry={entry} choices={choices} /></>;
}
