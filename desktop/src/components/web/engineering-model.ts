import type { WebRow } from '@/server/web/data';

export interface EngineeringPhoto { id: string; cadastro_foto_id: string | null; numero: number | null; descricao: string | null }
export interface EngineeringStage { id: string; celula_destino_id: string | null; status_cel_proj: string | null; bloquear_avanco_sem_aprov: boolean; aprovadores_ids: string[]; aprovadores_retorno_ids: string[] }
export interface EngineeringSnapshot { matrix: WebRow; form_ids: string[]; photos: WebRow[]; stages: WebRow[] }
export interface EngineeringChoices { types: WebRow[]; cells: WebRow[]; forms: WebRow[]; users: WebRow[]; cellUserLinks: WebRow[]; photoTitles: WebRow[]; statuses: WebRow[] }
export interface EngineeringPayload { submissionId: string; id: string; celula_id: string; tipo_equipamento_id: string; expected_updated_at: string | null; changes: { ativo?: boolean; visibilidade?: boolean; numero_fotos?: number; form_ids?: string[]; photos?: EngineeringPhoto[]; stages?: EngineeringStage[] } }
export interface PhotoTitlePayload { submissionId: string; id: string; expected_updated_at: string | null; changes: { titulo: string; numero?: number | null; celula_id?: string | null } }

