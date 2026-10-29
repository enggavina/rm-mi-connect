import type { OperationalPhoto, OperationalPhotoSnapshot, OperationalPhotoTitle } from '@/server/web/operational-photo-data';
import type { ManageOperationalPhotosInput } from '@/server/web/operational-photo-policy';
import { freezeEngineeringRequest } from './engineering-model';

export type OperationalPhotoMode = { action: 'add' } | { action: 'tag' | 'retire' | 'restore'; photoId: string };
export type OperationalPhotoDraft = { action: 'add'; titleIds: string[] }
  | { action: 'tag'; photoId: string; tag: string }
  | { action: 'retire' | 'restore'; photoId: string };

export const operationalTitleKey = (value: string | null) => (value ?? '').trim().replace(/\s+/g, ' ').toLowerCase();

export function canManageOperationalPhotos(snapshot: OperationalPhotoSnapshot, permitted: boolean) {
  return permitted && snapshot.complete && !snapshot.project.closed
    && !['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '');
}

export function operationalPhotoPage(photos: readonly OperationalPhoto[], retired: boolean, requestedPage = 1, pageSize = 25) {
  const rows = photos.filter(photo => photo.retired === retired).sort((a, b) => (a.numero ?? Infinity) - (b.numero ?? Infinity) || a.id.localeCompare(b.id));
  const pages = Math.max(1, Math.ceil(rows.length / pageSize));
  const page = Math.max(1, Math.min(Number.isInteger(requestedPage) ? requestedPage : 1, pages));
  return { rows: rows.slice((page - 1) * pageSize, page * pageSize), page, pages, total: rows.length };
}

export function operationalTitleBlockReason(title: OperationalPhotoTitle, selectedIds: readonly string[], titles: readonly OperationalPhotoTitle[]): string | null {
  if (!operationalTitleKey(title.titulo)) return 'Título não informado no cadastro.';
  if (title.retired_photo_id) return 'Este título possui uma previsão retirada. Use a seção Retiradas para restaurá-la.';
  if (title.assigned) return 'Este título já está vinculado à célula.';
  const key = operationalTitleKey(title.titulo);
  if (selectedIds.some(id => id !== title.id && titles.some(other => other.id === id && operationalTitleKey(other.titulo) === key))) {
    return 'Outro cadastro com este título já foi selecionado.';
  }
  if (selectedIds.length >= 100 && !selectedIds.includes(title.id)) return 'Adicione até 100 títulos por envio.';
  return null;
}

/** A retry preserves both generated slot IDs and all exact snapshot revisions. */
export function operationalPhotoRequest(snapshot: OperationalPhotoSnapshot, draft: OperationalPhotoDraft, submissionId: string, newId: () => string): ManageOperationalPhotosInput {
  if (!canManageOperationalPhotos(snapshot, true)) throw new Error('Recarregue as fotos desta célula antes de editar.');
  const common = { submissionId, projeto_id: snapshot.project.id, celula_projeto_id: snapshot.allocation.id,
    expected_project_updated_at: snapshot.project.updated_at, expected_allocation_updated_at: snapshot.allocation.updated_at,
    expected_photos_version: snapshot.photos_version };
  if (draft.action === 'add') {
    if (!snapshot.titles_complete) throw new Error('A lista completa de títulos precisa estar disponível antes de adicionar fotos.');
    if (!draft.titleIds.length || draft.titleIds.length > 100 || new Set(draft.titleIds).size !== draft.titleIds.length) {
      throw new Error('Selecione entre 1 e 100 títulos diferentes.');
    }
    const keys = new Set<string>();
    const items = draft.titleIds.map(titleId => {
      const title = snapshot.titles.find(item => item.id === titleId);
      if (!title || operationalTitleBlockReason(title, [], snapshot.titles)) throw new Error('Um dos títulos não está disponível. Recarregue as fotos da célula.');
      const key = operationalTitleKey(title.titulo);
      if (keys.has(key)) throw new Error('Selecione apenas um cadastro para cada título.');
      keys.add(key);
      return { id: newId(), cadastro_foto_id: titleId };
    });
    return freezeEngineeringRequest({ ...common, action: 'add', items });
  }
  const photo = snapshot.photos.find(item => item.id === draft.photoId);
  const allowed = draft.action === 'tag' ? photo?.can_edit_tag : draft.action === 'retire' ? photo?.can_retire : photo?.can_restore;
  if (!photo || !allowed) throw new Error('Esta foto não permite a alteração solicitada. Recarregue os dados da célula.');
  const target = { ...common, foto_id: photo.id, expected_foto_updated_at: photo.updated_at };
  if (draft.action === 'tag') {
    if (draft.tag.length > 2000) throw new Error('Use até 2.000 caracteres na tag.');
    return freezeEngineeringRequest({ ...target, action: 'tag', tag: draft.tag === '' ? null : draft.tag });
  }
  return freezeEngineeringRequest({ ...target, action: draft.action });
}
