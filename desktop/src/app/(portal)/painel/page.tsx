import Link from 'next/link';
import { getOverview } from '@/server/web/data';
import { PageHeading, Stat, Status, Empty, date } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function Painel() {
  const { access, counts, recentProjects, tasks } = await getOverview();
  return <>
    <PageHeading eyebrow="O DIA A DIA DA OPERAÇÃO" title="Visão geral" description="Acompanhe os projetos, os prazos e os registros que precisam da sua atenção." actions={access.projects && <Link className="button secondary" href="/projetos">Ver projetos<Icon name="arrow" size={16} /></Link>} />
    <div className="stats-grid">
      {access.projects && <Stat label="Projetos em operação" value={counts.activeProjects ?? 0} detail={`${counts.projects} projetos na base`} icon="folder" />}
      {access.forms && <Stat label="Formulários em análise" value={counts.awaitingReview ?? 0} detail="Registros aguardando avaliação" icon="clipboard" accent />}
      {access.planning && <Stat label="Células com prazo vencido" value={counts.overdueCells ?? 0} detail="Etapas visíveis ainda não finalizadas" icon="clock" />}
      {access.documents && <Stat label="Documentos e anexos" value={counts.documents ?? 0} detail="Arquivos vinculados aos projetos" icon="file" />}
    </div>
    {!Object.values(access).some(Boolean) && <section className="panel"><Empty title="Seu acesso ao portal está confirmado" detail="As áreas disponíveis dependem das funcionalidades autorizadas para sua conta na Central de Acessos." icon="settings" /></section>}
    <div className="two-columns">
      {access.projects && <section className="panel"><div className="panel-header"><div><h2>Projetos atualizados recentemente</h2><p>Acesso direto ao equipamento e ao histórico da operação.</p></div><Link className="text-link" href="/projetos">Ver todos<Icon name="chevron" size={13} /></Link></div>
        {recentProjects.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Projeto / equipamento</th><th>Cliente</th><th>Status PCP</th><th className="table-action">Abrir</th></tr></thead><tbody>{recentProjects.map(project => <tr key={project.id}>
          <td><Link className="table-title" href={`/projetos/${project.id}`}>{project.numero ? `OS ${project.numero.trim()}` : 'Recebimento sem OS'}</Link><span className="table-subtitle">{project.descricao_equipamento || project.nome || 'Equipamento não descrito'}</span></td>
          <td>{project.cliente_nome || 'Não informado'}</td><td><Status value={project.status_pcp} /></td><td className="table-action"><Link href={`/projetos/${project.id}`} aria-label={`Abrir projeto ${project.numero || 'em recebimento'}`}><Icon name="arrow" size={15} /></Link></td>
        </tr>)}</tbody></table></div> : <Empty title="Nenhum projeto cadastrado" detail="Os recebimentos enviados pelo aplicativo e os projetos criados no planejamento aparecerão aqui." />}
      </section>}
      {(access.forms || access.planning) && <section className="panel"><div className="panel-header"><div><h2>Precisa de atenção</h2><p>Registros e prazos nas áreas autorizadas.</p></div><Icon name="alert" size={18} style={{ color: '#aa813f' }} /></div>
        {tasks.length ? <div className="activity-list">{tasks.slice(0, 7).map(task => <Link href={task.href} className="activity-item" key={`${task.kind}:${task.id}`}><span className="activity-icon"><Icon name={task.kind === 'review' ? 'clipboard' : 'clock'} size={16} /></span><div><h3>{task.title}</h3><p>{task.kind === 'review' ? `OS ${task.numero_projeto_rm || 'não informada'} · ${date(task.updated_at)}` : `Prazo: ${date(task.data_limite)}`}</p><Status value={task.kind === 'review' ? 'em_an_lise' : 'atrasado'} /></div></Link>)}</div>
          : <Empty title="Nenhuma pendência encontrada" detail="Não há registros ou células com prazo vencido nas áreas disponíveis para sua conta." icon="check" />}
      </section>}
    </div>
    <section className="panel"><div className="panel-header"><div><h2>Da oficina ao acompanhamento</h2><p>As atividades enviadas pelos operadores ficam disponíveis nesta plataforma após a sincronização.</p></div>{access.planning && <Link className="button small secondary" href="/planejamento">Acompanhar células<Icon name="arrow" size={14} /></Link>}</div></section>
  </>;
}
