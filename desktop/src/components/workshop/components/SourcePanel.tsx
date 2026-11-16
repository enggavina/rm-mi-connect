import { Database, Info, RefreshCw, ShieldCheck } from 'lucide-react';
import type { WorkshopSnapshot } from '../domain/types';
import { formatDate, formatTime, isWorkshopActiveOrder } from '../domain/metrics';
export default function SourcePanel({ snapshot, loading, error, refresh, onBack }: { source: 'supabase'; snapshot: WorkshopSnapshot | null; loading: boolean; error: string | null; refresh: () => void; onBack: () => void }) {
  const active = snapshot?.orders.filter(order => isWorkshopActiveOrder(order, snapshot.referenceAt)).length ?? 0;
  return <section className="source-page">
    <button type="button" className="secondary-button" onClick={onBack}>Voltar à oficina 3D</button>
    <span className="eyebrow">DADOS DA OFICINA</span><h2>A mesma operação, em uma nova visão.</h2>
    <p className="source-intro">O gêmeo digital consulta a mesma base do EM, usada pelo aplicativo, projetos e planejamento. Os registros enviados pelo aplicativo aparecem após a sincronização e a atualização desta consulta.</p>
    <div className="connection-status"><div><span className={`connection-light ${error ? 'error' : ''}`}/><div><strong>{loading ? 'Consultando a oficina…' : error ? 'Dados não atualizados' : snapshot ? 'Leitura recebida do EM' : 'Aguardando consulta'}</strong><p>{error ?? (snapshot ? `${active} projetos em andamento · ${snapshot.cells?.length ?? 0} células · leitura em ${formatDate(snapshot.fetchedAt, true)} às ${formatTime(snapshot.fetchedAt)}` : 'Nenhuma leitura disponível.')}</p></div></div><button className="secondary-button" onClick={refresh} disabled={loading}><RefreshCw size={15} className={loading ? 'spin' : ''}/>Atualizar</button></div>
    <div className="source-grid">
      <article><Database size={20}/><h3>Projetos e planejamento do EM</h3><p>Equipamento, cliente, etapas, responsáveis, prazos e bloqueios são lidos dos cadastros atuais. Não há uma cópia de projetos ou uma segunda sincronização com outro sistema.</p></article>
      <article><ShieldCheck size={20}/><h3>Seu acesso atual</h3><p>Esta área usa a sessão do portal e as permissões de consulta de projetos e planejamento. A visão 3D é somente leitura; alterações continuam nas telas do projeto e no Gantt.</p></article>
      <article><Info size={20}/><h3>Mapa de processo</h3><p>As células organizam as atividades da oficina. A posição no mapa representa o processo, sem afirmar a localização física, a presença de pessoas ou a capacidade disponível.</p><p>Pessoas, logística, arquitetura e bancadas são ilustrações. A vista Localização exibe somente vínculos físicos registrados.</p></article>
    </div>
    {snapshot && <details className="data-warnings" open><summary>Critérios e qualidade da leitura</summary><ul>{snapshot.warnings.map(warning => <li key={warning}>{warning}</li>)}</ul></details>}
  </section>;
}
