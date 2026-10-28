import type { Operator, OutboxRow, Row } from '../core/types';

export function canAccessCell(operator: Operator | null, cellId: string | undefined): boolean {
  return !!operator && !!cellId && (operator.perfil === 'administrador' || operator.celulas_vinculadas.some(link => link.celula_id === cellId));
}

export function allowedCells(operator: Operator | null, cells: Row[]): Row[] {
  return cells.filter(cell => canAccessCell(operator, cell.id)).sort((a, b) => (a.indice ?? a.ordem ?? 0) - (b.indice ?? b.ordem ?? 0));
}

export function isActiveProject(project: Row): boolean {
  return !project.data_real_de_entrega && !['cancelado', 'finalizando_para_faturar'].includes(project.status_pcp);
}

export function cellAllocations(operator: Operator | null, cellId: string | undefined, projects: Row[], allocations: Row[]): Row[] {
  if (!canAccessCell(operator, cellId)) return [];
  const active = new Set(projects.filter(isActiveProject).map(project => project.id));
  return allocations.filter(a => a.celula_id === cellId && a.visibilidade === true && active.has(a.projeto_id))
    .sort((a, b) => (a.posicao ?? a.indice ?? 0) - (b.posicao ?? b.indice ?? 0));
}

export type JourneyContext = { ok: false; reason: string; loading?: boolean } | { ok: true; cell: Row; project: Row; allocation: Row; canEdit: boolean };
export function resolveJourneyContext(operator: Operator | null, cellId: string | undefined, projectId: string | undefined, cells: Row[], projects: Row[], allocations: Row[]): JourneyContext {
  if (!cellId || !projectId) return { ok: false, reason: 'Escolha uma célula e um projeto para continuar.' };
  if (!canAccessCell(operator, cellId)) return { ok: false, reason: 'Esta célula não está vinculada ao operador identificado.' };
  const cell = cells.find(c => c.id === cellId);
  const project = projects.find(p => p.id === projectId && isActiveProject(p));
  const allocation = allocations.find(a => a.celula_id === cellId && a.projeto_id === projectId && a.visibilidade === true);
  if (!cell || !project || !allocation) return { ok: false, reason: 'Este projeto não está disponível nesta célula. Sincronize o catálogo ou escolha outro projeto.' };
  return { ok: true, cell, project, allocation, canEdit: allocation.bloqueada !== 'sim' };
}

// The project-cell allocation is the complete source of form membership.
export function assignedForms(allocation: Row, forms: Row[]): Row[] {
  const byId = new Map(forms.map(form => [form.id, form]));
  return [...new Set<string>(Array.isArray(allocation.forms_ids) ? allocation.forms_ids : [])]
    .map(id => byId.get(id)).filter((form): form is Row => !!form);
}

export function canOpenForm(context: JourneyContext, formId: string | undefined): boolean {
  return context.ok && !!formId && Array.isArray(context.allocation.forms_ids) && context.allocation.forms_ids.includes(formId);
}

export function canReviseRecord(context: JourneyContext, record: Row | undefined): boolean {
  return context.ok && !!record && record.status === 'direcionado' && record.projeto_id === context.project.id
    && record.celula_id === context.cell.id && canOpenForm(context, record.form_id);
}

export function projectPhotos(context: JourneyContext, photos: Row[]): { required: Row[]; complementary: Row[]; others: Row[] } {
  if (!context.ok) return { required: [], complementary: [], others: [] };
  const rows = photos.filter(p => p.projeto_id === context.project.id && !p.lixeira)
    .sort((a, b) => (a.numero ?? 0) - (b.numero ?? 0));
  const current = rows.filter(p => p.celula_id === context.cell.id && (!p.celula_projeto_id || p.celula_projeto_id === context.allocation.id));
  const currentIds = new Set(current.map(p => p.id));
  return { required: current.filter(p => p.categoria_foto === 'obrigat_ria'), complementary: current.filter(p => p.categoria_foto !== 'obrigat_ria'), others: rows.filter(p => !currentIds.has(p.id)) };
}

export function canEditPhoto(context: JourneyContext, photo: Row): boolean {
  return context.ok && context.canEdit && !photo.lixeira && photo.projeto_id === context.project.id && photo.celula_id === context.cell.id
    && (!photo.celula_projeto_id || photo.celula_projeto_id === context.allocation.id);
}

export interface PendingPhoto {
  operationId: string; operatorId: string; uri: string; title: string; caption: string;
  status: string; error?: string;
}
type PhotoOperation = Pick<OutboxRow, 'id' | 'rpc_name' | 'params_json' | 'actor_id' | 'status' | 'created_at' | 'last_error'>;

/** Read-only presentation of queued work: never copies another actor's photo into a draft. */
export function pendingProjectPhotos(context: JourneyContext, photos: Row[], queue: readonly PhotoOperation[]): { slots: Record<string, PendingPhoto>; complementary: PendingPhoto[] } {
  const slots: Record<string, PendingPhoto> = {}; const complementary: PendingPhoto[] = [];
  if (!context.ok) return { slots, complementary };
  const gallery = projectPhotos(context, photos);
  const currentIds = new Set([...gallery.required, ...gallery.complementary].map(photo => photo.id));
  for (const operation of [...queue].sort((a, b) => a.created_at.localeCompare(b.created_at))) {
    if (operation.rpc_name !== 'rm_record_cell_photo_v1' || operation.status === 'completed') continue;
    let params: Record<string, unknown>;
    try { params = JSON.parse(operation.params_json); } catch { continue; }
    if (!params || params.p_projeto_id !== context.project.id || params.p_celula_id !== context.cell.id
      || (params.p_celula_projeto_id && params.p_celula_projeto_id !== context.allocation.id)
      || typeof params.p_foto_url !== 'string' || !params.p_foto_url) continue;
    const photo: PendingPhoto = { operationId: operation.id, operatorId: operation.actor_id, uri: params.p_foto_url,
      title: typeof params.p_titulo === 'string' ? params.p_titulo : '', caption: typeof params.p_legenda === 'string' ? params.p_legenda : '', status: operation.status, error: operation.last_error };
    if (typeof params.p_foto_id === 'string' && currentIds.has(params.p_foto_id)) slots[params.p_foto_id] = photo;
    else if (!params.p_foto_id && params.p_categoria_foto === 'complementar') complementary.push(photo);
  }
  return { slots, complementary };
}

export function requiredPhotoProgress(required: Row[], slots: Record<string, PendingPhoto>) {
  const pending = required.filter(photo => !!slots[photo.id]).length;
  const confirmed = required.filter(photo => !!photo.foto_url && !slots[photo.id]).length;
  const attention = required.filter(photo => slots[photo.id]?.status === 'failed').length;
  return { registered: confirmed + pending, confirmed, pending, attention };
}
