'use client';

import { useEffect, useRef, useState } from 'react';
import { saveProjectEquipment } from '@/server/web/project-equipment-actions';
import type { ProjectEquipmentSnapshot, SaveProjectEquipmentInput } from '@/server/web/project-equipment-policy';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { Icon } from './icons';
import { equipmentDisplayValue, equipmentFieldGroups, equipmentFieldLabels, projectEquipmentChanges, projectEquipmentDraft, projectEquipmentRequest,
  type ProjectEquipmentDraft, type ProjectEquipmentField } from './project-equipment-model';
import s from './project-equipment.module.css';

function useEquipmentExitGuard(dirty: boolean, pending: boolean, stale: boolean, leaving: { current: boolean }) {
  useEffect(() => {
    if (!dirty && !pending) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]'); if (!link || link.getAttribute('target') === '_blank') return;
      if (link.hasAttribute('data-engineering-reload') && stale && !pending) { leaving.current = true; return; }
      if (!window.confirm(pending ? 'Este envio ainda não foi confirmado. Sair desta tela?' : 'Há dados técnicos não enviados. Sair sem salvar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [dirty, pending, stale, leaving]);
}

export function ProjectEquipmentEditor({ snapshot }: { snapshot: ProjectEquipmentSnapshot }) {
  const [open, setOpen] = useState(false), [draft, setDraft] = useState<ProjectEquipmentDraft>(() => projectEquipmentDraft(snapshot));
  const [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false);
  const leaving = useRef(false), heading = useRef<HTMLHeadingElement>(null), launch = useRef<HTMLButtonElement>(null);
  const destination = `/projetos/${snapshot.project.id}?tab=informacoes#dados-equipamento`;
  const save = useEngineeringSave<SaveProjectEquipmentInput>(async input => {
    const result = await saveProjectEquipment(input); if (result.ok) { leaving.current = true; setSaved(true); } return result;
  }, destination);
  let changes: ReturnType<typeof projectEquipmentChanges> = {}, validation = '';
  try { changes = projectEquipmentChanges(snapshot, draft); } catch (error) { validation = error instanceof Error ? error.message : 'Confira os dados técnicos.'; }
  const changedFields = Object.keys(changes) as ProjectEquipmentField[];
  const original = projectEquipmentDraft(snapshot), dirty = Object.keys(original).some(key => draft[key as ProjectEquipmentField] !== original[key as ProjectEquipmentField]);
  const locked = save.locked || saved;
  useEquipmentExitGuard(open && dirty, save.busy || save.uncertain, save.stale, leaving);
  useEffect(() => { if (open) heading.current?.focus(); }, [open]);
  function update(key: ProjectEquipmentField, value: string) { setDraft(current => ({ ...current, [key]: value })); setConfirmed(false); save.setError(''); }
  function submit() {
    if (save.uncertain) { save.retry(); return; }
    if (locked || !confirmed || !changedFields.length || validation) return;
    try { void save.send(projectEquipmentRequest(snapshot, draft, crypto.randomUUID())); }
    catch (error) { save.setError(error instanceof Error ? error.message : 'Confira os dados técnicos.'); }
  }
  function cancel() {
    setDraft(projectEquipmentDraft(snapshot)); setConfirmed(false); save.setError(''); setOpen(false);
    setTimeout(() => launch.current?.focus(), 0);
  }
  return <div className={s.editor} data-project-equipment-editor>
    {!open ? <button ref={launch} type="button" className="button secondary" onClick={() => setOpen(true)}><Icon name="edit" size={14} />Editar dados técnicos</button>
      : <form onSubmit={event => { event.preventDefault(); submit(); }}>
        <h3 ref={heading} tabIndex={-1}>Editar dados técnicos do equipamento</h3>
        <p className={s.intro}>Confira os dados e revise as alterações antes de salvar. Campos vazios removem somente a informação alterada.</p>
        <p className={s.context}>Projeto: <strong>{snapshot.project.numero ? `OS ${snapshot.project.numero.trim()}` : 'Projeto em recebimento'}</strong> · Equipamento: <strong>{snapshot.equipment?.numero_serie || snapshot.equipment?.modelo || snapshot.equipment?.fabricante || 'Equipamento vinculado'}</strong></p>
        <EngineeringSaveNotice state={save} reload={destination} />
        {save.busy && <p role="status" className="notice">Salvando dados técnicos…</p>}{saved && <p role="status" className="notice success">Dados técnicos salvos. Atualizando o projeto…</p>}
        <fieldset className={s.fields} disabled={locked}>
          {equipmentFieldGroups.map(group => <fieldset key={group.id} className={s.section}><legend>{group.title}</legend><div className="form-grid">
            {group.fields.map(field => <div key={field.key} className={`field ${'multiline' in field ? 'span-all' : ''}`}>
              <label htmlFor={`equipment-${field.key}`}>{field.label}</label>
              {field.key === 'placa_motor' ? <select id={`equipment-${field.key}`} value={draft[field.key]} onChange={event => update(field.key, event.target.value)}>
                <option value="">Não informado</option><option value="c___placa">Com placa</option><option value="s___placa">Sem placa</option>
                {!!draft[field.key] && !['c___placa', 's___placa'].includes(draft[field.key]) && <option value={draft[field.key]}>Valor atual: {draft[field.key]}</option>}
              </select> : 'multiline' in field ? <textarea id={`equipment-${field.key}`} rows={3} value={draft[field.key]} onChange={event => update(field.key, event.target.value)} />
                : <input id={`equipment-${field.key}`} type="text" inputMode={'numeric' in field ? field.key === 'numero_cabos' ? 'numeric' : 'decimal' : undefined} value={draft[field.key]} onChange={event => update(field.key, event.target.value)} />}
              {(field.key === 'fp' || field.key === 'fs') && <p className={s.hint}>Use ponto ou vírgula decimal, sem separador de milhares.</p>}
            </div>)}
          </div></fieldset>)}
          {validation && <p role="alert" className="notice error">{validation}</p>}
          <section className={s.summary} aria-label="Revisão das alterações técnicas">
            <h4>{changedFields.length ? `${changedFields.length} ${changedFields.length === 1 ? 'alteração para conferir' : 'alterações para conferir'}` : 'Nenhuma alteração para salvar'}</h4>
            {!!changedFields.length && <><div className={s.tableHead} aria-hidden="true"><span>Campo</span><span>Atual</span><span>Após salvar</span></div><div className={s.changes}>{changedFields.map(key => <div key={key} className={s.change} data-equipment-change={key}>
              <strong>{equipmentFieldLabels[key]}</strong><span><small>Atual</small>{equipmentDisplayValue(key, snapshot.equipment?.[key])}</span><span><small>Após salvar</small>{equipmentDisplayValue(key, changes[key])}</span>
            </div>)}</div><label className={s.confirmation}><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} />Confirmo a alteração dos dados técnicos deste equipamento no projeto {snapshot.project.numero ? `OS ${snapshot.project.numero.trim()}` : 'em recebimento'}.</label></>}
            {!changedFields.length && <p className={s.notice}>Edite um campo para visualizar a comparação com o valor atual.</p>}
          </section>
        </fieldset>
        <div className={s.actions}><button type="button" className="button secondary" disabled={locked} onClick={cancel}>Cancelar edição</button><button type="submit" className="button" disabled={save.busy || save.stale || save.unauthorized || saved || !save.uncertain && (!confirmed || !changedFields.length || !!validation)}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : 'Salvar dados técnicos'}</button></div>
      </form>}
  </div>;
}