export function canManageEngineering(access: { profile: { perfil: string }; sso?: { capabilities: readonly string[] } }) {
  return access.profile.perfil === 'administrador' && (!access.sso || access.sso.capabilities.includes('em.engineering.manage'));
}
export function photoDraft(row: WebRow): EngineeringPhoto {
  return { id: row.id, cadastro_foto_id: row.cadastro_foto_id ?? null, numero: row.numero ?? null, descricao: row.descricao ?? null };
}
export function stageDraft(row: WebRow): EngineeringStage {
  return { id: row.id, celula_destino_id: row.celula_destino_id ?? null, status_cel_proj: row.status_cel_proj ?? null,
    bloquear_avanco_sem_aprov: row.bloquear_avanco_sem_aprov, aprovadores_ids: [...(row.aprovadores_ids ?? [])], aprovadores_retorno_ids: [...(row.aprovadores_retorno_ids ?? [])] };
}
/** IDs and order are significant to the server's legacy preservation check. */
export const sameEngineeringValue = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
export function freezeEngineeringRequest<T>(value: T): T {
  const freeze = (item: any): any => { if (item && typeof item === 'object') { Object.values(item).forEach(freeze); Object.freeze(item); } return item; };
  return freeze(structuredClone(value)) as T;
}
export function nextPhotoNumber(photos: readonly EngineeringPhoto[]): number | null {
  const max = Math.max(0, ...photos.map(photo => photo.numero ?? 0)); return max < 1000 ? max + 1 : null;
}
const cellNameKey = (name: unknown) => String(name ?? '').trim().replace(/\s+/g, ' ').toLocaleLowerCase();
export function engineeringRouteRows(rows: WebRow[], cells: WebRow[]) {
  const byId = new Map(cells.map(cell => [cell.id, cell]));
  return [...rows].sort((a, b) => {
    const left = byId.get(a.celula_id), right = byId.get(b.celula_id);
    return (left?.ordem ?? Infinity) - (right?.ordem ?? Infinity) || (left?.indice ?? Infinity) - (right?.indice ?? Infinity) || a.id.localeCompare(b.id);
  });
}
export function titlesForCell(choices: EngineeringChoices, cellId: string) {
  const cell = choices.cells.find(row => row.id === cellId);
  return cell ? choices.photoTitles.filter(row => !cellNameKey(row.celula_nome) || cellNameKey(row.celula_nome) === cellNameKey(cell.nome)) : [];
}
export function approversForCell(choices: EngineeringChoices, cellId: string | null) {
  const linked = new Set(choices.cellUserLinks.filter(row => row.celula_id === cellId).map(row => row.identidade_id));
  return choices.users.filter(user => user.status === 'ativo' && !user.missing && linked.has(user.id));
}
export function legacyPhoto(row: EngineeringPhoto, choices: EngineeringChoices, cellId: string) {
  return !row.cadastro_foto_id || !titlesForCell(choices, cellId).some(title => title.id === row.cadastro_foto_id)
    || row.numero == null || !Number.isInteger(row.numero) || row.numero < 1 || row.numero > 1000;
}
export function legacyStage(row: EngineeringStage, choices: EngineeringChoices, cellId: string) {
  const origin = new Set(approversForCell(choices, cellId).map(user => user.id));
  const destination = new Set(approversForCell(choices, row.celula_destino_id).map(user => user.id));
  return !row.celula_destino_id || row.celula_destino_id === cellId || !choices.cells.some(cell => cell.id === row.celula_destino_id)
    || !row.status_cel_proj || row.status_cel_proj === 'retornado' || !choices.statuses.some(status => status.option_key === row.status_cel_proj)
    || !row.aprovadores_ids.length || !row.aprovadores_retorno_ids.length || row.aprovadores_ids.length > 100 || row.aprovadores_retorno_ids.length > 100
    || new Set(row.aprovadores_ids).size !== row.aprovadores_ids.length || new Set(row.aprovadores_retorno_ids).size !== row.aprovadores_retorno_ids.length
    || row.aprovadores_ids.some(id => !origin.has(id)) || row.aprovadores_retorno_ids.some(id => !destination.has(id));
}
export function engineeringChanges(snapshot: EngineeringSnapshot | undefined, values: { ativo: boolean; visibilidade: boolean; numero_fotos: string; form_ids: string[]; photos: EngineeringPhoto[]; stages: EngineeringStage[] }): EngineeringPayload['changes'] {
  const changes: EngineeringPayload['changes'] = {};
  for (const key of ['ativo', 'visibilidade'] as const) if (!snapshot || values[key] !== (snapshot.matrix[key] === true)) changes[key] = values[key];
  if (!snapshot || values.numero_fotos !== String(snapshot.matrix.numero_fotos ?? '')) changes.numero_fotos = Number(values.numero_fotos);
  if (!snapshot || !sameEngineeringValue(values.form_ids, snapshot.form_ids)) changes.form_ids = [...values.form_ids];
  if (!snapshot || !sameEngineeringValue(values.photos, snapshot.photos.map(photoDraft))) changes.photos = values.photos.map(photo => ({ ...photo }));
  if (!snapshot || !sameEngineeringValue(values.stages, snapshot.stages.map(stageDraft))) changes.stages = values.stages.map(stage => ({ ...stage, aprovadores_ids: [...stage.aprovadores_ids], aprovadores_retorno_ids: [...stage.aprovadores_retorno_ids] }));
  return changes;
}
export function validateEngineering(changes: EngineeringPayload['changes'], choices: EngineeringChoices, cellId: string, snapshot?: EngineeringSnapshot): string | null {
  if (!choices.cells.some(cell => cell.id === cellId)) return 'Escolha a célula do roteiro.';
  if ('numero_fotos' in changes && (!Number.isInteger(changes.numero_fotos) || changes.numero_fotos! < 0 || changes.numero_fotos! > 1000)) return 'Informe uma quantidade prevista inteira entre 0 e 1.000.';
  if (changes.form_ids && changes.form_ids.length > 200) return 'Selecione até 200 formulários para este roteiro.';
  if (changes.photos && changes.photos.length > 1000) return 'Defina até 1.000 itens de foto neste roteiro.';
  if (changes.stages && changes.stages.length > 100) return 'Defina até 100 etapas de aprovação neste roteiro.';
  if (changes.form_ids?.some(id => !snapshot?.form_ids.includes(id) && !choices.forms.some(form => form.id === id && form.ativo && !form.missing))) return 'Escolha somente formulários ativos para novos vínculos.';
  for (const photo of changes.photos ?? []) {
    const original = snapshot?.photos.find(row => row.id === photo.id);
    if (original && sameEngineeringValue(photoDraft(original), photo)) continue;
    if (legacyPhoto(photo, choices, cellId)) return 'Cada foto nova ou alterada precisa de um título desta célula e um número entre 1 e 1.000.';
    if ((photo.descricao?.length ?? 0) > 4000) return 'Use até 4.000 caracteres na orientação da foto.';
  }
  for (const stage of changes.stages ?? []) {
    const original = snapshot?.stages.find(row => row.id === stage.id);
    if (original && sameEngineeringValue(stageDraft(original), stage)) continue;
    if (legacyStage(stage, choices, cellId)) return 'Confira o destino, o status e ao menos um aprovador ativo vinculado a cada célula da etapa alterada.';
  }
  return Object.keys(changes).length ? null : 'Nenhuma alteração foi feita no roteiro.';
}
export const engineeringFutureNotice = 'As alterações serão usadas nas próximas alocações. Células, formulários, fotos e aprovações de projetos já alocados permanecem preservados.';
