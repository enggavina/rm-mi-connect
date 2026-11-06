'use client';
import{useEffect,useRef,useState}from'react';
import{deleteProject,inspectProjectDeletion}from'@/server/web/project-delete-actions';
import type{ProjectDeleteSnapshot,DeleteProjectInput}from'@/server/web/project-delete-policy';
import{freezeEngineeringRequest}from'./engineering-model';
import{Icon}from'./icons';
import s from'./project-delete.module.css';
const labels:Record<keyof ProjectDeleteSnapshot['counts'],string>={equipment:'Equipamentos',cells:'Células do projeto',photos:'Fotos e previsões',form_records:'Registros de formulários',answers:'Respostas e rascunhos',approvals:'Configurações e decisões de aprovação',comments:'Comentários',notifications:'Notificações dos formulários',documents:'Documentos e anexos',commercial:'Propostas exclusivas',laboratory:'OS, fichas e ensaios exclusivos'};
export function ProjectDeleteButton({projectId}:{projectId:string}){
 const dialog=useRef<HTMLDialogElement>(null),reasonInput=useRef<HTMLTextAreaElement>(null),attempt=useRef<DeleteProjectInput|null>(null),inFlight=useRef(false);
 const[snapshot,setSnapshot]=useState<ProjectDeleteSnapshot|null>(null),[reason,setReason]=useState(''),[confirmed,setConfirmed]=useState(false),[loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[uncertain,setUncertain]=useState(false),[error,setError]=useState(''),[deleted,setDeleted]=useState<{pending:number}|null>(null);
 const locked=busy||uncertain;
 useEffect(()=>{if(!locked)return;const guard=(event:BeforeUnloadEvent)=>{event.preventDefault();event.returnValue='';};window.addEventListener('beforeunload',guard);return()=>window.removeEventListener('beforeunload',guard);},[locked]);
 async function load(){setLoading(true);setError('');try{const result=await inspectProjectDeletion(projectId);if(result.ok&&result.snapshot){setSnapshot(result.snapshot);setTimeout(()=>reasonInput.current?.focus(),0);}else setError(result.ok?'O projeto não está mais disponível.':result.error);}catch{setError('Não foi possível consultar as dependências. Tente novamente.');}finally{setLoading(false);}}
 function open(){setSnapshot(null);setReason('');setConfirmed(false);setError('');attempt.current=null;dialog.current?.showModal();void load();}
 function close(){if(locked)return;if(deleted){window.location.assign('/projetos');return;}dialog.current?.close();}
 async function submit(){
  if(inFlight.current||!snapshot?.can_delete)return;
  if(!attempt.current){if(!confirmed||!reason.trim()){setError('Confirme a exclusão e informe a justificativa.');return;}attempt.current=freezeEngineeringRequest({submissionId:crypto.randomUUID(),id:projectId,expected_updated_at:snapshot.project.updated_at,expected_context_version:snapshot.context_version,confirm_delete:true,justificativa:reason.trim()});}
  inFlight.current=true;setBusy(true);setError('');
  try{const result=await deleteProject(attempt.current);if(result.ok){setDeleted({pending:Number(result.data.record.cleanup_pending)||0});setUncertain(false);attempt.current=null;}else{setError(result.error);setUncertain(result.code==='UNAVAILABLE');if(result.code!=='UNAVAILABLE')attempt.current=null;}}
  catch{setUncertain(true);setError('A conexão foi interrompida. Tente confirmar o mesmo envio para consultar o resultado sem duplicar a exclusão.');}
  finally{inFlight.current=false;setBusy(false);}
 }
 const name=snapshot?.project.numero?`OS ${snapshot.project.numero}`:snapshot?.project.nome||'Projeto';
 return<><button type="button" className="button secondary" onClick={open}><Icon name="trash" size={15}/>Excluir projeto</button>
 <dialog ref={dialog} className={s.dialog} aria-labelledby="delete-project-title" onCancel={event=>{event.preventDefault();close();}}><div className={s.body}>
  <h2 id="delete-project-title">{deleted?'Projeto excluído':`Excluir ${name}`}</h2>
  {deleted?<><p role="status">O projeto e seus registros exclusivos foram excluídos.</p>{deleted.pending>0&&<p className="notice">A limpeza dos anexos privados está em processamento e continuará automaticamente.</p>}<a className="button" href="/projetos">Voltar aos projetos</a></>:<>
   {error&&<p className="notice error" role="alert">{error}</p>}{loading?<p role="status">Conferindo projeto e dependências…</p>:!snapshot?<button type="button" className="button secondary" onClick={()=>void load()}>Tentar consultar novamente</button>:<>
    <p>Esta exclusão é definitiva. Serão removidos os registros que pertencem exclusivamente a este projeto, incluindo respostas, fotos, documentos e histórico operacional.</p>
    <p className="form-note">Clientes, usuários e modelos globais são preservados. Arquivos de origem externa ou sem exclusividade comprovada não serão apagados dos seus provedores.</p>
    <p className="notice">Envios offline pendentes deste projeto serão recusados após a exclusão. Os dados salvos no dispositivo permanecem para conferência e reconciliação.</p>
    <dl className={s.counts}>{Object.entries(snapshot.counts).filter(([,value])=>value>0).map(([key,value])=><div key={key}><dt>{labels[key as keyof typeof labels]}</dt><dd>{value.toLocaleString('pt-BR')}</dd></div>)}</dl>
    {!snapshot.can_delete?<p className="notice" role="status">{snapshot.reason||'Existem vínculos compartilhados. Revise as dependências antes de excluir.'}</p>:<fieldset disabled={locked} className={s.fields}><label htmlFor="delete-project-reason">Justificativa obrigatória<textarea ref={reasonInput} id="delete-project-reason" rows={3} maxLength={2000} value={reason} onChange={event=>setReason(event.target.value)}/></label><label className="check-label"><input type="checkbox" checked={confirmed} onChange={event=>setConfirmed(event.target.checked)}/>Confirmo a exclusão definitiva de {name} e dos registros exclusivos apresentados.</label></fieldset>}
   </>}
   {uncertain&&<p className="notice">O envio ainda não foi confirmado. Os campos permanecem protegidos; confirme o mesmo protocolo antes de iniciar outra alteração.</p>}
   <div className="form-actions"><button type="button" className="button secondary" disabled={locked} onClick={close}>Cancelar</button>{snapshot?.can_delete&&<button type="button" className={`button ${s.danger}`} disabled={busy||(!uncertain&&(!confirmed||!reason.trim()))} onClick={()=>void submit()}>{busy?'Excluindo…':uncertain?'Tentar confirmar envio':'Excluir definitivamente'}</button>}</div>
  </>}
 </div></dialog></>;
}
