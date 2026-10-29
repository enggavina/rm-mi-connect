'use client';

import { useEffect, useRef, useState } from 'react';
import { saveProjectRoute } from '@/server/web/project-route-actions';
import type { ProjectRouteSnapshot } from '@/server/web/project-route-data';
import type { SaveProjectRouteInput } from '@/server/web/project-route-policy';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { projectRouteDestination, projectRouteNeedsNormalization, projectRouteOrderChanged, projectRouteRequest, moveProjectRouteItem } from './project-route-model';
import { Empty, Status } from './ui';
import { Icon } from './icons';
import s from './project-route.module.css';

export function ProjectRouteEditor({ snapshot, canEdit, destination }: { snapshot: ProjectRouteSnapshot; canEdit: boolean; destination: string }) {
  const [items, setItems] = useState(snapshot.items), [normalize, setNormalize] = useState(false), [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false);
  const leaving = useRef(false);
  const target = projectRouteDestination(destination, snapshot.project.id);
  const save = useEngineeringSave<SaveProjectRouteInput>(async input => {
    const result = await saveProjectRoute(input);
    if (result.ok) { leaving.current = true; setSaved(true); }
    return result;
  }, target);
  const changed = normalize || projectRouteOrderChanged(items, snapshot.items);
  const editable = canEdit && !snapshot.project.closed && snapshot.complete;
  const locked = save.locked || saved;
  useEffect(() => {
    if (!changed && !save.busy && !save.uncertain) return;
    const unload = (event: BeforeUnloadEvent) => { if (!leaving.current) { event.preventDefault(); event.returnValue = ''; } };
    const navigate = (event: MouseEvent) => {
      if (leaving.current || event.defaultPrevented || !(event.target instanceof Element)) return;
      const link = event.target.closest('a[href]');
      if (!link || link.getAttribute('target') === '_blank') return;
      if (!window.confirm(save.uncertain ? 'O resultado do envio ainda não foi confirmado. Sair desta tela?' : 'Há alterações não salvas na sequência. Sair sem salvar?')) {
        event.preventDefault(); event.stopPropagation();
      } else leaving.current = true;
    };
    window.addEventListener('beforeunload', unload); document.addEventListener('click', navigate, true);
    return () => { window.removeEventListener('beforeunload', unload); document.removeEventListener('click', navigate, true); };
  }, [changed, save.busy, save.uncertain]);
  function move(id: string, targetIndex: number) { setItems(current => moveProjectRouteItem(current, id, targetIndex)); setConfirmed(false); save.setError(''); }
  function reload() { leaving.current = true; window.location.assign(target); }
  function submit() {
    if (!editable || locked) return;
    if (!changed || !confirmed) { save.setError('Confira a sequência completa e confirme antes de salvar.'); return; }
    void save.send(projectRouteRequest(snapshot, items, crypto.randomUUID()));
  }
  if (!snapshot.complete) return <Empty title="Este roteiro excede o limite de edição" detail="A sequência completa precisa ser conferida. Nenhuma parte do roteiro será salva isoladamente." icon="board" />;
  if (!items.length) return <Empty title="Nenhuma célula alocada" detail="Aloque as células do projeto para definir a sequência de execução." icon="board" />;
  return <form onSubmit={event => { event.preventDefault(); submit(); }}>
    {snapshot.project.closed && <p className="notice">Projeto encerrado: a sequência permanece disponível para consulta.</p>}
    <div className={s.intro}><p className={s.note}>Defina a sequência das células deste projeto. As prioridades e posições dos projetos nas filas das células serão preservadas.</p>{editable && <button className="button small secondary" type="button" disabled={locked || normalize} onClick={() => { setNormalize(true); setConfirmed(false); }}>{normalize ? 'Sequência selecionada' : 'Confirmar sequência exibida'}</button>}</div>
    <div className={s.list}>{items.map((item, index) => {
      const label = item.celula_nome || 'Célula não informada';
      return <article className={s.item} key={item.id} data-route-item={item.id}>
        <span className={s.position} aria-label={`Posição proposta ${index + 1}`}>{index + 1}</span>
        <div><h3 className={s.title}>{label}</h3><div className={s.meta}><Status value={item.status} /><Status value={item.visibilidade ? 'ativo' : 'pendente'} label={item.visibilidade ? 'Visível no mobile' : 'Oculta no mobile'} /><span className={s.note}>{item.indice === null ? 'Sem ordem salva' : `Ordem salva: ${item.indice}`}</span></div></div>
        {editable && <div className={s.controls}><button type="button" className="button small secondary" disabled={locked || index === 0} aria-label={`Mover ${label} para cima`} onClick={() => move(item.id, index - 1)}><Icon name="chevron" size={12} style={{ transform: 'rotate(-90deg)' }} />Subir</button><button type="button" className="button small secondary" disabled={locked || index === items.length - 1} aria-label={`Mover ${label} para baixo`} onClick={() => move(item.id, index + 1)}><Icon name="chevron" size={12} style={{ transform: 'rotate(90deg)' }} />Descer</button></div>}
      </article>;
    })}</div>
    {editable && <div className={s.save}>
      <EngineeringSaveNotice state={{ ...save, stale: false }} reload={target} />
      {save.stale && <div className="notice">O projeto ou suas células mudaram. Recarregue a sequência completa antes de editar novamente.<p><button className="button secondary" type="button" onClick={reload}>Recarregar roteiro</button></p></div>}
      {saved && <div className="notice success" role="status">Sequência salva. Atualizando o roteiro…</div>}
      {changed && <label className="check-label"><input type="checkbox" checked={confirmed} disabled={locked} onChange={event => setConfirmed(event.target.checked)} />Conferi todas as células e desejo salvar esta sequência.</label>}
      {!changed && projectRouteNeedsNormalization(items) && <p className={s.note}>A ordem salva será preservada até você confirmar uma nova sequência.</p>}
      <div className={s.actions}>{changed && !locked && <button className="button secondary" type="button" onClick={() => { setItems(snapshot.items); setNormalize(false); setConfirmed(false); save.setError(''); }}>Descartar alterações</button>}{save.uncertain ? <button className="button" type="button" disabled={save.busy} onClick={save.retry}>Tentar confirmar envio</button> : !save.stale && !save.unauthorized && <button className="button" type="submit" disabled={locked || !changed || !confirmed}>{save.busy ? 'Salvando…' : 'Salvar sequência das células'}</button>}</div>
    </div>}
  </form>;
}
