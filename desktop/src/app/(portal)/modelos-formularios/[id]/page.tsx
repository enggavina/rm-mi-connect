import { notFound } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getFormTemplate, getFormTemplateChoices } from '@/server/web/form-template-data';
import { canManageFormTemplates } from '@/components/web/form-template-model';
import { FormTemplateEditor } from '@/components/web/form-template-editor';
import { FormTemplatePreview } from '@/components/web/form-template-preview';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function Modelo({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ resultado?: string }> }) {
  const access = await requireWebUser('em.form_templates.read'), { id } = await params;
  const [snapshot, choices] = await Promise.all([getFormTemplate(id), getFormTemplateChoices()]); if (!snapshot) notFound();
  const { draft, publication } = snapshot, managing = canManageFormTemplates(access), published = draft.state === 'published', result = (await searchParams).resultado;
  return <><a href="/modelos-formularios" className="back-link"><Icon name="back" size={15} />Voltar aos modelos</a><PageHeading eyebrow={published ? 'PUBLICADO · SOMENTE CONSULTA' : 'RASCUNHO'} title={draft.content.titulo || 'Novo modelo de formulário'} description={published ? 'Esta versão está publicada. Crie uma nova versão para alterar o conteúdo.' : 'Edite o conteúdo, salve o rascunho e confira a prévia antes de publicar.'} actions={published && draft.published_form_id && managing ? <a className="button" href={`/modelos-formularios/novo?base=${draft.published_form_id}&modo=version`}><Icon name="plus" size={15} />Nova versão</a> : undefined} />
    {['salvo', 'criado', 'publicado'].includes(result ?? '') && <div className="notice success" role="status">{result === 'publicado' ? 'Versão publicada.' : result === 'salvo' ? 'Rascunho salvo.' : 'Rascunho criado.'}</div>}
    {published && <div className="notice">Versão {publication?.version ?? 'publicada'}. Os formulários anteriores e projetos existentes permanecem preservados. Este formulário tem sua própria sequência de registros.<p>{draft.published_form_id && <a className="text-link" href={`/modelos-formularios/publicados/${draft.published_form_id}`}>Consultar formulário publicado</a>}{access.sso?.capabilities.includes('em.engineering.read') || !access.sso ? <> · <a className="text-link" href="/engenharia">Abrir Engenharia para vincular aos roteiros</a></> : null}</p></div>}
    {!managing && !published && <div className="notice">Consulta do rascunho. A edição e publicação exigem permissão de gestão e perfil administrador.</div>}
    {managing && !published ? <FormTemplateEditor key={`${id}:${draft.updated_at}`} draft={draft} choices={choices} /> : <FormTemplatePreview content={draft.content} choices={choices} />}
  </>;
}
