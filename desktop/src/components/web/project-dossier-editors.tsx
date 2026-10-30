'use client';

import { useEffect, useRef, useState } from 'react';
import { addProjectComment } from '@/server/web/project-dossier-actions';
import type { WebActionResult } from '@/server/web/mutation';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { Icon } from './icons';
import { DOSSIER_FILE_ACCEPT, dossierAttachmentRequest, dossierCommentRequest, dossierFileError,
  type DossierAttachmentRequest, type DossierCommentAllocation, type DossierCommentRequest } from './project-dossier-model';
import s from './project-dossier.module.css';

function useDossierExitGuard(dirty: boolean, pending: boolean, stale: boolean, leaving: { current: boolean }) {
  useEffect(() => {
    if (!dirty && !pending) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && stale && !pending) {
        if (event.button === 0 && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) leaving.current = true;
        return;
      }
      if (!window.confirm(pending ? 'Este envio ainda não foi confirmado. Sair desta tela?' : 'Há dados não enviados neste formulário. Sair sem enviar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [dirty, pending, stale, leaving]);
}

export function ProjectCommentEditor({ projectId, projectVersion, allocations }: {
  projectId: string; projectVersion: string; allocations: DossierCommentAllocation[];
}) {
  const [open, setOpen] = useState(false), [text, setText] = useState(''), [allocationId, setAllocationId] = useState(''), [saved, setSaved] = useState(false);
  const leaving = useRef(false), heading = useRef<HTMLHeadingElement>(null);
  const save = useEngineeringSave<DossierCommentRequest>(async input => { const result = await addProjectComment(input); if (result.ok) { leaving.current = true; setSaved(true); } return result; }, `/projetos/${projectId}?tab=historico`);
  const choices = allocations.filter(allocation => allocation.projeto_id === projectId && !allocation.retirada);
  const locked = save.locked || saved;
  useDossierExitGuard(open && !!(text || allocationId), save.busy || save.uncertain, save.stale, leaving);
  useEffect(() => { if (open) heading.current?.focus(); }, [open]);
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (locked) return;
    try { void save.send(dossierCommentRequest(projectId, projectVersion, choices.find(allocation => allocation.id === allocationId), text, crypto.randomUUID())); }
    catch (error) { save.setError(error instanceof Error ? error.message : 'Confira os dados do comentário.'); }
  }
  if (!choices.length) return <div className={s.readonly}><p className="form-note">Aloque uma célula ativa para registrar comentários neste projeto. O histórico permanece disponível.</p></div>;
  if (!open) return <div className={s.editor} data-project-comment-editor><button type="button" className="button secondary" onClick={() => setOpen(true)}><Icon name="plus" size={14} />Adicionar comentário</button></div>;
  return <div className={s.editor} data-project-comment-editor><form className={s.form} onSubmit={event => { event.preventDefault(); submit(); }}>
    <h3 tabIndex={-1} ref={heading}>Novo comentário do projeto</h3><p>Escolha a célula destinatária. O comentário será identificado com seu nome e a data de registro.</p>
    <EngineeringSaveNotice state={save} reload={`/projetos/${projectId}?tab=historico`} />
    {save.busy && <p role="status" className="notice">Registrando comentário…</p>}{saved && <p role="status" className="notice success">Comentário registrado. Atualizando o histórico…</p>}
    <fieldset className={s.fields} disabled={locked}><div className="form-grid">
      <div className="field span-all"><label htmlFor="dossier-comment-cell">Célula destinatária *</label><select id="dossier-comment-cell" value={allocationId} onChange={event => setAllocationId(event.target.value)} required><option value="">Selecione a célula</option>{choices.map(allocation => <option key={allocation.id} value={allocation.id}>{allocation.name}{allocation.visibilidade === false ? ' · Oculta no mobile' : ''}</option>)}</select></div>
      <div className="field span-all"><label htmlFor="dossier-comment-text">Comentário *</label><textarea id="dossier-comment-text" rows={5} value={text} onChange={event => setText(event.target.value)} maxLength={10_000} required /><p className={s.counter}>{text.length.toLocaleString('pt-BR')} / 10.000 caracteres</p></div>
    </div></fieldset>
    <div className={s.actions}><button type="button" className="button secondary" disabled={locked} onClick={() => { setText(''); setAllocationId(''); save.setError(''); setOpen(false); }}>Cancelar comentário</button><button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!allocationId || !text.trim())}>{save.busy ? 'Registrando…' : save.uncertain ? 'Tentar confirmar envio' : 'Registrar comentário'}</button></div>
  </form></div>;
}

async function sendAttachment(projectId: string, input: DossierAttachmentRequest, file: File): Promise<WebActionResult> {
  const body = new FormData(); body.set('input', JSON.stringify(input)); body.set('file', file, file.name);
  const response = await fetch(`/api/web/projects/${projectId}/attachments`, { method: 'POST', body, credentials: 'same-origin' });
  let result: unknown; try { result = await response.json(); } catch { /* An unconfirmed response must keep the same file and protocol. */ }
  if (result && typeof result === 'object' && 'ok' in result) {
    const value = result as WebActionResult;
    if (value.ok && response.ok && value.data?.projeto_id === input.projeto_id && typeof value.data.id === 'string'
      && value.data.record?.attachment_id === value.data.id && value.data.record.visivel_cliente === false) return value;
    if (!value.ok && typeof value.error === 'string' && typeof value.code === 'string') return value;
  }
  return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar o registro do anexo. Tente novamente com o mesmo arquivo nesta tela.' };
}

