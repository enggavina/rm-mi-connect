import type { EngineeringChoices, EngineeringSnapshot } from './engineering-model';
import { engineeringFutureNotice } from './engineering-model';
import { Details, Status, display } from './ui';
import s from './engineering.module.css';

export function EngineeringDetail({ entry, choices }: { entry: EngineeringSnapshot; choices: EngineeringChoices }) {
  const cellName = (id: string | null) => choices.cells.find(cell => cell.id === id)?.nome || 'Referência não disponível';
  const userNames = (ids: string[]) => ids.map(id => choices.users.find(user => user.id === id)?.nome || 'Referência não disponível').join(', ') || 'Não definido';
  return <><div className="notice">{engineeringFutureNotice}</div><section className="panel"><div className="panel-header"><h2>Configuração do roteiro</h2><Status value={entry.matrix.ativo ? 'ativo' : 'inativo'} /></div><div className="panel-content"><Details values={[
    ['Tipo de equipamento', choices.types.find(type => type.id === entry.matrix.tipo_equipamento_id)?.nome || 'Referência não disponível'], ['Célula', cellName(entry.matrix.celula_id)],
    ['Visível para operação ao alocar', entry.matrix.visibilidade ? 'Sim' : 'Não'],
  ]} /></div></section>
    <section className="panel"><div className="panel-header"><h2>Formulários <span className="inline-count">{entry.form_ids.length}</span></h2></div><div className="panel-content"><ul className={s.readList}>{entry.form_ids.map(id => { const form = choices.forms.find(row => row.id === id); return <li key={id}>{form?.titulo || 'Referência não disponível'}{!form?.ativo && <small className={s.tag}> — vínculo legado inativo ou indisponível</small>}</li>; })}</ul>{!entry.form_ids.length && <p className={s.muted}>Nenhum formulário vinculado.</p>}</div></section>
    <section className="panel"><div className="panel-header"><h2>Fotos do modelo <span className="inline-count">{entry.photos.length}</span></h2></div><div className="panel-content">{entry.photos.map((photo, index) => <article className={s.item} key={photo.id}><h3>{photo.titulo || choices.photoTitles.find(title => title.id === photo.cadastro_foto_id)?.titulo || `Item de foto ${index + 1}`}</h3><p className={s.muted}>Número / ordem: {photo.numero ?? 'Não informado'} · {photo.categoria_foto == null ? 'Obrigatória ao alocar' : display(photo.categoria_foto)}</p>{photo.descricao && <p className={s.muted}>{photo.descricao}</p>}{!photo.cadastro_foto_id && <p className={s.muted}>Título legado preservado.</p>}</article>)}{!entry.photos.length && <p className={s.muted}>Nenhuma foto definida.</p>}</div></section>
    <section className="panel"><div className="panel-header"><h2>Etapas de aprovação <span className="inline-count">{entry.stages.length}</span></h2></div><div className="panel-content">{entry.stages.map((stage, index) => <article className={s.item} key={stage.id}><h3>Etapa {index + 1} · {cellName(stage.celula_destino_id)}</h3><Details values={[
      ['Status para liberação', choices.statuses.find(status => status.option_key === stage.status_cel_proj)?.bubble_display || display(stage.status_cel_proj)],
      ['Aguardar aprovações bloqueadoras', stage.bloquear_avanco_sem_aprov ? 'Sim' : 'Não'], ['Aprovadores na origem', userNames(stage.aprovadores_ids ?? [])], ['Aprovadores de retorno', userNames(stage.aprovadores_retorno_ids ?? [])],
      ...(stage.aprovador_id ? [['Aprovador individual legado', userNames([stage.aprovador_id])] as [string, unknown]] : []),
    ]} /></article>)}{!entry.stages.length && <p className={s.muted}>Nenhuma etapa de aprovação definida.</p>}</div></section>
  </>;
}
