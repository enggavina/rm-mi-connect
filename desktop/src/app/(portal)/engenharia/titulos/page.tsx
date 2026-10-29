import { requireWebUser } from '@/server/web/auth';
import { listPhotoTitles } from '@/server/web/engineering-data';
import { canManageEngineering } from '@/components/web/engineering-model';
import { Empty, PageHeading, Pagination } from '@/components/web/ui';
import { Icon } from '@/components/web/icons';

export default async function TitulosFotos({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams; const filters = Object.fromEntries(['q', 'page', 'cell'].map(key => [key, typeof params[key] === 'string' ? params[key] as string : undefined]));
  const access = await requireWebUser('em.engineering.read'), data = await listPhotoTitles(filters), managing = canManageEngineering(access);
  return <><a className="back-link" href="/engenharia"><Icon name="back" size={15} />Voltar para engenharia</a><PageHeading eyebrow="ENGENHARIA" title="Títulos de fotos" description="Consulte os títulos disponíveis para configurar as fotos obrigatórias dos roteiros." actions={managing ? <a className="button" href="/engenharia/titulos/novo"><Icon name="plus" size={15} />Cadastrar título de foto</a> : undefined} />
    {params.resultado === 'salvo' && <div role="status" className="notice success">Título de foto salvo.</div>}
    {params.resultado === 'excluido' && <div role="status" className="notice success">Título de foto excluído.</div>}
    <section className="panel"><form className="filters" action="/engenharia/titulos"><div className="search-field"><Icon name="search" size={15} /><input name="q" defaultValue={filters.q} maxLength={100} aria-label="Buscar título de foto" placeholder="Buscar título ou célula…" /></div><select aria-label="Filtrar célula" name="cell" defaultValue={filters.cell ?? ''}><option value="">Todas as células</option>{data.cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select><button className="button secondary">Buscar</button></form>
      {data.rows.length ? <div className="table-scroll"><table className="data-table"><thead><tr><th>Título</th><th>Disponível para</th><th>Número de referência</th>{managing && <th>Ações</th>}</tr></thead><tbody>{data.rows.map(row => <tr key={row.id}><td className="table-title">{row.titulo}</td><td>{String(row.celula_nome ?? '').trim() || 'Todas as células — Global'}{!row.scope_resolved && <span className="table-subtitle">Vínculo legado sem correspondência única</span>}</td><td>{row.numero ?? '—'}</td>{managing && <td><a className="text-link" href={`/engenharia/titulos/${row.id}/editar`} aria-label={`Editar título ${row.titulo}`}><Icon name="edit" size={14} />Editar</a></td>}</tr>)}</tbody></table></div> : <Empty title="Nenhum título encontrado" detail="Ajuste os filtros para consultar outros títulos." icon="image" />}
      <Pagination {...data} base="/engenharia/titulos" filters={filters} />
    </section>
  </>;
}
