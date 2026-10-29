import { Icon, type IconName } from './icons';
export function PageHeading({ eyebrow, title, description, actions }: { eyebrow?: string; title: string; description?: string; actions?: React.ReactNode }) {
  return <div className="page-heading"><div>{eyebrow && <p className="eyebrow">{eyebrow}</p>}<h1>{title}</h1>{description && <p className="page-description">{description}</p>}</div>{actions && <div className="heading-actions">{actions}</div>}</div>;
}
export function Stat({ label, value, detail, icon, accent = false }: { label: string; value: number | string; detail?: string; icon: IconName; accent?: boolean }) {
  return <div className={`stat ${accent ? 'stat-accent' : ''}`}><div className="stat-top"><span>{label}</span><Icon name={icon} size={18} /></div><strong>{typeof value === 'number' ? value.toLocaleString('pt-BR') : value}</strong>{detail && <small>{detail}</small>}</div>;
}
const labels: Record<string, string> = {
  administrador: 'Administrador', padr_o: 'Padrão', mobile: 'Operador mobile', cliente: 'Cliente', auditor: 'Auditor', vendedor: 'Vendedor',
  em_an_lise: 'Em análise', aprovado: 'Aprovado', direcionado: 'Em revisão', reprovado: 'Reprovado', nulo: 'Pendente', peritagem: 'Peritagem', executando: 'Executando', em_dia: 'Executando', pendente: 'Pendente', finalizado: 'Finalizado', atrasado: 'Atrasado', retornado: 'Retornado', n_a: 'N/A',
  equipamento_inspecionado: 'Equipamento inspecionado', aguardando_aprova__o: 'Aguardando aprovação', sem_status: 'Sem status', revis_o_comercial: 'Revisão comercial', revis_o_comercial0: 'Revisão comercial', finalizando_para_faturar: 'Finalizado para faturar', susponso__hold_: 'Suspenso', aguardando_recebimento_equipamento: 'Aguardando recebimento', equipamento_em_inspe__o: 'Em inspeção', sem_previs_o: 'Sem previsão', investiga__o_de_garantia: 'Investigação de garantia', executando_com_garantia: 'Executando com garantia', cancelado: 'Cancelado',
  para_execu__o: 'Para execução', liberado_para_montagem: 'Liberado para montagem', liberado_para_ensaios_parciais: 'Liberado para ensaios', liberado_para_impregna__o: 'Liberado para impregnação', ativo: 'Ativo', inativo: 'Inativo', sim: 'Sim', n_o: 'Não', c___placa: 'Com placa', s___placa: 'Sem placa', obrigat_ria: 'Obrigatória', complementar: 'Complementar',
};
export const display = (value: unknown): string => value == null || value === '' ? 'Não informado' : labels[String(value)] || String(value).replace(/_/g, ' ');
export function Status({ value, label }: { value?: string | null; label?: string }) {
  const tone = ['aprovado', 'finalizado', 'ativo', 'executando', 'em_dia'].includes(value || '') ? 'green' : ['reprovado', 'atrasado', 'cancelado', 'inativo'].includes(value || '') ? 'red' : ['direcionado', 'retornado', 'aguardando_aprova__o', 'em_an_lise'].includes(value || '') ? 'amber' : 'neutral';
  return <span className={`status status-${tone}`}><span />{label || display(value)}</span>;
}
export const date = (value: unknown, withTime = false): string => {
  if (!value) return '—'; const parsed = new Date(String(value)); if (Number.isNaN(parsed.getTime())) return '—';
  return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}), timeZone: 'America/Sao_Paulo' }).format(parsed);
};
export function Empty({ title, detail, icon = 'folder', children }: { title: string; detail?: string; icon?: IconName; children?: React.ReactNode }) {
  return <div className="empty-state"><span className="empty-icon"><Icon name={icon} size={26} /></span><h3>{title}</h3>{detail && <p>{detail}</p>}{children}</div>;
}
export function Pagination({ page, pageSize, total, base, filters = {} }: { page: number; pageSize: number; total: number; base: string; filters?: Record<string, string | undefined> }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  const href = (next: number) => { const params = new URLSearchParams(Object.entries(filters).filter((entry): entry is [string, string] => !!entry[1])); params.set('page', String(next)); return `${base}?${params}`; };
  return <div className="pagination"><span>{total ? `${((page - 1) * pageSize + 1).toLocaleString('pt-BR')}–${Math.min(page * pageSize, total).toLocaleString('pt-BR')} de ${total.toLocaleString('pt-BR')} registros` : 'Nenhum registro'}</span><div>{page > 1 ? <a className="button small secondary" href={href(page - 1)}>Anterior</a> : <span className="button small secondary disabled">Anterior</span>}<span className="page-number">{page} / {pages}</span>{page < pages ? <a className="button small secondary" href={href(page + 1)}>Próxima<Icon name="chevron" size={14} /></a> : <span className="button small secondary disabled">Próxima</span>}</div></div>;
}
export function Details({ values }: { values: [string, unknown][] }) {
  return <dl className="details-grid">{values.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value == null || value === '' ? '—' : String(value)}</dd></div>)}</dl>;
}
