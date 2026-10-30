'use client';

import { useEffect, useRef, useState } from 'react';
import type { WebActionResult } from '@/server/web/mutation';
import type { ProjectAttachmentSnapshot, ProjectAttachmentVersionInput } from '@/server/web/project-attachment-version-policy';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { DOSSIER_FILE_ACCEPT, dossierFileError } from './project-dossier-model';
import { attachmentFileSize, attachmentVersionDraft, attachmentVersionRequest, attachmentVersionValidation, type AttachmentVersionDraft } from './project-attachment-version-model';
import { Icon } from './icons';
import s from './project-attachment-version.module.css';

async function sendVersion(input: ProjectAttachmentVersionInput, file: File, series: NonNullable<ProjectAttachmentSnapshot['series']>): Promise<WebActionResult> {
  const body = new FormData(); body.set('input', JSON.stringify(input)); body.set('file', file, file.name);
  const response = await fetch(`/api/web/projects/${input.projeto_id}/attachments/${input.source_attachment_id}/versions`, { method: 'POST', body, credentials: 'same-origin' });
  let result: unknown; try { result = await response.json(); } catch { /* Preserve the exact file and intent when the response is uncertain. */ }
  if (result && typeof result === 'object' && 'ok' in result) {
    const value = result as WebActionResult;
    if (value.ok && response.ok && value.data?.operation === 'finalize_project_attachment_version' && value.data.id === input.submissionId
      && value.data.projeto_id === input.projeto_id && value.data.record?.attachment_id === input.submissionId
      && value.data.record.source_attachment_id === input.source_attachment_id && value.data.record.root_attachment_id === series.root_id
      && value.data.record.revision === series.head_revision + 1 && value.data.record.visivel_cliente === false) return value;
    if (!value.ok && typeof value.error === 'string' && typeof value.code === 'string') return value;
  }
  return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível confirmar a nova versão. Tente novamente com o mesmo arquivo e protocolo nesta tela.' };
}

