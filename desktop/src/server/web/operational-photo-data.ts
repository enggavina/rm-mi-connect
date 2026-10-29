import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { uuid } from './policy';
import type { CorporateCapability } from './sso-policy';

const timestamp = z.string().datetime({ offset: true });
const text = z.string().nullable();
const photoSchema = z.object({
  id: uuid, projeto_id: uuid, celula_id: uuid, celula_projeto_id: uuid.nullable(), cadastro_foto_id: uuid.nullable(),
  titulo: text, categoria_foto: text, tag: text, numero: z.number().nullable(), updated_at: timestamp,
  captured: z.boolean(), selected_for_report: z.boolean(), retired: z.boolean(),
  can_edit_tag: z.boolean(), can_retire: z.boolean(), can_restore: z.boolean(), action_reason: text,
});
const titleSchema = z.object({
  id: uuid, titulo: text, numero: z.number().nullable(), updated_at: timestamp,
  assigned: z.boolean(), retired_photo_id: uuid.nullable(),
});
const snapshotSchema = z.object({
  project: z.object({ id: uuid, numero: text, status_pcp: text, data_real_de_entrega: timestamp.nullable(), updated_at: timestamp, closed: z.boolean() }),
  allocation: z.object({ id: uuid, projeto_id: uuid, celula_id: uuid, celula_nome: text, status: text, updated_at: timestamp }),
  photos: z.array(photoSchema).max(2000), titles: z.array(titleSchema).max(1000),
  photos_version: z.string().regex(/^[0-9a-f]{64}$/), total: z.number().int().nonnegative(), complete: z.boolean(),
  titles_total: z.number().int().nonnegative(), titles_complete: z.boolean(),
});

export type OperationalPhotoSnapshot = z.infer<typeof snapshotSchema>;
export type OperationalPhoto = OperationalPhotoSnapshot['photos'][number];
export type OperationalPhotoTitle = OperationalPhotoSnapshot['titles'][number];

const readCapabilities: CorporateCapability[] = ['em.portal.read', 'em.projects.read', 'em.planning.read', 'em.photos.read'];
const unavailable = () => new Error('Não foi possível consultar as fotos previstas desta célula. Tente novamente.');

/** Same RLS client as the project; the DTO never transports photo URLs or files. */
export function createOperationalPhotoData(client: SupabaseClient, capabilities?: readonly CorporateCapability[]) {
  async function getOperationalPhotos(projectId: string, allocationId: string, includeTitles = false): Promise<OperationalPhotoSnapshot | null> {
    if (capabilities !== undefined && (!readCapabilities.every(capability => capabilities.includes(capability))
      || includeTitles && !capabilities.includes('em.planning.manage'))) throw new Error('Acesso não autorizado às fotos previstas desta célula.');
    if (!uuid.safeParse(projectId).success || !uuid.safeParse(allocationId).success) return null;
    const result = await client.rpc('rm_web_operational_photos_snapshot_v1', {
      p_project_id: projectId, p_allocation_id: allocationId, p_include_titles: includeTitles,
    });
    if (result.error) throw unavailable();
    if (result.data === null) return null;
    const parsed = snapshotSchema.safeParse(result.data);
    if (!parsed.success) throw unavailable();
    const snapshot = parsed.data;
    const closed = snapshot.project.data_real_de_entrega !== null
      || ['cancelado', 'finalizando_para_faturar'].includes(snapshot.project.status_pcp ?? '');
    const ended = closed || ['finalizado', 'n_a'].includes(snapshot.allocation.status ?? '');
    if (snapshot.project.id !== projectId || snapshot.project.closed !== closed
      || snapshot.allocation.id !== allocationId || snapshot.allocation.projeto_id !== projectId
      || new Set(snapshot.photos.map(photo => photo.id)).size !== snapshot.photos.length
      || new Set(snapshot.titles.map(title => title.id)).size !== snapshot.titles.length
      || snapshot.complete !== (snapshot.total <= 2000)
      || (snapshot.complete ? snapshot.photos.length !== snapshot.total : snapshot.photos.length !== 0)
      || snapshot.titles_complete !== (snapshot.titles_total <= 1000)
      || (includeTitles && (snapshot.titles_complete ? snapshot.titles.length !== snapshot.titles_total : snapshot.titles.length !== 0))
      || snapshot.photos.some(photo => photo.projeto_id !== projectId || photo.celula_id !== snapshot.allocation.celula_id
        || photo.celula_projeto_id !== null && photo.celula_projeto_id !== allocationId
        || (ended || photo.categoria_foto !== 'obrigat_ria') && (photo.can_edit_tag || photo.can_retire || photo.can_restore)
        || photo.retired && (photo.can_edit_tag || photo.can_retire)
        || !photo.retired && photo.can_restore
        || (photo.captured || photo.selected_for_report) && (photo.can_retire || photo.can_restore))
      || snapshot.titles.some(title => title.retired_photo_id !== null && (!title.assigned
        || snapshot.complete && !snapshot.photos.some(photo => photo.id === title.retired_photo_id && photo.retired)))) throw unavailable();
    // Titles are an operational choice for writers, not a second public catalog.
    // Explicitly redact them even if a stale RPC unexpectedly supplied choices.
    return { ...snapshot, titles: includeTitles ? snapshot.titles : [] };
  }
  return { getOperationalPhotos };
}

export async function getOperationalPhotos(projectId: string, allocationId: string) {
  const { requireWebUser } = await import('./auth');
  const access = await requireWebUser(readCapabilities);
  const includeTitles = ['administrador', 'padr_o'].includes(access.profile.perfil)
    && (!access.sso || access.sso.capabilities.includes('em.planning.manage'));
  return createOperationalPhotoData(access.client, access.sso?.capabilities).getOperationalPhotos(projectId, allocationId, includeTitles);
}
