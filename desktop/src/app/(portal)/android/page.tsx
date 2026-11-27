import { redirect } from 'next/navigation';
import { Empty, PageHeading } from '@/components/web/ui';
import { androidPilot } from '@/server/web/android-pilot';
import { androidPilotRelease as release } from '@/shared/android-pilot-release';

export default async function AndroidInstallerPage() {
  const status = await androidPilot.authorize();
  if (status === 401) redirect('/login');
  if (status === 403) redirect('/acesso?motivo=permissao');

  return <>
    <PageHeading title="Aplicativo Android" description="Instalador do EM para os dispositivos do piloto da oficina." />
    <section className="panel">
      {status === 200 ? <>
        <h2>EM · Versão {release.version}</h2>
        <p>Android ARM64 · {new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 }).format(release.bytes / 1_000_000)} MB</p>
        <p>Instale sobre a versão existente para manter os rascunhos e envios pendentes.</p>
        <a href="/api/web/android/instalador" className="button primary">Baixar APK</a>
      </> : <Empty title="Instalador indisponível" detail="Abra esta página novamente para confirmar o vínculo com a oficina." icon="settings" />}
    </section>
  </>;
}
