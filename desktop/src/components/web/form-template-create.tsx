'use client';
import { useState } from 'react';
import { useTemplateSave, TemplateSaveNotice } from './form-template-save';
import { Icon } from './icons';
import s from './form-template.module.css';

export function FormTemplateCreate({ source, initialKind = 'copy' }: { source?: { id: string; titulo: string; version?: number | null }; initialKind?: 'copy' | 'version' }) {
  const [id] = useState(() => crypto.randomUUID()), [kind, setKind] = useState<'new' | 'copy' | 'version'>(source ? initialKind : 'new');
  const save = useTemplateSave();
  return <><TemplateSaveNotice state={save} reload={source ? `/modelos-formularios/novo?base=${source.id}&modo=${kind}` : '/modelos-formularios/novo'} /><form onSubmit={event => { event.preventDefault(); void save.send({ action: 'create', payload: { submissionId: crypto.randomUUID(), id, source_form_id: source?.id ?? null, kind } }); }}><fieldset className={s.fieldSet} disabled={save.locked}>
    {source ? <><div className="notice">Base selecionada: <strong>{source.titulo}</strong>{source.version != null ? ` · Versão ${source.version}` : ' · Modelo legado'}. A base permanecerá intacta.</div><div className="field"><label htmlFor="template-copy-mode">Como usar esta base</label><select id="template-copy-mode" value={kind} onChange={event => setKind(event.target.value as 'copy' | 'version')}><option value="copy">Copiar como novo modelo independente</option><option value="version">Criar nova versão da mesma família</option></select></div><p className={s.notes} style={{ marginTop: 16 }}>Uma nova versão mantém a família da base. A numeração da versão será definida ao publicar; a base escolhida pode ser anterior à versão mais recente.</p></> : <><p className={s.subtitle}>Crie um rascunho vazio e adicione os subtítulos, questões e opções. Você poderá salvar etapas incompletas antes de publicar.</p><p className={s.notes}>Para aproveitar um modelo existente, volte à lista e escolha “Copiar base” ou “Nova versão”.</p></>}
    <p className={s.notes}>Nenhum formulário será disponibilizado à operação até a publicação. Depois de publicar, a adoção nos roteiros é feita na Engenharia.</p>
  </fieldset><div className="form-actions"><button type="button" className="button secondary" disabled={save.busy || save.uncertain} onClick={() => window.location.assign('/modelos-formularios')}>Cancelar</button><button className="button" disabled={save.locked}><Icon name="plus" size={15} />{save.busy ? 'Criando…' : 'Criar rascunho'}</button></div></form></>;
}
