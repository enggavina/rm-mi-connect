'use client';
import {useEffect,useState} from 'react';
import {manageProjectRouteCell} from '@/server/web/project-route-cell-actions';
import type {ProjectRouteCellSnapshot} from '@/server/web/project-route-cell-data';
import type {ManageProjectRouteCellInput} from '@/server/web/project-route-cell-policy';
import {EngineeringSaveNotice,useEngineeringSave} from './engineering-save';
import {removeRouteCellRequest} from './project-route-cell-model';
import s from './project-route-config.module.css';
export function ProjectRouteCellRemoval({snapshot,canManage,disabled=false,onInteractionChange}:{snapshot:ProjectRouteCellSnapshot;canManage:boolean;disabled?:boolean;onInteractionChange?:(active:boolean)=>void}){
  const [open,setOpen]=useState(false),[confirmed,setConfirmed]=useState(false),[saved,setSaved]=useState(false);
  const destination=`/projetos/${snapshot.project.id}?tab=roteiro`;
  const save=useEngineeringSave<ManageProjectRouteCellInput>(async input=>{const result=await manageProjectRouteCell(input);if(result.ok)setSaved(true);return result;},destination);
  useEffect(()=>{onInteractionChange?.(open||save.busy||save.uncertain);},[open,save.busy,save.uncertain,onInteractionChange]);
  if(!canManage)return null;const locked=disabled||save.locked||saved;
  return <section className={s.removal} data-route-cell-removal><h3>Remover célula do roteiro</h3>
    {!snapshot.can_remove_cell&&<p className="form-note">{snapshot.remove_reason||'Há evidência operacional que impede a remoção desta célula.'}</p>}
    {!open?<button type="button" className="button secondary" disabled={disabled||!snapshot.can_remove_cell} onClick={()=>setOpen(true)}>Remover do roteiro</button>
      :<form onSubmit={event=>{event.preventDefault();if(save.uncertain){save.retry();return;}if(locked)return;try{void save.send(removeRouteCellRequest(snapshot,confirmed,crypto.randomUUID()));}catch(error){save.setError(error instanceof Error?error.message:'Confira a remoção.');}}}>
        <EngineeringSaveNotice state={save} reload={destination}/>{saved&&<p className="notice success" role="status">Célula removida do roteiro. Atualizando projeto…</p>}
        <p>Remover <strong>{snapshot.allocation.celula_nome||'esta célula'}</strong> deste projeto? Serão retiradas suas configurações não utilizadas: {snapshot.removal_counts.photos} fotos previstas e {snapshot.removal_counts.rules} regras. Os formulários serão desvinculados.</p>
        <p className="form-note">Os identificadores são preservados para manter a proteção dos envios offline. Uma célula com evidência operacional não pode ser removida por esta ação.</p>
        <label className="check-label"><input type="checkbox" checked={confirmed} disabled={locked} onChange={event=>setConfirmed(event.target.checked)}/>Confirmo a remoção desta célula e de suas configurações não utilizadas.</label>
        <div className={s.actions}><button type="button" className="button secondary" disabled={save.busy||save.uncertain} onClick={()=>{setOpen(false);setConfirmed(false);}}>Cancelar</button>
          <button className="button" disabled={save.busy||save.stale||save.unauthorized||saved||disabled||!confirmed&&!save.uncertain}>{save.busy?'Removendo…':save.uncertain?'Tentar confirmar envio':'Confirmar remoção'}</button></div>
      </form>}
  </section>;
}
