import type { OutboxRow, Row } from '../core/types';
import type { JourneyContext } from './journey';
import { RECEIVING_PHOTO_TITLES } from './receiving';

export function photoTitle(photo: Row): string {
  return photo.titulo || RECEIVING_PHOTO_TITLES.find(item => item.value === photo.tipo_recebimento)?.label || 'Foto do projeto';
}
export function galleryPhotos(context: JourneyContext, photos: Row[], queue: OutboxRow[]): Row[] {
  if (!context.ok) return [];
  const projectPhotos = photos.filter(photo => photo.projeto_id === context.project.id && !photo.lixeira);
  const registered = new Map(projectPhotos.filter(photo => !!photo.foto_url).map(photo => [photo.id, photo]));
  for (const operation of [...queue].sort((a, b) => a.created_at.localeCompare(b.created_at))) {
    if (operation.rpc_name !== 'rm_record_cell_photo_v1' || operation.status === 'completed') continue;
    let params: Record<string, unknown>; try { params = JSON.parse(operation.params_json); } catch { continue; }
    if (!params || params.p_projeto_id !== context.project.id || typeof params.p_celula_id !== 'string' || typeof params.p_foto_url !== 'string' || !params.p_foto_url) continue;
    const original = params.p_foto_id ? projectPhotos.find(photo => photo.id === params.p_foto_id && photo.celula_id === params.p_celula_id && (!params.p_celula_projeto_id || !photo.celula_projeto_id || photo.celula_projeto_id === params.p_celula_projeto_id)) : undefined;
    if ((params.p_foto_id && !original) || (!params.p_foto_id && params.p_categoria_foto !== 'complementar')) continue;
    const id = original?.id || operation.id;
    registered.set(id, { ...original, id, projeto_id: context.project.id, celula_id: params.p_celula_id, titulo: original?.titulo || params.p_titulo, foto_url: params.p_foto_url, legenda: params.p_legenda, categoria_foto: original?.categoria_foto || 'complementar', operation_id: operation.id, upload_status: operation.status, registered_by: operation.actor_id });
  }
  return [...registered.values()];
}
export function cellPhotoTitles(cell: Row, catalog: Row[]) {
  const normalize = (value: string) => value.trim().toLocaleLowerCase('pt-BR');
  return catalog.filter(row => !row.celula_nome?.trim() || normalize(cell.nome) === normalize(row.celula_nome)).sort((a, b) => (a.numero ?? 0) - (b.numero ?? 0));
}
