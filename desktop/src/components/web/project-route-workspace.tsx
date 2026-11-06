'use client';
import {useCallback,useState,type ReactNode} from 'react';
import type {ProjectRouteSnapshot} from '@/server/web/project-route-data';
import type {ProjectRouteCellSnapshot} from '@/server/web/project-route-cell-data';
import type {OperationalPhotoSnapshot} from '@/server/web/operational-photo-data';
import type {OperationalStageRuleSnapshot} from '@/server/web/operational-stage-rule-data';
import {ProjectRouteEditor} from './project-route-editor';
import {ProjectRouteFormsEditor} from './project-route-forms-editor';
import {ProjectRouteCellRemoval} from './project-route-cell-removal';
import {OperationalPhotoEditor} from './operational-photo-editor';
import {OperationalStageRuleEditor} from './operational-stage-rule-editor';
import s from './project-route-config.module.css';

type Resource='photos'|'forms'|'approvals'|'remove';
type ContextSnapshot={project:{id:string;updated_at:string};allocation:{id:string;projeto_id:string;celula_id:string;updated_at:string}};
export function routeCellContextCurrent(route:ProjectRouteSnapshot,allocationId:string,snapshot:ContextSnapshot|null){
  const item=route.items.find(item=>item.id===allocationId);
  return !!snapshot&&!!item&&snapshot.project.id===route.project.id&&snapshot.project.updated_at===route.project.updated_at
    &&snapshot.allocation.id===allocationId&&snapshot.allocation.projeto_id===route.project.id
    &&snapshot.allocation.celula_id===item.celula_id&&snapshot.allocation.updated_at===item.updated_at;
}
export function ProjectRouteWorkspace({route,canManage,destination,itemDetails,allocationId,allocationName,photos,forms,rules,
  canReadPhotos,canReadForms,canReadApprovals,initialTab}:{route:ProjectRouteSnapshot;canManage:boolean;destination:string;
  itemDetails?:Record<string,ReactNode>;allocationId?:string;allocationName?:string;photos:OperationalPhotoSnapshot|null;
  forms:ProjectRouteCellSnapshot|null;rules:OperationalStageRuleSnapshot|null;canReadPhotos:boolean;canReadForms:boolean;canReadApprovals:boolean;initialTab?:string}){
  const tabs=([{id:'photos',label:'Fotos',allowed:canReadPhotos},{id:'forms',label:'Formulários',allowed:canReadForms},{id:'approvals',label:'Aprovações',allowed:canReadApprovals}] as const).filter(tab=>tab.allowed);
  const [tab,setTab]=useState<string>(()=>tabs.some(tab=>tab.id===initialTab)?initialTab!:tabs[0]?.id??''),[orderActive,setOrderActive]=useState(false);
  const [active,setActive]=useState<Resource|null>(null);
  const photoInteraction=useCallback((value:boolean)=>setActive(current=>value?'photos':current==='photos'?null:current),[]);
  const formInteraction=useCallback((value:boolean)=>setActive(current=>value?'forms':current==='forms'?null:current),[]);
  const ruleInteraction=useCallback((value:boolean)=>setActive(current=>value?'approvals':current==='approvals'?null:current),[]);
  const removeInteraction=useCallback((value:boolean)=>setActive(current=>value?'remove':current==='remove'?null:current),[]);
  const target=(name:string)=>`${destination}&route_tab=${name}#configuracao-roteiro`;
  const photosCurrent=!!allocationId&&routeCellContextCurrent(route,allocationId,photos),formsCurrent=!!allocationId&&routeCellContextCurrent(route,allocationId,forms),rulesCurrent=!!allocationId&&routeCellContextCurrent(route,allocationId,rules);
  return <>
    <ProjectRouteEditor snapshot={route} canEdit={canManage} destination={destination} itemDetails={itemDetails} disabled={active!==null} onInteractionChange={setOrderActive}/>
    {allocationId&&<section id="configuracao-roteiro" style={{marginTop:28}} data-route-configuration={allocationId}>
      <div className="panel-header"><div><h2>{allocationName||'Célula do roteiro'}</h2><p>Fotos, formulários e aprovações próprios desta célula no projeto.</p></div>
        <a className="button small secondary" href={`/projetos/${route.project.id}?tab=planejamento&allocation=${allocationId}`}>Planejar prazos e responsável</a></div>
      {(orderActive||active)&&<p className="form-note" role="status">Conclua ou cancele a alteração atual antes de abrir outra configuração ou mudar a sequência.</p>}
      <div className={s.tabs} aria-label="Configurações da célula no roteiro">{tabs.map(item=><button key={item.id} type="button" className="button small secondary" aria-pressed={tab===item.id} disabled={orderActive||active!==null&&active!==item.id} onClick={()=>setTab(item.id)}>{item.label}</button>)}</div>
      {tab==='photos'&&(photosCurrent&&photos?<OperationalPhotoEditor key={photos.photos_version} snapshot={photos} canManage={canManage} destination={target('photos')} disabled={orderActive||active!==null&&active!=='photos'} onInteractionChange={photoInteraction}/>:<p className="notice" role="status">Não foi possível conferir as fotos desta alocação. Recarregue o roteiro.</p>)}
      {tab==='forms'&&(formsCurrent&&forms?<ProjectRouteFormsEditor key={forms.context_version} snapshot={forms} canManage={canManage} destination={target('forms')} disabled={orderActive||active!==null&&active!=='forms'} onInteractionChange={formInteraction}/>:<p className="notice" role="status">Não foi possível conferir os formulários desta alocação. Recarregue o roteiro.</p>)}
      {tab==='approvals'&&(rulesCurrent&&rules?<OperationalStageRuleEditor key={rules.rules_version} snapshot={rules} canManage={canManage} destination={target('approvals')} disabled={orderActive||active!==null&&active!=='approvals'} onInteractionChange={ruleInteraction}/>:<p className="notice" role="status">Não foi possível conferir as aprovações desta alocação. Recarregue o roteiro.</p>)}
      {formsCurrent&&forms&&<ProjectRouteCellRemoval snapshot={forms} canManage={canManage&&canReadPhotos&&canReadForms&&canReadApprovals} disabled={orderActive||active!==null&&active!=='remove'} onInteractionChange={removeInteraction}/>}
    </section>}
  </>;
}
