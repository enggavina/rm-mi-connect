import { notFound, redirect } from 'next/navigation';
import { requireWebUser } from '@/server/web/auth';
import { getPublishedFormTemplate } from '@/server/web/form-template-data';
import { canManageFormTemplates } from '@/components/web/form-template-model';
import { FormTemplateCreate } from '@/components/web/form-template-create';
import { PageHeading } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function NovoModelo({ searchParams }: { searchParams: Promise<{ base?: string | string[]; modo?: string }> }) {
  const access = await requireWebUser(['em.form_templates.read', 'em.form_templates.manage']); if (!canManageFormTemplates(access)) redirect('/acesso?motivo=permissao');
  const params = await searchParams, base = typeof params.base === 'string' ? params.base : undefined;
  const source = base ? await getPublishedFormTemplate(base) : null; if (base && !source) notFound();
  return <><a href="/modelos-formularios" className="back-link"><Icon name="back" size={15} />Voltar aos modelos</a><PageHeading eyebrow="MODELOS DE FORMULÁRIO" title={source ? params.modo === 'version' ? 'Criar nova versão' : 'Copiar modelo' : 'Criar modelo de formulário'} description="Comece por um rascunho e confira o conteúdo antes de publicar." /><section className="panel"><div className="panel-content"><FormTemplateCreate source={source ? { id: source.form.id, titulo: source.form.titulo, version: source.version } : undefined} initialKind={params.modo === 'version' ? 'version' : 'copy'} /></div></section></>;
}
