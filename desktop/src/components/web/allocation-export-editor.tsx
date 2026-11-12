'use client';
import {useEffect,useRef,useState,type FormEvent} from 'react';
import {Icon} from './icons';
import {allocationExportRequest,fetchAllocationExport,type AllocationExportCell,type AllocationExportField} from './allocation-export-model';
import s from './allocation-export.module.css';

const groups=[{id:'project',label:'Projeto'},{id:'equipment',label:'Equipamento'},{id:'allocation',label:'Célula e alocação'}] as const;
export function AllocationExportEditor({cells,fields,defaultFields,initialCellId}:{cells:readonly AllocationExportCell[];fields:readonly AllocationExportField[];defaultFields:readonly string[];initialCellId?:string}){
  const dialog=useRef<HTMLDialogElement>(null),searchInput=useRef<HTMLInputElement>(null),controller=useRef<AbortController|null>(null);
  const [selectedCells,setSelectedCells]=useState<string[]>(()=>initialCellId&&cells.some(cell=>cell.id===initialCellId)?[initialCellId]:[]);
  const [selectedFields,setSelectedFields]=useState<string[]>(()=>fields.filter(field=>defaultFields.includes(field.key)).map(field=>field.key));
  const [search,setSearch]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState('');
  useEffect(()=>()=>controller.current?.abort(),[]);
  const visibleCells=cells.filter(cell=>(cell.nome??'Célula sem nome').toLocaleLowerCase('pt-BR').includes(search.trim().toLocaleLowerCase('pt-BR')));
  function open(){setError('');setSuccess('');dialog.current?.showModal();setTimeout(()=>searchInput.current?.focus(),0);}
  function close(){controller.current?.abort();controller.current=null;setBusy(false);dialog.current?.close();}
  function toggle(value:string,current:readonly string[],update:(values:string[])=>void){update(current.includes(value)?current.filter(item=>item!==value):[...current,value]);setError('');setSuccess('');}
  async function submit(event:FormEvent<HTMLFormElement>){
    event.preventDefault();if(controller.current)return;setError('');setSuccess('');
    let input;try{input=allocationExportRequest(selectedCells,selectedFields,cells,fields);}catch(cause){setError(cause instanceof Error?cause.message:'Confira a seleção antes de exportar.');return;}
    const current=new AbortController();controller.current=current;setBusy(true);
    try{
      const file=await fetchAllocationExport(input,current.signal);
      if(current.signal.aborted)return;
      const url=URL.createObjectURL(file.blob),link=document.createElement('a');link.href=url;link.download=file.filename;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);
      setSuccess('Excel gerado. O download foi iniciado.');
    }catch(cause){if(!current.signal.aborted)setError(cause instanceof Error?cause.message:'Não foi possível gerar o Excel. Tente novamente.');}
    finally{if(controller.current===current){controller.current=null;setBusy(false);}}
  }
  return <><button type="button" className="button secondary" onClick={open} disabled={cells.length===0||fields.length===0}><Icon name="download" size={16}/>Exportar para Excel</button>
    <dialog ref={dialog} className={s.dialog} aria-labelledby="allocation-export-title" aria-describedby="allocation-export-description" onCancel={event=>{event.preventDefault();close();}}><div className={s.body}>
      <div className={s.heading}><div><h2 id="allocation-export-title">Exportar alocações para Excel</h2><p id="allocation-export-description">Escolha as células e as informações. O arquivo terá uma aba por célula, com uma linha para cada alocação.</p></div><button type="button" className={s.close} aria-label="Fechar exportação" onClick={close}><Icon name="close" size={20}/></button></div>
      <form className={s.form} onSubmit={submit}>
        <fieldset className={s.fieldset} disabled={busy}><legend>Células</legend><div className={s.tools}><input ref={searchInput} className={s.search} type="search" aria-label="Buscar células para exportar" placeholder="Buscar célula…" onKeyDown={event=>{if(event.key==="Enter")event.preventDefault();}} value={search} onChange={event=>setSearch(event.target.value)} maxLength={150}/><button type="button" className="button small secondary" onClick={()=>{setSelectedCells([...new Set([...selectedCells,...visibleCells.map(cell=>cell.id)])]);setError('');setSuccess('');}} disabled={visibleCells.length===0}>Selecionar exibidas</button><button type="button" className="button small secondary" onClick={()=>{setSelectedCells([]);setError('');setSuccess('');}} disabled={selectedCells.length===0}>Limpar células</button></div>
          <p className={s.count} aria-live="polite">{selectedCells.length} {selectedCells.length===1?'célula selecionada':'células selecionadas'}</p><div className={s.cells}>{visibleCells.length?visibleCells.map(cell=><label className={s.choice} key={cell.id}><input type="checkbox" checked={selectedCells.includes(cell.id)} onChange={()=>toggle(cell.id,selectedCells,setSelectedCells)}/><span>{cell.nome||'Célula sem nome'}</span></label>):<p className={s.empty}>Nenhuma célula encontrada.</p>}</div>
        </fieldset>
        <fieldset className={s.fieldset} disabled={busy}><legend>Informações para exportar</legend><div className={s.tools}><button type="button" className="button small secondary" onClick={()=>{setSelectedFields(fields.map(field=>field.key));setError('');setSuccess('');}}>Selecionar todas as informações</button><button type="button" className="button small secondary" onClick={()=>{setSelectedFields([]);setError('');setSuccess('');}} disabled={selectedFields.length===0}>Limpar informações</button></div><div>{groups.map(group=>{const values=fields.filter(field=>field.group===group.id);return values.length>0&&<section key={group.id} className={s.group} aria-label={`Informações de ${group.label}`}><h3 className={s.groupTitle}>{group.label}</h3><div className={s.fields}>{values.map(field=><label key={field.key} className={s.choice}><input type="checkbox" checked={selectedFields.includes(field.key)} onChange={()=>toggle(field.key,selectedFields,setSelectedFields)}/><span>{field.label}</span></label>)}</div></section>;})}</div></fieldset>
        <p className={s.note}>A exportação inclui as alocações atuais das células selecionadas, inclusive as ocultas no mobile. Os filtros e a página da lista não limitam o arquivo. Um projeto alocado em duas células aparece nas duas abas.</p>
        {error&&<p className={`notice error ${s.feedback}`} role="alert">{error}</p>}{success&&<p className={`notice ${s.feedback}`} role="status">{success}</p>}
        <div className={s.footer}><button type="button" className="button secondary" onClick={close}>{busy?'Cancelar exportação':'Fechar'}</button><button type="submit" className="button" disabled={busy} aria-busy={busy}><Icon name="download" size={16}/>{busy?'Gerando Excel…':'Gerar Excel'}</button></div>
      </form>
    </div></dialog></>;
}
