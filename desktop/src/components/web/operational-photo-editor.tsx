'use client';

import { useEffect, useRef, useState } from 'react';
import { manageOperationalPhotos } from '@/server/web/operational-photo-actions';
import type { ManageOperationalPhotosInput } from '@/server/web/operational-photo-policy';
import type { OperationalPhotoSnapshot } from '@/server/web/operational-photo-data';
import { canManageOperationalPhotos, operationalPhotoPage, operationalPhotoRequest, operationalTitleBlockReason, type OperationalPhotoMode } from './operational-photo-model';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { projectRouteDestination } from './project-route-model';
import { Empty, Status } from './ui';
import { Icon } from './icons';
import s from './operational-photo.module.css';

export function OperationalPhotoEditor({ snapshot, canManage, destination }: {
  snapshot: OperationalPhotoSnapshot; canManage: boolean; destination: string;
}) {
  const [mode, setMode] = useState<OperationalPhotoMode | null>(null), [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [search, setSearch] = useState(''), [tag, setTag] = useState(''), [confirmed, setConfirmed] = useState(false);
  const [retired, setRetired] = useState(false), [page, setPage] = useState(1), [saved, setSaved] = useState(false);
  const leaving = useRef(false);
  const target = projectRouteDestination(destination, snapshot.project.id);
  const save = useEngineeringSave<ManageOperationalPhotosInput>(async input => {
    const result = await manageOperationalPhotos(input);
    if (result.ok) { leaving.current = true; setSaved(true); }
    return result;
  }, target);
  const editable = canManageOperationalPhotos(snapshot, canManage);
  const locked = save.locked || saved;
  const current = mode && mode.action !== 'add' ? snapshot.photos.find(photo => photo.id === mode.photoId) : undefined;
  const currentTitle = current?.titulo || 'Foto sem título';
  const dirty = mode?.action === 'add' ? selectedIds.length > 0 : mode?.action === 'tag' && tag !== (current?.tag ?? '');
  useEffect(() => {
    if (!dirty && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]');
      if (!link || link.getAttribute('target') === '_blank') return;
      if (!window.confirm(save.uncertain ? 'O envio ainda não foi confirmado. Sair desta tela?' : 'Há alterações de fotos não salvas. Sair sem salvar?')) {
        event.preventDefault(); event.stopPropagation();
      } else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [dirty, save.busy, save.uncertain]);
  function open(next: OperationalPhotoMode) {
    if (!editable || locked || mode || next.action === 'add' && !snapshot.titles_complete) return;
    setMode(next); setSelectedIds([]); setSearch(''); setConfirmed(false); save.setError('');
    setTag(next.action === 'tag' ? snapshot.photos.find(photo => photo.id === next.photoId)?.tag ?? '' : '');
  }
  function cancel() {
    if (save.busy || save.uncertain) return;
    setMode(null); setSelectedIds([]); setConfirmed(false); save.setError('');
  }
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (!mode || !editable || locked) return;
    if ((mode.action === 'retire' || mode.action === 'restore') && !confirmed) { save.setError('Confirme a alteração deste título antes de continuar.'); return; }
    try {
      const draft = mode.action === 'add' ? { action: 'add' as const, titleIds: selectedIds }
        : mode.action === 'tag' ? { action: 'tag' as const, photoId: mode.photoId, tag }
          : { action: mode.action, photoId: mode.photoId };
      void save.send(operationalPhotoRequest(snapshot, draft, crypto.randomUUID(), () => crypto.randomUUID()));
    } catch (error) { save.setError(error instanceof Error ? error.message : 'Confira os dados desta foto.'); }
  }
  const activeCount = snapshot.photos.filter(photo => !photo.retired).length;
  const retiredCount = snapshot.photos.length - activeCount;
  const displayed = operationalPhotoPage(snapshot.photos, retired, page);
  const filteredTitles = snapshot.titles.filter(title => (title.titulo ?? '').toLocaleLowerCase('pt-BR').includes(search.toLocaleLowerCase('pt-BR')));
  const actionLabel = mode?.action === 'add' ? 'Adicionar fotos obrigatórias' : mode?.action === 'tag' ? 'Salvar tag'
    : mode?.action === 'retire' ? 'Confirmar retirada' : 'Confirmar restauração';

  if (!snapshot.complete) return <Empty title="Esta célula excede o limite de fotos desta tela" detail="Nenhuma parte das fotos será alterada isoladamente. Os registros existentes permanecem preservados." icon="image" />;
  return <>
    <div className={s.toolbar}><p className={s.summary}>{activeCount} em uso · {retiredCount} retiradas. A galeria do projeto reúne as capturas já registradas.</p>
      {canManage && <button type="button" className="button secondary" disabled={!editable || !snapshot.titles_complete || locked || !!mode} onClick={() => open({ action: 'add' })}><Icon name="plus" size={15} />Adicionar títulos</button>}
    </div>
    {canManage && !snapshot.titles_complete && <div className={s.notice}><p className="notice">A lista de títulos desta célula excede o limite de inclusão nesta tela. Não é possível adicionar títulos, mas as fotos já vinculadas permanecem disponíveis.</p></div>}
    {(snapshot.project.closed || ['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '')) && <div className={s.notice}><p className="notice">O projeto ou a célula está encerrado. As fotos permanecem disponíveis para consulta.</p></div>}
    <div className={s.notice}><EngineeringSaveNotice state={{ ...save, stale: false }} reload={target} />
      {save.stale && <div className="notice">O projeto, a célula ou suas fotos foram alterados. <a className="text-link" href={target} onClick={() => { leaving.current = true; }}>Recarregar fotos da célula</a> antes de editar novamente.</div>}
      {save.busy && <p className="notice" role="status">Salvando alteração das fotos…</p>}
      {saved && <p className="notice success" role="status">Alteração confirmada. Atualizando as fotos…</p>}
    </div>
    {mode && <form className={s.form} onSubmit={event => { event.preventDefault(); submit(); }}>
      <h3>{mode.action === 'add' ? 'Adicionar fotos obrigatórias' : mode.action === 'tag' ? 'Editar tag da foto' : mode.action === 'retire' ? 'Retirar título previsto' : 'Restaurar título previsto'}</h3>
      {mode.action !== 'add' && <p><strong>{currentTitle}</strong></p>}
      <fieldset className={s.fieldSet} disabled={locked}>
        {mode.action === 'add' ? <>
          <p>Selecione os títulos que devem ser registrados nesta célula. Os títulos já vinculados permanecem identificados na lista.</p>
          <div className="field"><label htmlFor="operational-title-search">Buscar título para adicionar</label><input id="operational-title-search" value={search} onChange={event => setSearch(event.target.value)} maxLength={200} /></div>
          {snapshot.titles.length ? <div className={s.choices}>{filteredTitles.map(title => {
            const reason = operationalTitleBlockReason(title, selectedIds, snapshot.titles);
            return <label key={title.id}><input type="checkbox" aria-label={`Selecionar título ${title.titulo || 'não informado'}`} checked={selectedIds.includes(title.id)} disabled={!!reason}
              onChange={event => setSelectedIds(ids => event.target.checked ? [...ids, title.id] : ids.filter(id => id !== title.id))} /><span>{title.titulo || 'Título não informado'}{reason && <small>{reason}</small>}</span></label>;
          })}</div> : <p>Nenhum título disponível para esta célula.</p>}
          {snapshot.titles.length > 0 && filteredTitles.length === 0 && <p>Nenhum título encontrado nesta pesquisa.</p>}
          <p>{selectedIds.length} títulos selecionados. Até 100 títulos por envio.</p>
        </> : mode.action === 'tag' ? <>
          <p>A tag identifica esta foto nos relatórios. Deixe o campo vazio para removê-la.</p>
          <div className="field"><label htmlFor="operational-photo-tag">Tag da foto</label><textarea className={s.tagInput} id="operational-photo-tag" value={tag} onChange={event => setTag(event.target.value)} maxLength={2000} /></div>
          {tag.length > 2000 && <p className="notice">A tag legada excede 2.000 caracteres. Ela será preservada enquanto você não salvar uma alteração.</p>}
        </> : <>
          <p>{mode.action === 'retire' ? 'Este título deixará de ser solicitado na célula. Ele permanecerá nas fotos retiradas e poderá ser restaurado.' : 'Este título voltará a ser solicitado na célula. Capturas pendentes poderão ser reenviadas após a restauração.'}</p>
          <label className="check-label"><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />{mode.action === 'retire' ? 'Confirmo a retirada deste título.' : 'Confirmo a restauração deste título.'}</label>
        </>}
      </fieldset>
      <div className={s.actions}><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={cancel}>Cancelar edição</button>
        <button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved
          || (!save.uncertain && ((mode.action === 'add' && !selectedIds.length) || (mode.action === 'tag' && (tag === (current?.tag ?? '') || tag.length > 2000))
            || ((mode.action === 'retire' || mode.action === 'restore') && !confirmed)))}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : actionLabel}</button>
      </div>
    </form>}
    <div className={s.tabs} aria-label="Situação das fotos"><button type="button" aria-pressed={!retired} disabled={locked || !!mode} onClick={() => { setRetired(false); setPage(1); }}>Em uso ({activeCount})</button><button type="button" aria-pressed={retired} disabled={locked || !!mode} onClick={() => { setRetired(true); setPage(1); }}>Retiradas ({retiredCount})</button></div>
    {retired && <div className={s.notice}><p className="form-note">As previsões retiradas permanecem no histórico. Restaure um título para voltar a solicitá-lo, sem criar outra foto.</p></div>}
    {displayed.rows.length ? <div className={s.list}>{displayed.rows.map(photo => <article className={s.item} key={photo.id} data-operational-photo={photo.id}>
      <div><h3>{photo.titulo || 'Foto sem título'}</h3><div className={s.meta}><Status value={photo.categoria_foto} /><Status value={photo.retired ? 'inativo' : photo.captured ? 'finalizado' : 'pendente'} label={photo.retired ? 'Retirada' : photo.captured ? 'Capturada' : 'Aguardando captura'} />{photo.selected_for_report && <Status value="ativo" label="Selecionada para relatório" />}</div>
        <p className={s.tag}>{photo.tag === null || photo.tag === '' ? 'Sem tag' : `Tag: ${photo.tag}`}</p>{canManage && photo.action_reason && <p className={s.reason}>{photo.action_reason}</p>}
      </div>
      {editable && <div className={s.controls}>
        {photo.can_edit_tag && <button type="button" className="button small secondary" aria-label={`Editar tag de ${photo.titulo || 'foto sem título'}`} disabled={locked || !!mode} onClick={() => open({ action: 'tag', photoId: photo.id })}><Icon name="edit" size={14} />Editar tag</button>}
        {photo.can_retire && <button type="button" className="button small secondary" aria-label={`Retirar ${photo.titulo || 'foto sem título'}`} disabled={locked || !!mode} onClick={() => open({ action: 'retire', photoId: photo.id })}>Retirar</button>}
        {photo.can_restore && <button type="button" className="button small secondary" aria-label={`Restaurar ${photo.titulo || 'foto sem título'}`} disabled={locked || !!mode} onClick={() => open({ action: 'restore', photoId: photo.id })}>Restaurar</button>}
      </div>}
    </article>)}</div> : <Empty title={retired ? 'Nenhuma foto retirada' : 'Nenhuma foto vinculada a esta célula'} detail={retired ? 'As previsões retiradas do roteiro serão reunidas aqui.' : 'Os títulos definidos na Engenharia são copiados nas novas alocações. Você também pode adicionar títulos nesta célula quando tiver permissão.'} icon="image" />}
    <div className={s.pagination}><span>{displayed.total ? `${(displayed.page - 1) * 25 + 1}–${Math.min(displayed.page * 25, displayed.total)} de ${displayed.total} fotos` : 'Nenhum registro'}</span><div><button type="button" className="button small secondary" disabled={locked || !!mode || displayed.page <= 1} onClick={() => setPage(displayed.page - 1)}>Anterior</button><span>{displayed.page} / {displayed.pages}</span><button type="button" className="button small secondary" disabled={locked || !!mode || displayed.page >= displayed.pages} onClick={() => setPage(displayed.page + 1)}>Próxima</button></div></div>
  </>;
}
