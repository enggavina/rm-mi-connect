'use client';
import { useState } from 'react';
import type { WebRow } from '@/server/web/data';
import { savePhotoTitle } from '@/server/web/engineering-actions';
import { Icon } from './icons';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import type { PhotoTitlePayload } from './engineering-model';
import s from './engineering.module.css';

export function EngineeringTitleEditor({ entry, cells }: { entry?: WebRow; cells: WebRow[] }) {
  const [id] = useState(() => entry?.id || crypto.randomUUID());
  const [title, setTitle] = useState(String(entry?.titulo ?? '')), [number, setNumber] = useState(String(entry?.numero ?? '')), [scope, setScope] = useState('');
  const save = useEngineeringSave<PhotoTitlePayload>(savePhotoTitle, '/engenharia/titulos?resultado=salvo');
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
    void save.send({ submissionId: crypto.randomUUID(), id, expected_updated_at: entry?.updated_at ?? null, changes });
  }
  return <><div className="notice">O título orienta a configuração das fotos obrigatórias. Alterá-lo não renomeia fotos já copiadas para projetos.</div><EngineeringSaveNotice state={save} reload={entry ? `/engenharia/titulos/${id}/editar` : '/engenharia/titulos/novo'} />
    <form onSubmit={event => { event.preventDefault(); submit(); }}><fieldset className={s.fieldSet} disabled={save.locked}><div className="form-grid">
      <div className="field span-all"><label htmlFor="photo-title-name">Título *</label><input id="photo-title-name" value={title} onChange={event => setTitle(event.target.value)} maxLength={200} required autoComplete="off" /></div>
      <div className="field"><label htmlFor="photo-title-number">Número de referência</label>{changeNumber ? <input id="photo-title-number" type="number" min={0} max={1000} step={1} value={number} onChange={event => setNumber(event.target.value)} /> : <><input id="photo-title-number" value={number} readOnly /><span className="form-note">A numeração legada será preservada.</span><button type="button" className="button small secondary" onClick={() => setChangeNumber(true)}>Alterar numeração</button></>}<span className="form-note">Opcional. A ordem de cada foto é definida no roteiro.</span></div>
      <div className="field"><label htmlFor="photo-title-scope">Disponível para *</label>{entry ? <><input id="photo-title-scope" value={String(entry.celula_nome ?? '').trim() || 'Todas as células — Global'} readOnly /><span className="form-note">O escopo é preservado na edição.{entry.scope_resolved === false && ' Vínculo legado sem correspondência única no cadastro atual.'}</span></> : <select id="photo-title-scope" required value={scope} onChange={event => setScope(event.target.value)}><option value="">Selecione o escopo</option><option value="global">Todas as células — Global</option>{cells.map(cell => <option key={cell.id} value={cell.id}>{cell.nome}</option>)}</select>}</div>
    </div></fieldset><div className="form-actions"><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={() => window.location.assign('/engenharia/titulos')}>Cancelar</button><button className="button" disabled={save.busy || save.stale || save.unauthorized}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : <><Icon name="check" size={15} />Salvar título</>}</button></div></form>
  </>;
}
