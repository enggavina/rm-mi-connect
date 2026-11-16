'use client';
import { useEffect, useMemo, useRef, useState } from 'react';
import { manageProjectDocuments } from '@/server/web/project-document-folder-actions';
import type { ManageProjectDocumentsInput } from '@/server/web/project-document-folder-policy';
import type { ProjectDocumentPage } from '@/server/web/project-dossier-search-policy';
import { EngineeringSaveNotice, useEngineeringSave } from './engineering-save';
import { freezeEngineeringRequest } from './engineering-model';
import { documentDirectoryHref, documentFolderDescendants, documentFolderPaths } from './project-document-folder-model';
import { Icon } from './icons';
import { useDossierExitGuard } from './project-dossier-editors';
import s from './project-document-folders.module.css';

type Action = ManageProjectDocumentsInput['action'];
export function ProjectDocumentFolderExplorer({ projectId, projectVersion, navigation, documents, canEdit }: {
  projectId: string; projectVersion: string; navigation: NonNullable<ProjectDocumentPage['navigation']>;
  documents: ProjectDocumentPage['items']; canEdit: boolean;
}) {
  const [action, setAction] = useState<Action | null>(null), [name, setName] = useState(''), [destination, setDestination] = useState(''), [documentId, setDocumentId] = useState(''), [confirmed, setConfirmed] = useState(false), [saved, setSaved] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null), leaving = useRef(false), folderId = navigation.current_folder_id;
  const paths = useMemo(() => documentFolderPaths(navigation.folders), [navigation.folders]);
  const current = navigation.folders.find(folder => folder.id === folderId);
  const children = navigation.folders.filter(folder => folder.parent_id === folderId);
  const excluded = useMemo(() => action === 'move_folder' && folderId ? documentFolderDescendants(navigation.folders, folderId) : new Set<string>(), [action, folderId, navigation.folders]);
  const reload = documentDirectoryHref(projectId, action === 'delete_folder' || action === 'move_folder' ? current?.parent_id ?? null : folderId);
  const save = useEngineeringSave<ManageProjectDocumentsInput>(async input => { const result = await manageProjectDocuments(input); if (result.ok) { leaving.current = true; setSaved(true); } return result; }, reload);
  useDossierExitGuard(!!action && !!(name || destination || documentId || confirmed), save.busy || save.uncertain, save.stale, leaving);
  const locked = save.locked || saved;
  useEffect(() => { if (action) heading.current?.focus(); }, [action]);
  function open(next: Action) { setAction(next); setName(next === 'rename_folder' ? current?.nome ?? '' : ''); setDestination(''); setDocumentId(''); setConfirmed(false); save.setError(''); }
  function submit() {
    if (save.uncertain) { save.retry(); return; } if (!action || locked) return;
    const base = { submissionId: crypto.randomUUID(), projeto_id: projectId, expected_project_updated_at: projectVersion };
    let input: ManageProjectDocumentsInput;
    if (action === 'create_folder') input = { ...base, action, parent_id: folderId, nome: name.trim() };
    else if (action === 'move_document') {
      const item = documents.find(item => `${item.source}:${item.id}` === documentId);
      if (!item || !confirmed) { save.setError('Escolha o documento e confirme a alteração.'); return; }
      input = { ...base, action, source: item.source, document_id: item.id, folder_id: destination || null, expected_folder_id: folderId, confirm_change: true };
    } else {
      if (!current) return;
      const selected = { ...base, folder_id: current.id, expected_folder_updated_at: current.updated_at };
      if (action === 'rename_folder') input = { ...selected, action, nome: name.trim() };
      else { if (!confirmed) { save.setError('Confirme a alteração.'); return; } input = action === 'move_folder' ? { ...selected, action, parent_id: destination || null, confirm_change: true } : { ...selected, action, confirm_change: true }; }
    }
    void save.send(freezeEngineeringRequest(input));
  }
  const titles: Record<Action, string> = { create_folder: 'Nova pasta', rename_folder: 'Renomear pasta', move_folder: 'Mover pasta', delete_folder: 'Excluir pasta vazia', move_document: 'Mover documento' };
  return <div className={s.explorer} data-document-folder-explorer>
    <nav className={s.breadcrumbs} aria-label="Diretório atual"><a href={documentDirectoryHref(projectId, null)} aria-current={!folderId ? 'page' : undefined}><Icon name="folder" size={16} />Documentos</a>{navigation.breadcrumbs.map(folder => <span key={folder.id}><Icon name="chevron" size={12} /><a href={documentDirectoryHref(projectId, folder.id)} aria-current={folder.id === folderId ? 'page' : undefined}>{folder.nome}</a></span>)}</nav>
    {canEdit && <div className={s.tools}><button className="button small secondary" type="button" disabled={locked} onClick={() => open('create_folder')}><Icon name="plus" size={14} />Nova pasta</button>{current && <><button className="button small secondary" type="button" disabled={locked} onClick={() => open('rename_folder')}>Renomear pasta</button><button className="button small secondary" type="button" disabled={locked} onClick={() => open('move_folder')}>Mover pasta</button><button className="button small secondary" type="button" disabled={locked} onClick={() => open('delete_folder')}>Excluir pasta vazia</button></>}{documents.length > 0 && <button className="button small secondary" type="button" disabled={locked} onClick={() => open('move_document')}>Mover documento</button>}</div>}
    {canEdit && action && <form className={s.editor} onSubmit={event => { event.preventDefault(); submit(); }}><h3 ref={heading} tabIndex={-1}>{titles[action]}{action !== 'create_folder' && action !== 'move_document' ? `: ${current?.nome}` : ''}</h3>
      <EngineeringSaveNotice state={save} reload={reload} />{saved && <p role="status" className="notice success">Alteração confirmada. Atualizando os documentos…</p>}
      {action === 'delete_folder' && <p>A pasta só será excluída se estiver vazia. Documentos, subpastas e envios pendentes impedem a exclusão.</p>}
      <fieldset disabled={locked} className={s.fields}>
        {(action === 'create_folder' || action === 'rename_folder') && <div className="field"><label htmlFor="document-folder-name">Nome da pasta *</label><input id="document-folder-name" value={name} onChange={event => setName(event.target.value)} required maxLength={200} /></div>}
        {action === 'move_document' && <div className="field"><label htmlFor="directory-document">Documento desta página *</label><select id="directory-document" value={documentId} onChange={event => { setDocumentId(event.target.value); setConfirmed(false); }} required><option value="">Selecione o documento</option>{documents.map(item => <option key={`${item.source}:${item.id}`} value={`${item.source}:${item.id}`}>{item.nome || 'Documento do projeto'} · {item.source === 'docs' ? 'Anexo' : 'Documento'}</option>)}</select></div>}
        {(action === 'move_folder' || action === 'move_document') && <div className="field"><label htmlFor="directory-destination">Pasta de destino</label><select id="directory-destination" value={destination} onChange={event => { setDestination(event.target.value); setConfirmed(false); }}><option value="">Documentos (raiz do projeto)</option>{navigation.folders.filter(folder => !excluded.has(folder.id)).map(folder => <option value={folder.id} key={folder.id}>{paths.get(folder.id)}</option>)}</select></div>}
        {['delete_folder', 'move_folder', 'move_document'].includes(action) && <label className={s.confirm}><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} required />Confirmo {action === 'delete_folder' ? `a exclusão da pasta “${current?.nome}”` : 'a alteração do diretório'}.</label>}
      </fieldset><div className={s.tools}><button className="button small secondary" type="button" disabled={locked} onClick={() => setAction(null)}>Cancelar</button><button className="button small" type="submit" disabled={save.busy || save.stale || save.unauthorized || saved}>{save.busy ? 'Salvando…' : save.uncertain ? 'Tentar confirmar alteração' : titles[action]}</button></div>
    </form>}
    {children.length > 0 && <div className={s.folders} aria-label="Subpastas">{children.map(folder => <a className={s.folder} key={folder.id} href={documentDirectoryHref(projectId, folder.id)}><Icon name="folder" size={24} /><span>{folder.nome}</span><Icon name="chevron" size={14} /></a>)}</div>}
    <p className={s.caption}>Arquivos neste diretório{children.length ? ` · ${children.length} ${children.length === 1 ? 'subpasta' : 'subpastas'}` : ''}</p>
  </div>;
}
