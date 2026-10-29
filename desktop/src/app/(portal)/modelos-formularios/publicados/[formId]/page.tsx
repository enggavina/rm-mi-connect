import { notFound } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getPublishedFormTemplate, getFormTemplateChoices } from '@/server/web/form-template-data';
import { canManageFormTemplates } from '@/components/web/form-template-model';
import { FormTemplatePreview } from '@/components/web/form-template-preview';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function Publicado({ params }: { params: Promise<{ formId: string }> }) {
  const access = await requireWebUser('em.form_templates.read'), { formId } = await params;
  const [data, choices] = await Promise.all([getPublishedFormTemplate(formId), getFormTemplateChoices()]); if (!data) notFound();
  const managing = canManageFormTemplates(access);
  return <><a href="/modelos-formularios" className="back-link"><Icon name="back" size={15} />Voltar aos modelos</a><PageHeading eyebrow={data.version == null ? 'MODELO LEGADO · SOMENTE CONSULTA' : `PUBLICADO · VERSÃO ${data.version}`} title={data.form.titulo} description="Consulte o conteúdo utilizado pela operação. Alterações são preparadas em um novo rascunho." actions={managing ? <><a className="button secondary" href={`/modelos-formularios/novo?base=${formId}&modo=copy`}>Copiar base</a><a className="button" href={`/modelos-formularios/novo?base=${formId}&modo=version`}><Icon name="plus" size={15} />Nova versão</a></> : undefined} /><FormTemplatePreview content={data.content} choices={choices} /></>;
}
