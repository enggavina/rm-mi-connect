import { redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getEngineeringChoices } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { EngineeringEditor } from '@/components/web/engineering-editor';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function NovoRoteiro({ searchParams }: { searchParams: Promise<{ tipo?: string | string[] }> }) {
  const access = await requireWebUser(['em.engineering.read', 'em.engineering.manage']); if (!canManageEngineering(access)) redirect('/acesso?motivo=permissao');
  const choices = await getEngineeringChoices(); const param = (await searchParams).tipo; const typeId = typeof param === 'string' && choices.types.some(type => type.id === param) ? param : '';
  return <><a className="back-link" href={`/engenharia${typeId ? `?tipo=${typeId}` : ''}`}><Icon name="back" size={15} />Voltar para engenharia</a><PageHeading eyebrow="ENGENHARIA" title="Adicionar célula ao roteiro" description="Defina a configuração da célula para este tipo de equipamento." /><section className="panel"><div className="panel-content"><EngineeringEditor choices={choices} initialTypeId={typeId} /></div></section></>;
}
