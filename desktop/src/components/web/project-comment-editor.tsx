'use client';

import { useEffect, useRef, useState } from 'react';
import { editProjectComment } from '@/server/web/project-comment-actions';
import type { EditProjectCommentInput, ProjectCommentSnapshot } from '@/server/web/project-comment-policy';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { Icon } from './icons';
import { projectCommentChanged, projectCommentDraft, projectCommentRequest, projectCommentValidation } from './project-comment-model';
import s from './project-comment.module.css';

export function ProjectCommentCorrection({ snapshot }: { snapshot: ProjectCommentSnapshot }) {
  const [open, setOpen] = useState(false), [draft, setDraft] = useState(() => projectCommentDraft(snapshot));
  const [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false);
  const leaving = useRef(false), launch = useRef<HTMLButtonElement>(null), heading = useRef<HTMLHeadingElement>(null);
  const destination = `/projetos/${snapshot.project.id}/comentarios/${snapshot.comment.id}#comentario`;
  const save = useEngineeringSave<EditProjectCommentInput>(async input => {
    const result = await editProjectComment(input); if (result.ok) { leaving.current = true; setSaved(true); } return result;
  }, destination);
  const changed = projectCommentChanged(snapshot, draft), validation = projectCommentValidation(draft), locked = save.locked || saved;
  const dirty = draft.evento !== (snapshot.comment.evento ?? '') || draft.motivo !== '';
  useEffect(() => { if (open) heading.current?.focus(); }, [open]);
  useEffect(() => {
    if (!open || !dirty && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && save.stale && !save.busy && !save.uncertain) { leaving.current = true; return; }
      if (!window.confirm(save.busy || save.uncertain ? 'Esta correção ainda não foi confirmada. Sair desta tela?' : 'Há uma correção não enviada. Sair sem salvar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [open, dirty, save.busy, save.uncertain, save.stale]);
  function update(key: 'evento' | 'motivo', value: string) { setDraft(current => ({ ...current, [key]: value })); setConfirmed(false); save.setError(''); }
  function cancel() { setDraft(projectCommentDraft(snapshot)); setConfirmed(false); save.setError(''); setOpen(false); setTimeout(() => launch.current?.focus(), 0); }
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (locked || !confirmed || !changed || validation) return;
    try { void save.send(projectCommentRequest(snapshot, draft, crypto.randomUUID())); }
    catch (error) { save.setError(error instanceof Error ? error.message : 'Confira a correção do comentário.'); }
  }
  return <div className={s.editor} data-project-comment-editor>
    {!open ? <button ref={launch} type="button" className="button secondary" onClick={() => setOpen(true)}><Icon name="edit" size={14} />Corrigir comentário</button>
      : <form onSubmit={event => { event.preventDefault(); submit(); }}>
        <h3 ref={heading} tabIndex={-1}>Corrigir comentário</h3><p className={s.note}>Revise o texto e informe o motivo. O autor, a data original e a célula permanecem registrados; a correção entra no histórico abaixo.</p>
        <EngineeringSaveNotice state={save} reload={destination} />
        {save.busy && <p role="status" className="notice">Salvando correção…</p>}{saved && <p role="status" className="notice success">Correção salva. Atualizando o comentário…</p>}
        <fieldset className={s.fields} disabled={locked}>
          <div className="field"><label htmlFor="comment-evento">Texto do comentário</label><textarea id="comment-evento" rows={7} value={draft.evento} onChange={event => update('evento', event.target.value)} aria-describedby="comment-evento-help" /><p id="comment-evento-help" className={s.hint}>Até 10.000 caracteres.</p></div>
          <div className="field"><label htmlFor="comment-motivo">Motivo da correção</label><textarea id="comment-motivo" rows={3} value={draft.motivo} onChange={event => update('motivo', event.target.value)} aria-describedby="comment-motivo-help" /><p id="comment-motivo-help" className={s.hint}>Obrigatório. Até 2.000 caracteres.</p></div>
          <section className={s.summary} aria-label="Revisão da correção do comentário"><h4>{changed ? 'Confira a correção' : 'Nenhuma alteração no texto'}</h4>
            {changed ? <><div className={s.comparison}><div><h5>Atual</h5><p>{snapshot.comment.evento || 'Sem texto registrado'}</p></div><div><h5>Após salvar</h5><p>{draft.evento.trim() || 'Informe o novo texto'}</p></div></div>
              <label className={s.confirmation}><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Confirmo a correção deste comentário e o motivo informado.</label></>
              : <p className={s.note}>Altere o comentário para visualizar a comparação antes de salvar.</p>}
          </section>
          {dirty && validation && <p className={s.validation} role="status">{validation}</p>}
        </fieldset>
        <div className={s.actions}><button type="button" className="button secondary" disabled={locked} onClick={cancel}>Cancelar edição</button><button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!confirmed || !changed || !!validation)}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : 'Salvar correção'}</button></div>
      </form>}
  </div>;
}
