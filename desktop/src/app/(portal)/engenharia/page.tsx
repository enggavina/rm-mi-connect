import { requireWebUser } from '@/server/web/auth';
import { getEngineeringMatrix } from '@/server/web/engineering-data';
import { canManageEngineering, engineeringRouteRows } from '@/components/web/engineering-model';
import { Empty, PageHeading, Status } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';
import s from '@/components/web/engineering.module.css';

export default async function Engenharia({ searchParams }: { searchParams: Promise<{ tipo?: string | string[]; resultado?: string }> }) {
  const params = await searchParams; const access = await requireWebUser('em.engineering.read');
  const data = await getEngineeringMatrix(typeof params.tipo === 'string' ? params.tipo : undefined); const managing = canManageEngineering(access);
  const type = data.types.find(row => row.id === data.selectedTypeId);
  return <><PageHeading eyebrow="BASE TÉCNICA" title="Engenharia" description="Configure o roteiro de células, os formulários, as fotos e as aprovações por tipo de equipamento." actions={<><a className="button secondary" href="/engenharia/titulos"><Icon name="image" size={15} />Títulos de fotos</a>{managing && <a className="button" href={`/engenharia/novo${data.selectedTypeId ? `?tipo=${data.selectedTypeId}` : ''}`}><Icon name="plus" size={15} />Adicionar célula ao roteiro</a>}</>} />
    {params.resultado === 'salvo' && <div role="status" className="notice success">Roteiro salvo. A configuração será usada nas próximas alocações.</div>}
    <section className="panel"><form className="filters" action="/engenharia"><div className={`field ${s.selectType}`}><label htmlFor="engineering-type">Tipo de equipamento</label><select id="engineering-type" name="tipo" defaultValue={data.selectedTypeId ?? ''} required><option value="">Selecione o tipo</option>{data.types.map(row => <option key={row.id} value={row.id}>{row.nome}</option>)}</select></div><button className="button secondary">Consultar roteiro</button></form></section>
    <section className="panel"><div className="panel-header"><div><h2>{type ? `Roteiro · ${type.nome}` : 'Roteiro de células'}</h2><p>A ordem segue o cadastro de células. A edição preserva os projetos já alocados.</p></div>{type && <span className="inline-count">{data.rows.length}</span>}</div>
      {data.rows.length ? engineeringRouteRows(data.rows, data.cells).map(row => { const cell = data.cells.find(item => item.id === row.celula_id); return <article key={row.id} className={s.row}><div><h3>{cell?.nome || 'Célula não disponível'}</h3><Status value={row.ativo ? 'ativo' : 'inativo'} /><div className={s.summary}><span>{row.form_count ?? 0} formulários</span><span>{row.photo_count ?? 0} fotos no modelo</span><span>{row.stage_count ?? 0} etapas</span><span>{row.visibilidade ? 'Visível ao alocar' : 'Oculta ao alocar'}</span></div></div><div className={s.actions}><a className="button small secondary" href={`/engenharia/${row.id}`}>Consultar</a>{managing && <a className="button small secondary" href={`/engenharia/${row.id}/editar`} aria-label={`Editar roteiro de ${cell?.nome || 'célula'}`}><Icon name="edit" size={14} />Editar</a>}</div></article>; }) : <Empty title={type ? 'Nenhuma célula neste roteiro' : 'Selecione um tipo de equipamento'} detail={type ? 'Adicione a primeira célula para definir as próximas alocações deste tipo.' : 'Consulte a configuração antes de criar ou alterar um vínculo.'} icon="board" />}
    </section>
  </>;
}
