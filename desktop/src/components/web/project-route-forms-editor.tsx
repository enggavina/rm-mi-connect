'use client';
import {useEffect,useRef,useState} from 'react';
import {manageProjectRouteCell} from '@/server/web/project-route-cell-actions';
import type {ProjectRouteCellSnapshot} from '@/server/web/project-route-cell-data';
import type {ManageProjectRouteCellInput} from '@/server/web/project-route-cell-policy';
import {EngineeringSaveNotice,useEngineeringSave} from './engineering-save';
import {routeFormsChanged,routeFormsRequest} from './project-route-cell-model';
import {projectRouteDestination} from './project-route-model';
import s from './project-route-config.module.css';

export function ProjectRouteFormsEditor({snapshot,canManage,destination,disabled=false,onInteractionChange}:{snapshot:ProjectRouteCellSnapshot;
  canManage:boolean;destination:string;disabled?:boolean;onInteractionChange?:(active:boolean)=>void}){
  const [selected,setSelected]=useState(snapshot.allocation.forms_ids),[search,setSearch]=useState(''),[saved,setSaved]=useState(false);
  const leaving=useRef(false),target=projectRouteDestination(destination,snapshot.project.id);
  const save=useEngineeringSave<ManageProjectRouteCellInput>(async input=>{const result=await manageProjectRouteCell(input);if(result.ok){leaving.current=true;setSaved(true);}return result;},target);
  const changed=routeFormsChanged(snapshot.allocation.forms_ids,selected),locked=disabled||save.locked||saved;
  const editable=canManage&&snapshot.can_edit_forms&&snapshot.complete&&!snapshot.project.closed&&!snapshot.allocation.retirada;
  useEffect(()=>{onInteractionChange?.(changed||save.busy||save.uncertain);},[changed,save.busy,save.uncertain,onInteractionChange]);
  useEffect(()=>{
    if(!changed&&!save.busy&&!save.uncertain)return;
    const unload=(event:BeforeUnloadEvent)=>{if(!leaving.current){event.preventDefault();event.returnValue='';}};
    const navigate=(event:MouseEvent)=>{if(leaving.current||event.defaultPrevented||!(event.target instanceof Element))return;const link=event.target.closest('a[href]');
      if(!link||link.getAttribute('target')==='_blank')return;if(!window.confirm('Há uma alteração de formulários ainda não confirmada. Sair desta tela?')){event.preventDefault();event.stopPropagation();}else leaving.current=true;};
    window.addEventListener('beforeunload',unload);document.addEventListener('click',navigate,true);return()=>{window.removeEventListener('beforeunload',unload);document.removeEventListener('click',navigate,true);};
  },[changed,save.busy,save.uncertain]);
  const shown=snapshot.forms.filter(form=>(form.titulo??'').toLocaleLowerCase('pt-BR').includes(search.toLocaleLowerCase('pt-BR')));
  return <form className={s.editor} data-route-forms onSubmit={event=>{event.preventDefault();if(save.uncertain){save.retry();return;}if(!editable||locked)return;
    try{void save.send(routeFormsRequest(snapshot,selected,crypto.randomUUID()));}catch(error){save.setError(error instanceof Error?error.message:'Confira os formulários selecionados.');}}}>
    <h3>Formulários desta célula</h3><p className="form-note">As alterações pertencem somente a esta célula neste projeto. Formulários com início ou conteúdo persistido permanecem vinculados.</p>
    <EngineeringSaveNotice state={save} reload={target}/>{saved&&<p className="notice success" role="status">Formulários salvos. Atualizando a célula…</p>}
    {(!editable||snapshot.forms_reason)&&<p className="notice" role="status">{snapshot.forms_reason||'Configuração disponível para consulta conforme seu acesso.'}</p>}
    {!snapshot.complete?<p className="notice">A configuração completa precisa estar disponível antes de alterar os vínculos.</p>:<>
      <div className="field"><label htmlFor="route-form-search">Buscar formulário</label><input id="route-form-search" value={search} onChange={event=>setSearch(event.target.value)} maxLength={200} disabled={save.busy||save.uncertain}/></div>
      <fieldset disabled={!editable||locked} className={s.choices}><legend>Formulários vinculados ({selected.length})</legend>{shown.map(form=>{
        const protectedForm=form.assigned&&!form.can_remove;return <label className={s.choice} key={form.id}><input type="checkbox" checked={selected.includes(form.id)} aria-label={`Vincular ${form.titulo||'formulário histórico'}`}
          disabled={protectedForm||!selected.includes(form.id)&&selected.length>=500||!form.ativo&&!form.assigned}
          onChange={event=>setSelected(ids=>event.target.checked?[...ids,form.id]:ids.filter(id=>id!==form.id))}/><span>{form.titulo||'Formulário histórico'}{protectedForm&&<small>{form.reason||'Uso persistido: vínculo preservado.'}</small>}{!form.ativo&&<small>Modelo inativo; vínculo existente preservado.</small>}</span></label>;})}
        {!shown.length&&<p className="form-note">Nenhum formulário encontrado.</p>}
      </fieldset></>}
    {editable&&<div className={s.actions}>{changed&&!save.uncertain&&<button type="button" className="button secondary" disabled={locked} onClick={()=>{setSelected(snapshot.allocation.forms_ids);save.setError('');}}>Descartar alterações</button>}
      <button className="button" disabled={save.busy||save.stale||save.unauthorized||saved||disabled||!changed&&!save.uncertain}>{save.busy?'Salvando…':save.uncertain?'Tentar confirmar envio':'Salvar formulários'}</button></div>}
  </form>;
}
