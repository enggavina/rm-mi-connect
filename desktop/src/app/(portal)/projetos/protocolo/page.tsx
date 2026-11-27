import Link from 'next/link';
import { redirect } from 'next/navigation';
import { Details, Empty, PageHeading, Status, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import { androidOperationLabels, androidProtocolQuery, checkAndroidProtocol } from '@/server/web/android-protocol';
import { requireWebUser } from '@/server/web/auth';
import { hasWebCapability } from '@/server/web/auth-policy';
import { WorkshopContextError } from '@/server/web/workshop-context';
import { readWorkshopOperations } from '@/server/web/workshop-operation-reader';

export default async function AndroidProtocolPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const session = await requireWebUser(['em.projects.read', 'em.history.read']);
  if (!session.sso) redirect('/acesso?motivo=permissao');
  const { protocolo } = await searchParams;
  const parsed = androidProtocolQuery.safeParse(protocolo);
  let receipt: ReturnType<typeof checkAndroidProtocol> = null;
  let unavailable = false;

  if (parsed.success) {
    const read = await readWorkshopOperations(session);
    if (!read) redirect('/acesso?motivo=permissao');
    try {
      const capabilities = ['forms', 'photos', 'approvals', 'planning'] as const;
      const flags = Object.fromEntries(capabilities.map(topic => [topic, hasWebCapability(session, `em.${topic}.read`)]));
      receipt = checkAndroidProtocol(await read('android_protocol', { protocol: parsed.data, ...flags }), parsed.data);
    } catch (error) {
      if (!(error instanceof WorkshopContextError)) throw error;
      if (error.status === 401) redirect('/login');
      if (error.status === 403) redirect('/acesso?motivo=permissao');
      unavailable = true;
    }
  }

  return <>
    <Link className="back-link" href="/projetos"><Icon name="back" size={15} />Todos os projetos</Link>
    <PageHeading eyebrow="PROJETOS DA OFICINA" title="Protocolo do Android" description="Consulte o código exibido na confirmação do aplicativo para verificar se o registro chegou ao EM." />
    <section className="panel">
      <form action="/projetos/protocolo" className="filters">
        <div className="search-field"><Icon name="search" size={16} /><input name="protocolo" aria-label="Protocolo do Android"
          placeholder="Cole o protocolo do Android" defaultValue={typeof protocolo === 'string' ? protocolo.slice(0, 36) : ''}
          required maxLength={36} autoComplete="off" spellCheck={false} /></div>
        <button type="submit" className="button secondary">Consultar</button>
        {protocolo !== undefined && <Link href="/projetos/protocolo" className="button ghost">Limpar</Link>}
      </form>
      {unavailable && <div className="notice error" role="alert">Consulta temporariamente indisponível. Tente novamente.</div>}
      {protocolo !== undefined && !parsed.success && <div className="notice error" role="alert">Informe o código completo do protocolo.</div>}
      {parsed.success && !receipt && !unavailable && <Empty title="Protocolo não encontrado" detail="Confira o código e se o aplicativo já confirmou o envio." />}
      {receipt && <>
        <div className="panel-header"><h2>{androidOperationLabels[receipt.operation]}</h2>
          <Status value={receipt.phase === 'confirmed' ? 'finalizado' : 'pendente'} label={receipt.phase === 'confirmed' ? 'Envio confirmado' : 'Abertura confirmada · conclusão pendente'} />
        </div>
        <Details values={[
          ['Protocolo', receipt.protocol], ['Projeto', receipt.project_number ? `OS ${receipt.project_number}` : 'Recebimento sem OS'],
          ['Registrado em', date(receipt.recorded_at, true)],
          ...(receipt.last_retry_at ? [['Último reenvio confirmado', date(receipt.last_retry_at, true)] as [string, string]] : []),
        ]} />
        <div className="filters">
          <Link className="button secondary" href={`/projetos/${receipt.project_id}`}>Abrir projeto</Link>
          {receipt.form_record_id && <Link className="button secondary" href={`/formularios/${receipt.form_record_id}`}>Abrir formulário</Link>}
        </div>
      </>}
    </section>
  </>;
}