export function ProjectAttachmentVersionEditor({ snapshot }: { snapshot: ProjectAttachmentSnapshot }) {
  const [open, setOpen] = useState(false), [draft, setDraft] = useState(() => attachmentVersionDraft(snapshot));
  const [file, setFile] = useState<File | null>(null), [confirmed, setConfirmed] = useState(false), [hashing, setHashing] = useState(false), [saved, setSaved] = useState(false);
  const retainedFile = useRef<File | null>(null), computing = useRef(false), leaving = useRef(false), heading = useRef<HTMLHeadingElement>(null), launch = useRef<HTMLButtonElement>(null);
  const reload = `/projetos/${snapshot.project.id}/anexos/${snapshot.attachment.id}#anexo`;
  const save = useEngineeringSave<ProjectAttachmentVersionInput>(async input => {
    const selected = retainedFile.current;
    if (!selected || selected.name !== input.filename || selected.type !== input.mime_type || selected.size !== input.byte_size) return { ok: false, code: 'UNAVAILABLE', error: 'Mantenha o arquivo original selecionado para confirmar este envio.' };
    if (!snapshot.series) return { ok: false, code: 'UNAVAILABLE', error: 'Não foi possível conferir a sequência deste anexo.' };
    const result = await sendVersion(input, selected, snapshot.series); if (result.ok) { leaving.current = true; setSaved(true); } return result;
  }, input => `/projetos/${input.projeto_id}/anexos/${input.submissionId}#anexo`);
  const locked = hashing || save.locked || saved, validation = attachmentVersionValidation(file, draft);
  const baseline = attachmentVersionDraft(snapshot);
  const currentSummary = [snapshot.attachment.nome || 'Anexo do projeto', snapshot.attachment.filename || 'Arquivo registrado',
    snapshot.attachment.status || 'Status não informado', `Vencimento: ${snapshot.attachment.data_vencimento?.slice(0, 10) || 'Não informado'}`,
    `Observação: ${snapshot.attachment.descricao || 'Não informada'}`].join('\n');
  const nextSummary = [draft.nome.trim() || 'Informe o título', file?.name || 'Selecione o novo arquivo', draft.status || 'Selecione o status',
    `Vencimento: ${draft.expiry || 'Não informado'}`, `Observação: ${draft.descricao.trim() || 'Não informada'}`].join('\n');
  const dirty = !!file || (Object.keys(baseline) as (keyof AttachmentVersionDraft)[]).some(key => draft[key] !== baseline[key]);
  useEffect(() => { if (open) heading.current?.focus(); }, [open]);
  useEffect(() => {
    if (!open || !dirty && !hashing && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && save.stale && !hashing && !save.busy && !save.uncertain) { leaving.current = true; return; }
      if (!window.confirm(hashing || save.busy || save.uncertain ? 'Esta nova versão ainda não foi confirmada. Sair desta tela?' : 'Há uma nova versão não enviada. Sair sem salvar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [open, dirty, hashing, save.busy, save.uncertain, save.stale]);
  function update(key: keyof AttachmentVersionDraft, value: string) { setDraft(current => ({ ...current, [key]: value })); setConfirmed(false); save.setError(''); }
  function cancel() { setDraft(attachmentVersionDraft(snapshot)); setFile(null); retainedFile.current = null; setConfirmed(false); save.setError(''); setOpen(false); setTimeout(() => launch.current?.focus(), 0); }
  async function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (locked || computing.current || !confirmed || validation) return;
    const selected = retainedFile.current; if (!selected) { save.setError('Selecione o novo arquivo.'); return; }
    computing.current = true; setHashing(true); save.setError('');
    try {
      let digest: ArrayBuffer;
      try { digest = await crypto.subtle.digest('SHA-256', await selected.arrayBuffer()); }
      catch { throw new Error('Não foi possível conferir o arquivo. Selecione-o novamente e tente enviar.'); }
      const sha256 = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
      await save.send(attachmentVersionRequest(snapshot, selected, draft, sha256, crypto.randomUUID()));
    } catch (error) { save.setError(error instanceof Error ? error.message : 'Não foi possível conferir o arquivo. Tente novamente.'); }
    finally { computing.current = false; setHashing(false); }
  }
  return <div className={s.editor} data-project-attachment-version-editor>
    {!open ? <button type="button" ref={launch} className="button secondary" onClick={() => setOpen(true)}><Icon name="plus" size={14} />Enviar nova versão</button>
      : <form onSubmit={event => { event.preventDefault(); void submit(); }}>
        <h3 tabIndex={-1} ref={heading}>Nova versão do anexo</h3><p className={s.note}>Selecione o novo arquivo, confira os dados e informe o motivo. O arquivo atual e as versões anteriores continuarão disponíveis.</p>
        <EngineeringSaveNotice state={save} reload={reload} />
        {(hashing || save.busy) && <p role="status" className="notice">{hashing && !save.busy ? 'Conferindo arquivo…' : 'Enviando e registrando a nova versão…'}</p>}
        {saved && <p role="status" className="notice success">Nova versão registrada. Atualizando o anexo…</p>}
        {save.uncertain && <p className="notice">O arquivo e os dados selecionados permanecem nesta tela para confirmar o mesmo envio.</p>}
        <fieldset className={s.fields} disabled={locked}><div className="form-grid">
          <div className="field span-all"><label htmlFor="attachment-version-file">Novo arquivo</label><input id="attachment-version-file" type="file" accept={DOSSIER_FILE_ACCEPT} onChange={event => {
            if (computing.current || save.locked || saved) return;
            const selected = event.target.files?.[0] ?? null, error = selected ? dossierFileError(selected) : null; save.setError(error ?? ''); setConfirmed(false);
            if (error) { retainedFile.current = null; setFile(null); event.target.value = ''; return; }
            retainedFile.current = selected; setFile(selected);
          }} /><p className={s.hint}>PDF, JPEG ou PNG · até 20 MiB por arquivo.</p>{file && <div className={s.file}><strong>{file.name}</strong><p>{attachmentFileSize(file.size)}</p></div>}</div>
          <div className="field span-all"><label htmlFor="attachment-version-name">Título do anexo</label><input id="attachment-version-name" value={draft.nome} onChange={event => update('nome', event.target.value)} /></div>
          <div className="field"><label htmlFor="attachment-version-status">Status do documento</label><select id="attachment-version-status" value={draft.status} onChange={event => update('status', event.target.value)}><option value="">Selecione o status</option><option value="No prazo">No prazo</option><option value="Vencido">Vencido</option></select></div>
          <div className="field"><label htmlFor="attachment-version-expiry">Data de vencimento</label><input id="attachment-version-expiry" type="date" value={draft.expiry} onChange={event => update('expiry', event.target.value)} /></div>
          <div className="field span-all"><label htmlFor="attachment-version-description">Observação</label><textarea id="attachment-version-description" rows={3} value={draft.descricao} onChange={event => update('descricao', event.target.value)} /></div>
          <div className="field span-all"><label htmlFor="attachment-version-reason">Motivo da substituição</label><textarea id="attachment-version-reason" rows={3} value={draft.motivo} onChange={event => update('motivo', event.target.value)} /><p className={s.hint}>Obrigatório. Até 2.000 caracteres.</p></div>
        </div><section className={s.summary} aria-label="Revisão da nova versão"><h4>Confira a nova versão</h4><div className={s.comparison}>
          <div><h5>Versão atual {snapshot.series?.head_revision}</h5><p>{currentSummary}</p></div>
          <div><h5>Nova versão {(snapshot.series?.head_revision ?? 0) + 1}</h5><p>{nextSummary}</p></div>
        </div><div className={s.reason}><strong>Motivo da substituição</strong><p>{draft.motivo.trim() || 'Informe o motivo'}</p></div><p className={s.note}>O envio acrescenta uma versão ao histórico e preserva os arquivos anteriores.</p>
          <label className={s.confirmation}><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Confirmo a nova versão deste anexo e o motivo informado.</label>
        </section>{dirty && validation && <p role="status" className={s.validation}>{validation}</p>}</fieldset>
        <div className={s.actions}><button type="button" className="button secondary" disabled={locked} onClick={cancel}>Cancelar nova versão</button><button type="submit" className="button" disabled={hashing || save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!confirmed || !!validation)}>{hashing || save.busy ? 'Enviando…' : save.uncertain ? 'Tentar confirmar envio' : 'Registrar nova versão'}</button></div>
      </form>}
  </div>;
}
