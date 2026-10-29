'use client';

import { useRef } from 'react';
import { setProjectPhotoSelection } from '@/server/web/project-photo-actions';
import type { ProjectPhotoSelectionInput } from '@/server/web/project-photo-policy';
import { Photo } from './photo';
import { Status } from './ui';
import { useEngineeringSave } from './engineering-save';

export type ProjectGalleryPhoto = {
  id: string; titulo: string | null; foto_url: string; categoria_foto: string | null;
  cellName: string; legenda: string | null; selecao_relatorio: boolean; updated_at: string;
};

export function ProjectPhotoGallery({ projectId, photos, canSelect, destination }: {
  projectId: string; photos: ProjectGalleryPhoto[]; canSelect: boolean; destination: string;
}) {
  const state = useEngineeringSave<ProjectPhotoSelectionInput>(setProjectPhotoSelection, destination);
  const attemptPhoto = useRef<string | null>(null);
  function select(photo: ProjectGalleryPhoto, selected: boolean) {
    if (!canSelect || state.locked) return;
    attemptPhoto.current = photo.id;
    void state.send({ submissionId: crypto.randomUUID(), projeto_id: projectId, foto_id: photo.id,
      expected_updated_at: photo.updated_at, selected });
  }
  return <>
    <p className="form-note">A seleção é salva no projeto para o relatório fotográfico. A numeração e os arquivos das fotos são preservados.</p>
    {state.error && <p className="notice error" role="alert">{state.error}</p>}
    {state.uncertain && <div className="notice">A confirmação está pendente. A seleção permanece bloqueada até conferir o mesmo envio. <button className="button small secondary" type="button" onClick={state.retry}>Tentar confirmar envio</button></div>}
    {state.stale && <div className="notice">A foto foi alterada desde que esta página foi aberta. <a className="text-link" href={destination}>Recarregar fotos</a> para consultar a seleção atual.</div>}
    {state.unauthorized && <div className="notice">Confirme seu acesso antes de continuar. <a className="text-link" href="/login">Voltar ao acesso</a></div>}
    {state.busy && <p className="notice" role="status">Salvando seleção da foto…</p>}
    <div className="photo-grid">{photos.map(photo => <article className="photo-card" key={photo.id} data-project-photo={photo.id} aria-busy={state.busy && attemptPhoto.current === photo.id}>
      <Photo url={photo.foto_url} title={photo.titulo || 'Foto do equipamento'} />
      <div className="photo-caption"><Status value={photo.categoria_foto || ''} /><h3>{photo.titulo || 'Foto do equipamento'}</h3>
        <p>{photo.cellName}</p>{photo.legenda && <p style={{ marginTop: 8 }}>{photo.legenda}</p>}
        {canSelect ? <label className="photo-selection"><input type="checkbox" checked={photo.selecao_relatorio} aria-label={`Incluir ${photo.titulo || 'foto do equipamento'} no relatório`}
          disabled={state.locked} onChange={event => select(photo, event.currentTarget.checked)} />Incluir no relatório</label>
          : <p className="photo-selection">{photo.selecao_relatorio ? 'Selecionada para relatório' : 'Não selecionada para relatório'}</p>}
      </div>
    </article>)}</div>
  </>;
}
