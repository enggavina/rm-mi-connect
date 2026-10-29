'use client';
import { useState } from 'react';
import { saveEngineering } from '@/server/web/engineering-actions';
import type { WebRow } from '@/server/web/data';
import { Icon } from './icons';
import { display } from './ui';
import { approversForCell, engineeringChanges, engineeringFutureNotice, legacyPhoto, legacyStage, nextPhotoNumber, photoDraft, stageDraft, titlesForCell, validateEngineering, type EngineeringChoices, type EngineeringPayload, type EngineeringSnapshot } from './engineering-model';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import s from './engineering.module.css';

function Checks({ label, options, all, selected, onChange, field }: { label: string; options: WebRow[]; all: WebRow[]; selected: string[]; onChange: (ids: string[]) => void; field: 'titulo' | 'nome' }) {
  const [query, setQuery] = useState('');
  const available = new Set(options.map(row => row.id));
  const rows = [...options, ...selected.filter(id => !available.has(id)).map(id => all.find(row => row.id === id) ?? { id, [field]: 'Referência não disponível', missing: true })];
  const visible = rows.filter(row => String(row[field] ?? '').toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  return <div className="field"><span className="field-label">{label}</span><input className={s.search} type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="Filtrar opções…" aria-label={`Filtrar ${label.toLocaleLowerCase()}`} />
    <div className={s.checklist}>{visible.map(row => <label className="check-label" key={row.id}><input type="checkbox" checked={selected.includes(row.id)} onChange={event => onChange(event.target.checked ? [...selected, row.id] : selected.filter(id => id !== row.id))} /><span>{row[field] || 'Referência não disponível'}{!available.has(row.id) && <small>Vínculo legado indisponível para novas inclusões. Desmarque somente se desejar removê-lo.</small>}</span></label>)}{!visible.length && <span className={s.muted}>Nenhuma opção disponível para esta seleção.</span>}</div>
  </div>;
}

export function EngineeringEditor({ snapshot, choices, initialTypeId = '' }: { snapshot?: EngineeringSnapshot; choices: EngineeringChoices; initialTypeId?: string }) {
  const [id] = useState(() => snapshot?.matrix.id || crypto.randomUUID());
  const [cellId, setCellId] = useState(snapshot?.matrix.celula_id || ''), [typeId, setTypeId] = useState(snapshot?.matrix.tipo_equipamento_id || initialTypeId);
  const [active, setActive] = useState(snapshot ? snapshot.matrix.ativo === true : true), [visible, setVisible] = useState(snapshot ? snapshot.matrix.visibilidade === true : true);
  const [quantity, setQuantity] = useState(String(snapshot?.matrix.numero_fotos ?? (snapshot ? '' : 0)));
  const [forms, setForms] = useState<string[]>(snapshot?.form_ids ? [...snapshot.form_ids] : []);
  const [photos, setPhotos] = useState(snapshot?.photos.map(photoDraft) ?? []), [stages, setStages] = useState(snapshot?.stages.map(stageDraft) ?? []);
  const [reconfigurePhotos, setReconfigurePhotos] = useState<string[]>([]), [reconfigureStages, setReconfigureStages] = useState<string[]>([]);
  const back = `/engenharia${typeId ? `?tipo=${typeId}` : ''}`;
  const save = useEngineeringSave<EngineeringPayload>(saveEngineering, `${back}${typeId ? '&' : '?'}resultado=salvo`);
  const catalog = titlesForCell(choices, cellId);
  const originApprovers = approversForCell(choices, cellId);
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (!choices.types.some(type => type.id === typeId)) { save.setError('Escolha o tipo de equipamento.'); return; }
    const changes = engineeringChanges(snapshot, { ativo: active, visibilidade: visible, numero_fotos: quantity, form_ids: forms, photos, stages });
    const error = validateEngineering(changes, choices, cellId, snapshot);
    if (error) { save.setError(error); return; }
    void save.send({ submissionId: crypto.randomUUID(), id, celula_id: cellId, tipo_equipamento_id: typeId, expected_updated_at: snapshot?.matrix.updated_at ?? null, changes });
  }
  return <><div className="notice">{engineeringFutureNotice}</div><EngineeringSaveNotice state={save} reload={snapshot ? `/engenharia/${id}/editar` : `/engenharia/novo${typeId ? `?tipo=${typeId}` : ''}`} />
    <form onSubmit={event => { event.preventDefault(); submit(); }}><fieldset className={s.fieldSet} disabled={save.locked}>
      <section className={s.section} aria-labelledby="matrix-base"><h2 id="matrix-base">Célula no roteiro</h2><p>O roteiro segue a ordem de exibição do cadastro de células.</p><div className="form-grid">
        <div className="field"><label htmlFor="matrix-type">Tipo de equipamento *</label><select id="matrix-type" value={typeId} onChange={event => setTypeId(event.target.value)} disabled={!!snapshot} required><option value="">Selecione o tipo</option>{choices.types.map(type => <option value={type.id} key={type.id}>{type.nome}</option>)}</select></div>
        <div className="field"><label htmlFor="matrix-cell">Célula *</label><select id="matrix-cell" value={cellId} onChange={event => setCellId(event.target.value)} disabled={!!snapshot} required><option value="">Selecione a célula</option>{choices.cells.map(cell => <option value={cell.id} key={cell.id}>{cell.nome}</option>)}</select></div>
        <label className="check-label span-all"><input type="checkbox" checked={active} onChange={event => setActive(event.target.checked)} />Modelo ativo para novas alocações</label>
        <label className="check-label span-all"><input type="checkbox" checked={visible} onChange={event => setVisible(event.target.checked)} />Visível para a operação ao alocar</label>
        <div className="field"><label htmlFor="matrix-quantity">Quantidade prevista de fotos</label><input id="matrix-quantity" type="number" min={0} max={1000} step={1} value={quantity} onChange={event => setQuantity(event.target.value)} /><span className="form-note">Número de referência do roteiro. Este número não cria fotos; adicione os títulos abaixo.</span></div>
      </div></section>
      <section className={s.section} aria-labelledby="matrix-forms"><h2 id="matrix-forms">Formulários <span className={s.tag}>{forms.length} vinculados</span></h2><p>Selecione os modelos existentes que serão copiados para a célula na nova alocação.</p><Checks label="Formulários do roteiro" options={choices.forms.filter(form => form.ativo && !form.missing)} all={choices.forms} selected={forms} onChange={setForms} field="titulo" /></section>
      <section className={s.section} aria-labelledby="matrix-photos"><h2 id="matrix-photos">Fotos do modelo <span className={s.tag}>{photos.length} itens</span></h2><p>Cada item cria um espaço para a foto na próxima alocação. Fotos novas são obrigatórias; os itens legados mantêm sua categoria enquanto não forem alterados.</p>
        {photos.map((photo, index) => { const original = snapshot?.photos.find(row => row.id === photo.id); const historical = !!original && (legacyPhoto(photoDraft(original), choices, cellId) || original.categoria_foto === 'complementar'); const locked = historical && !reconfigurePhotos.includes(photo.id); const selected = catalog.find(title => title.id === photo.cadastro_foto_id);
          const change = (patch: Partial<typeof photo>) => setPhotos(current => current.map(row => row.id === photo.id ? { ...row, ...patch } : row));
          return <article className={s.item} key={photo.id}><div className={s.itemHead}><h3>Foto {index + 1}{original?.titulo && <span className={s.summary}>{original.titulo}</span>}</h3><button type="button" className="button small secondary" onClick={() => setPhotos(current => current.filter(row => row.id !== photo.id))}>Remover do modelo</button></div>
            <p className={s.muted}>{original?.categoria_foto === 'complementar' ? 'Complementar — legado preservado' : 'Obrigatória nas novas alocações'}{!!original?.identificador_foto_key && ' · Identificação legada preservada'}</p>
            {locked ? <div className={s.legacy}>Este item possui uma configuração legada. Será preservado como está, inclusive ao salvar outras seções. Para alterá-lo, escolha um título e número válidos; o item alterado será obrigatório nas próximas alocações.<div className={s.toggle}><button type="button" className="button small secondary" onClick={() => setReconfigurePhotos(current => [...current, photo.id])}>Reconfigurar foto</button></div></div> : <div className="form-grid">
              <div className="field span-all"><label htmlFor={`photo-title-${photo.id}`}>Título da foto *</label><select id={`photo-title-${photo.id}`} value={photo.cadastro_foto_id ?? ''} onChange={event => change({ cadastro_foto_id: event.target.value || null })} required><option value="">Selecione o título</option>{!selected && photo.cadastro_foto_id && <option value={photo.cadastro_foto_id} disabled>Título legado indisponível</option>}{catalog.map(title => <option value={title.id} key={title.id}>{title.titulo}{!String(title.celula_nome ?? '').trim() ? ' — Global' : ''}</option>)}</select></div>
              <div className="field"><label htmlFor={`photo-order-${photo.id}`}>Número / ordem *</label><input id={`photo-order-${photo.id}`} type="number" min={1} max={1000} step={1} required value={photo.numero ?? ''} onChange={event => change({ numero: event.target.value === '' ? null : Number(event.target.value) })} /></div>
              <div className="field span-all"><label htmlFor={`photo-help-${photo.id}`}>Orientação para a foto</label><textarea id={`photo-help-${photo.id}`} maxLength={4000} value={photo.descricao ?? ''} onChange={event => change({ descricao: event.target.value || null })} /></div>
            </div>}
            {locked && <dl className="details-grid"><div><dt>Título</dt><dd>{original?.titulo || 'Não informado'}</dd></div><div><dt>Número / ordem</dt><dd>{photo.numero ?? 'Não informado'}</dd></div>{photo.descricao && <div><dt>Orientação</dt><dd>{photo.descricao}</dd></div>}</dl>}
          </article>;
        })}
        {!photos.length && <p>Nenhuma foto definida neste modelo.</p>}
        <div className={s.actions}><button type="button" className="button secondary" disabled={!cellId || photos.length >= 1000} onClick={() => setPhotos(current => [...current, { id: crypto.randomUUID(), cadastro_foto_id: null, numero: nextPhotoNumber(current), descricao: null }])}><Icon name="plus" size={15} />Adicionar foto obrigatória</button><a href="/engenharia/titulos" target="_blank" rel="noopener noreferrer" className="text-link">Consultar títulos de fotos<Icon name="external" size={14} /></a></div>
        {!catalog.length && cellId && <p className={s.muted}>Nenhum título disponível para esta célula. Cadastre um título e recarregue o roteiro antes de incluir a foto.</p>}
        {!!snapshot && snapshot.photos.some(row => !photos.some(photo => photo.id === row.id)) && <p className={s.removed}>Itens removidos deixarão de ser copiados nas próximas alocações. As fotos dos projetos existentes serão preservadas.</p>}
      </section>
      <section className={s.section} aria-labelledby="matrix-stages"><h2 id="matrix-stages">Aprovações e destino <span className={s.tag}>{stages.length} etapas</span></h2><p>Defina quando liberar a próxima célula e quem aprova na origem e no retorno. O retorno é criado pela operação ao liberar a etapa.</p>
        {stages.map((stage, index) => { const original = snapshot?.stages.find(row => row.id === stage.id); const historical = !!original && (legacyStage(stageDraft(original), choices, cellId) || !!original.aprovador_id); const locked = historical && !reconfigureStages.includes(stage.id); const destination = choices.cells.find(cell => cell.id === stage.celula_destino_id);
          const change = (patch: Partial<typeof stage>) => setStages(current => current.map(row => row.id === stage.id ? { ...row, ...patch } : row));
          const names = (ids: string[]) => ids.map(id => choices.users.find(user => user.id === id)?.nome || 'Referência não disponível').join(', ') || 'Não definido';
          return <article className={s.item} key={stage.id}><div className={s.itemHead}><h3>Etapa {index + 1}{destination && <span className={s.summary}>Destino: {destination.nome}</span>}</h3><button type="button" className="button small secondary" onClick={() => setStages(current => current.filter(row => row.id !== stage.id))}>Remover do modelo</button></div>
            {locked ? <><div className={s.legacy}>Esta etapa contém vínculos legados e será preservada sem alterações.{original?.aprovador_id && <> Há também um aprovador individual: <strong>{names([original.aprovador_id])}</strong>.</>} Ao reconfigurar, as listas escolhidas abaixo passam a definir os aprovadores.<div className={s.toggle}><button type="button" className="button small secondary" onClick={() => setReconfigureStages(current => [...current, stage.id])}>Reconfigurar etapa</button></div></div><dl className="details-grid"><div><dt>Destino</dt><dd>{destination?.nome || 'Referência não disponível'}</dd></div><div><dt>Status para liberação</dt><dd>{choices.statuses.find(status => status.option_key === stage.status_cel_proj)?.bubble_display || display(stage.status_cel_proj)}</dd></div><div><dt>Aprovadores na origem</dt><dd>{names(stage.aprovadores_ids)}</dd></div><div><dt>Aprovadores de retorno</dt><dd>{names(stage.aprovadores_retorno_ids)}</dd></div><div><dt>Aguardar todas as aprovações</dt><dd>{stage.bloquear_avanco_sem_aprov ? 'Sim' : 'Não'}</dd></div></dl></> : <div className="form-grid">
              <div className="field"><label htmlFor={`stage-target-${stage.id}`}>Célula de destino *</label><select id={`stage-target-${stage.id}`} value={stage.celula_destino_id ?? ''} onChange={event => change({ celula_destino_id: event.target.value || null })} required><option value="">Selecione o destino</option>{stage.celula_destino_id && (!destination || destination.id === cellId) && <option value={stage.celula_destino_id} disabled>Destino legado indisponível</option>}{choices.cells.filter(cell => cell.id !== cellId).map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select></div>
              <div className="field"><label htmlFor={`stage-status-${stage.id}`}>Status para liberação *</label><select id={`stage-status-${stage.id}`} value={stage.status_cel_proj ?? ''} onChange={event => change({ status_cel_proj: event.target.value || null })} required><option value="">Selecione o status</option>{stage.status_cel_proj === 'retornado' && <option value="retornado" disabled>Retornado — legado</option>}{choices.statuses.filter(status => status.option_key !== 'retornado').map(status => <option value={status.option_key} key={status.option_key}>{status.bubble_display}</option>)}</select></div>
              <label className="check-label span-all"><input type="checkbox" checked={stage.bloquear_avanco_sem_aprov} onChange={event => change({ bloquear_avanco_sem_aprov: event.target.checked })} />Aguardar todas as aprovações bloqueadoras antes de liberar o destino</label>
              <Checks label={`Aprovadores na origem — etapa ${index + 1}`} options={originApprovers} all={choices.users} selected={stage.aprovadores_ids} onChange={ids => change({ aprovadores_ids: ids })} field="nome" />
              <Checks label={`Aprovadores de retorno no destino — etapa ${index + 1}`} options={approversForCell(choices, stage.celula_destino_id)} all={choices.users} selected={stage.aprovadores_retorno_ids} onChange={ids => change({ aprovadores_retorno_ids: ids })} field="nome" />
            </div>}
          </article>;
        })}
        {!stages.length && <p>Nenhuma etapa de aprovação definida neste modelo.</p>}<button type="button" className="button secondary" disabled={!cellId || stages.length >= 100} onClick={() => setStages(current => [...current, { id: crypto.randomUUID(), celula_destino_id: null, status_cel_proj: null, bloquear_avanco_sem_aprov: false, aprovadores_ids: [], aprovadores_retorno_ids: [] }])}><Icon name="plus" size={15} />Adicionar etapa de aprovação</button>
        {!!snapshot && snapshot.stages.some(row => !stages.some(stage => stage.id === row.id)) && <p className={s.removed}>Etapas removidas deixarão de ser copiadas nas próximas alocações. As decisões dos projetos existentes serão preservadas.</p>}
      </section>
    </fieldset><div className="form-actions"><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={() => window.location.assign(back)}>Cancelar</button><button className="button" disabled={save.busy || save.stale || save.unauthorized}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : <><Icon name="check" size={15} />Salvar roteiro</>}</button></div></form>
  </>;
}
