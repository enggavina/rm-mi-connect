'use client';
import { useState } from 'react';
import type { WebRow } from '@/server/web/data';
import { deletePhotoTitle, savePhotoTitle } from '@/server/web/engineering-actions';
import { Icon } from './icons';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import type { PhotoTitleAttempt, PhotoTitlePayload } from './engineering-model';
import { confirmsCatalogDeletion } from './catalog-model';
import s from './engineering.module.css';

export function EngineeringTitleEditor({ entry, cells }: { entry?: WebRow; cells: WebRow[] }) {
  const [id] = useState(() => entry?.id || crypto.randomUUID());
  const [title, setTitle] = useState(String(entry?.titulo ?? '')), [number, setNumber] = useState(String(entry?.numero ?? '')), [scope, setScope] = useState('');
  const [deleting, setDeleting] = useState(false), [confirmation, setConfirmation] = useState('');
  // One frozen attempt owns both commands. An uncertain delete cannot start save.
  const save = useEngineeringSave<PhotoTitleAttempt>(attempt => attempt.action === 'save' ? savePhotoTitle(attempt.payload) : deletePhotoTitle(attempt.payload),
    attempt => `/engenharia/titulos?resultado=${attempt.action === 'save' ? 'salvo' : 'excluido'}`);
  const legacyNumber = !!entry && entry.numero != null && (!Number.isInteger(entry.numero) || entry.numero < 0 || entry.numero > 1000);
  const [changeNumber, setChangeNumber] = useState(!legacyNumber);
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (!title.trim() || title.trim().length > 200) { save.setError('Informe um título com até 200 caracteres.'); return; }
    if ((!entry || number !== String(entry.numero ?? '')) && number !== '' && (!/^\d+$/.test(number) || Number(number) > 1000)) { save.setError('Informe um número inteiro entre 0 e 1.000 ou deixe vazio.'); return; }
    if (!entry && scope !== 'global' && !cells.some(cell => cell.id === scope)) { save.setError('Escolha uma célula ou o escopo global.'); return; }
    const changes: PhotoTitlePayload['changes'] = { titulo: title.trim() };
    if (!entry || number !== String(entry.numero ?? '')) changes.numero = number === '' ? null : Number(number);
    if (!entry) changes.celula_id = scope === 'global' ? null : scope;
    void save.send({ action: 'save', payload: { submissionId: crypto.randomUUID(), id, expected_updated_at: entry?.updated_at ?? null, changes } });
  }
  function remove() {
    if (save.uncertain) { save.retry(); return; }
    if (!entry || typeof entry.updated_at !== 'string' || !confirmsCatalogDeletion(entry.titulo, confirmation)) return;
    void save.send({ action: 'delete', payload: { submissionId: crypto.randomUUID(), id, expected_updated_at: entry.updated_at } });
  }
  return <><div className="notice">O título orienta a configuração das fotos obrigatórias. Alterá-lo não renomeia fotos já copiadas para projetos.</div><EngineeringSaveNotice state={save} reload={entry ? `/engenharia/titulos/${id}/editar` : '/engenharia/titulos/novo'} />
    <form onSubmit={event => { event.preventDefault(); if (!deleting) submit(); }}><fieldset className={s.fieldSet} disabled={save.locked || deleting}><div className="form-grid">
      <div className="field span-all"><label htmlFor="photo-title-name">Título *</label><input id="photo-title-name" value={title} onChange={event => setTitle(event.target.value)} maxLength={200} required autoComplete="off" /></div>
      <div className="field"><label htmlFor="photo-title-number">Número de referência</label>{changeNumber ? <input id="photo-title-number" type="number" min={0} max={1000} step={1} value={number} onChange={event => setNumber(event.target.value)} /> : <><input id="photo-title-number" value={number} readOnly /><span className="form-note">A numeração legada será preservada.</span><button type="button" className="button small secondary" onClick={() => setChangeNumber(true)}>Alterar numeração</button></>}<span className="form-note">Opcional. A ordem de cada foto é definida no roteiro.</span></div>
      <div className="field"><label htmlFor="photo-title-scope">Disponível para *</label>{entry ? <><input id="photo-title-scope" value={String(entry.celula_nome ?? '').trim() || 'Todas as células — Global'} readOnly /><span className="form-note">O escopo é preservado na edição.{entry.scope_resolved === false && ' Vínculo legado sem correspondência única no cadastro atual.'}</span></> : <select id="photo-title-scope" required value={scope} onChange={event => setScope(event.target.value)}><option value="">Selecione o escopo</option><option value="global">Todas as células — Global</option>{cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select>}</div>
    </div></fieldset><div className="form-actions"><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={() => window.location.assign('/engenharia/titulos')}>Cancelar</button>{!deleting && <button className="button" disabled={save.busy || save.stale || save.unauthorized}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : <><Icon name="check" size={15} />Salvar título</>}</button>}</div></form>
    {entry && <section aria-labelledby="delete-photo-title" style={{ marginTop: 36, paddingTop: 24, borderTop: '1px solid var(--line)' }}>
      <h2 id="delete-photo-title" style={{ fontSize: 14 }}>Excluir título de foto</h2>
      <p className="form-note">Títulos vinculados a fotos ou modelos não podem ser excluídos. Os registros existentes são preservados.</p>
      {!deleting ? <button type="button" className="button secondary" disabled={save.locked} onClick={() => { setDeleting(true); setConfirmation(''); save.setError(''); }}>Excluir título</button> : <form onSubmit={event => { event.preventDefault(); remove(); }}>
        <p className="notice">Você está excluindo <strong>{entry.titulo}</strong>.</p>
        <div className="field"><label htmlFor="confirm-title-delete">Digite “{entry.titulo}” para confirmar</label><input id="confirm-title-delete" value={confirmation} onChange={event => setConfirmation(event.target.value)} required autoComplete="off" disabled={save.locked} /></div>
        <div className="form-actions"><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={() => { setDeleting(false); setConfirmation(''); save.setError(''); }}>Manter título</button>
          <button className="button" disabled={save.busy || save.stale || save.unauthorized || (!save.uncertain && !confirmsCatalogDeletion(entry.titulo, confirmation))}>{save.busy ? 'Excluindo…' : save.uncertain ? 'Tentar confirmar envio' : 'Confirmar exclusão'}</button></div>
      </form>}
    </section>}
  </>;
}
