'use client';
import { useEffect, useRef, useState } from 'react';
import { saveProject } from '@/server/web/actions';
import type { WebRow } from '@/server/web/data';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { equipmentTypeLabel } from './engineering-model';

/** The existing project type controls future route materialization, not equipment data. */
export function ProjectTypePlanning({ project, types, hasAllocations, closed, canManage, destination }: {
  project: WebRow; types: WebRow[]; hasAllocations: boolean; closed: boolean; canManage: boolean; destination: string;
}) {
  const current = typeof project.tipo_equipamento_id === 'string' ? project.tipo_equipamento_id : '';
  const [selected, setSelected] = useState(current);
  const leaving = useRef(false);
  const save = useEngineeringSave<Record<string, unknown>>(async input => {
    const result = await saveProject(input);
    if (result.ok) leaving.current = true;
    return result;
  }, destination);
  const editable = canManage && !closed && !hasAllocations;
  const dirty = selected !== current;
  useEffect(() => {
    if (!dirty && !save.busy && !save.uncertain) return;
    const guard = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]');
      if (!link || link.getAttribute('target') === '_blank' || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      if (link.hasAttribute('data-engineering-reload') && save.stale && !save.busy && !save.uncertain) { leaving.current = true; return; }
      if (!window.confirm(save.uncertain ? 'A classificação ainda não foi confirmada. Sair desta tela?' : 'Há uma classificação não salva. Sair sem salvar?')) { event.preventDefault(); event.stopPropagation(); }
      else leaving.current = true;
    };
    window.addEventListener('beforeunload', guard);
    document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', guard); document.removeEventListener('click', navigate, true); };
  }, [dirty, save.busy, save.uncertain, save.stale]);
  if (!editable) return !current && !hasAllocations && !closed ? <p className="notice">O tipo do roteiro ainda não foi definido. Um gestor de projetos pode defini-lo antes da primeira alocação.</p> : null;
  return <section className="panel"><div className="panel-header"><div><h2>Tipo para o roteiro</h2><p>Define quais modelos serão copiados ao alocar uma célula. Após a primeira alocação, a classificação fica preservada.</p></div></div><div className="panel-content">
    <EngineeringSaveNotice state={save} reload={destination} />
    <form onSubmit={event => { event.preventDefault(); if (save.uncertain) { save.retry(); return; } if (!dirty || save.locked) return;
      void save.send({ submissionId: crypto.randomUUID(), id: project.id, expected_updated_at: project.updated_at, changes: { tipo_equipamento_id: selected || null } }); }}>
      <div className="field"><label htmlFor="planning-project-type">Tipo para o roteiro</label><select id="planning-project-type" value={selected} disabled={save.locked} onChange={event => setSelected(event.target.value)}>
        <option value="">Sem tipo definido</option>{current && !types.some(type => type.id === current) && <option value={current} disabled>Tipo atual indisponível</option>}{types.map(type => <option key={type.id} value={type.id}>{equipmentTypeLabel(type)}</option>)}
      </select></div>
      {!selected && <p className="form-note">Sem tipo, os modelos de roteiro não são copiados automaticamente.</p>}
      <button className="button small secondary" type="submit" disabled={save.busy || save.stale || save.unauthorized || (!dirty && !save.uncertain)}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar envio' : 'Salvar tipo do roteiro'}</button>
    </form>
  </div></section>;
}