export function ProjectAttachmentEditor({ projectId, projectVersion }: { projectId: string; projectVersion: string }) {
  const [open, setOpen] = useState(false), [nome, setName] = useState(''), [description, setDescription] = useState(''), [status, setStatus] = useState(''), [expiry, setExpiry] = useState('');
  const [file, setFile] = useState<File | null>(null), [hashing, setHashing] = useState(false), [saved, setSaved] = useState(false);
  const retainedFile = useRef<File | null>(null), computing = useRef(false), leaving = useRef(false), heading = useRef<HTMLHeadingElement>(null);
  const save = useEngineeringSave<DossierAttachmentRequest>(async input => {
    const selected = retainedFile.current;
    if (!selected || selected.name !== input.filename || selected.type !== input.mime_type || selected.size !== input.byte_size) return { ok: false, code: 'UNAVAILABLE', error: 'Mantenha o arquivo selecionado para confirmar o mesmo envio.' };
    const result = await sendAttachment(projectId, input, selected); if (result.ok) { leaving.current = true; setSaved(true); } return result;
  }, `/projetos/${projectId}?tab=documentos`);
  const locked = hashing || save.locked || saved;
  useDossierExitGuard(open && !!(nome || description || file || status || expiry), hashing || save.busy || save.uncertain, save.stale, leaving);
  useEffect(() => { if (open) heading.current?.focus(); }, [open]);
  async function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (locked || computing.current) return;
    const selected = retainedFile.current;
    if (!selected) { save.setError('Selecione um arquivo PDF, JPEG ou PNG.'); return; }
    computing.current = true; setHashing(true); save.setError('');
    try {
      let digest: ArrayBuffer;
      try { digest = await crypto.subtle.digest('SHA-256', await selected.arrayBuffer()); }
      catch { throw new Error('Não foi possível conferir o arquivo. Selecione-o novamente e tente enviar.'); }
      const sha256 = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
      await save.send(dossierAttachmentRequest(projectId, projectVersion, selected, { nome, descricao: description, status, expiry }, sha256, crypto.randomUUID()));
    } catch (error) { save.setError(error instanceof Error ? error.message : 'Não foi possível conferir o arquivo. Tente novamente.'); }
    finally { computing.current = false; setHashing(false); }
  }
  if (!open) return <div className={s.editor} data-project-attachment-editor><button type="button" className="button secondary" onClick={() => setOpen(true)}><Icon name="plus" size={14} />Adicionar anexo privado</button></div>;
  return <div className={s.editor} data-project-attachment-editor><form className={s.form} onSubmit={event => { event.preventDefault(); void submit(); }}>
    <h3 tabIndex={-1} ref={heading}>Novo anexo privado</h3><p>O arquivo ficará disponível aos usuários internos com acesso aos documentos deste projeto.</p>
    <EngineeringSaveNotice state={save} reload={`/projetos/${projectId}?tab=documentos`} />
    {save.uncertain && <p className="notice">O arquivo selecionado e os dados deste envio continuam nesta tela. Confirme o mesmo envio antes de selecionar outro arquivo.</p>}
    {(hashing || save.busy) && <p role="status" className="notice">{hashing && !save.busy ? 'Conferindo arquivo…' : 'Enviando e registrando o anexo…'}</p>}
    {saved && <p role="status" className="notice success">Anexo registrado. Atualizando os documentos…</p>}
    <fieldset className={s.fields} disabled={locked}><div className="form-grid">
      <div className="field span-all"><label htmlFor="dossier-attachment-file">Arquivo *</label><input id="dossier-attachment-file" type="file" accept={DOSSIER_FILE_ACCEPT} required onChange={event => {
        const selected = event.target.files?.[0] ?? null, error = selected ? dossierFileError(selected) : null;
        save.setError(error ?? '');
        if (error) { retainedFile.current = null; setFile(null); event.target.value = ''; return; }
        retainedFile.current = selected; setFile(selected); if (selected && !nome.trim()) setName(selected.name.slice(0, 200));
      }} /><p>PDF, JPEG ou PNG · até 20 MiB por arquivo.</p>{file && <div className={s.fileInfo}><strong>{file.name}</strong><p>{file.size < 1024 * 1024 ? `${Math.max(1, Math.ceil(file.size / 1024)).toLocaleString('pt-BR')} KiB` : `${(file.size / 1024 / 1024).toLocaleString('pt-BR', { maximumFractionDigits: 2 })} MiB`}</p></div>}</div>
      <div className="field span-all"><label htmlFor="dossier-attachment-name">Título do anexo *</label><input id="dossier-attachment-name" value={nome} onChange={event => setName(event.target.value)} maxLength={200} required /></div>
      <div className="field"><label htmlFor="dossier-attachment-status">Status do documento *</label><select id="dossier-attachment-status" value={status} onChange={event => setStatus(event.target.value)} required><option value="">Selecione o status</option><option value="No prazo">No prazo</option><option value="Vencido">Vencido</option></select></div>
      <div className="field"><label htmlFor="dossier-attachment-expiry">Data de vencimento</label><input id="dossier-attachment-expiry" type="date" value={expiry} onChange={event => setExpiry(event.target.value)} /></div>
      <div className="field span-all"><label htmlFor="dossier-attachment-description">Observação</label><textarea id="dossier-attachment-description" rows={3} value={description} onChange={event => setDescription(event.target.value)} maxLength={2000} /></div>
    </div></fieldset>
    <div className={s.actions}><button type="button" className="button secondary" disabled={locked} onClick={() => { setName(''); setDescription(''); setStatus(''); setExpiry(''); setFile(null); retainedFile.current = null; save.setError(''); setOpen(false); }}>Cancelar anexo</button><button type="submit" className="button" disabled={hashing || save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!file || !nome.trim() || !status)}>{hashing || save.busy ? 'Enviando…' : save.uncertain ? 'Tentar confirmar envio' : 'Registrar anexo privado'}</button></div>
  </form></div>;
}
