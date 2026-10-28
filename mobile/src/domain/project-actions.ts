import type { Operator, OutboxRow, Row, RpcName } from '../core/types';
import { canApprove, label } from './forms';
import type { JourneyContext } from './journey';

export const cellStatusOptions = [
  { value: 'pendente', label: 'Pendente' }, { value: 'retornado', label: 'Retornado' },
  { value: 'liberado_para_ensaios_parciais', label: 'Liberado para ensaios parciais' },
  { value: 'liberado_para_impregna__o', label: 'Liberado para impregnação' },
  { value: 'liberado_para_montagem', label: 'Liberado para montagem' },
  { value: 'para_execu__o', label: 'Para execução' }, { value: 'em_dia', label: 'Executando' },
  { value: 'finalizado', label: 'Finalizado' }, { value: 'atrasado', label: 'Atrasado' }, { value: 'n_a', label: 'N/A' },
] as const;
export const cellStatusLabel = (status?: string) => cellStatusOptions.find(option => option.value === status)?.label ?? label(status);

export function projectClientName(project: Row | undefined, allocation: Row, clients: Row[]): string {
  return clients.find(client => client.id === project?.cliente_id)?.nome || project?.cliente_nome_exportacao || allocation.cliente_nome_export || 'Cliente não informado';
}

export function frontProjectPhoto(projectId: string, photos: Row[]): Row | undefined {
  const frontTitle = (value: unknown) => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/gi, '').toLocaleLowerCase() === 'vistafrontal';
  return photos.filter(photo => photo.projeto_id === projectId && !photo.lixeira && !!photo.foto_url && (photo.tipo_recebimento === 'frente' || frontTitle(photo.titulo)))
    .sort((a, b) => Number(b.tipo_recebimento === 'frente') - Number(a.tipo_recebimento === 'frente') || (a.numero ?? 0) - (b.numero ?? 0))[0];
}

export function cellProjectStages(allocation: Row, stages: Row[]): Row[] {
  return stages.filter(stage => stage.projeto_id === allocation.projeto_id && stage.celula_origem_id === allocation.celula_id && (!stage.celula_projeto_id || stage.celula_projeto_id === allocation.id));
}
export function cellProjectLogs(allocation: Row, logs: Row[]): Row[] {
  return logs.filter(log => log.projeto_id === allocation.projeto_id && log.celula_id === allocation.celula_id).sort((a, b) => String(b.data_aprovacao || b.created_at).localeCompare(String(a.data_aprovacao || a.created_at)));
}
export function cellProjectComments(allocation: Row, comments: Row[]): Row[] {
  return comments.filter(comment => comment.projeto_id === allocation.projeto_id && comment.celula_id === allocation.celula_id).sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
}

export type StageAction = 'liberar' | 'retornar' | 'aprovar';
export const stageActionLabels: Record<StageAction, string> = { liberar: 'Liberar', retornar: 'Retornar', aprovar: 'Aprovar' };
export function availableStageActions(operator: Operator | null, context: JourneyContext, stage: Row): StageAction[] {
  if (!context.ok || !cellProjectStages(context.allocation, [stage]).length || (stage.status != null && stage.status !== 'nulo')) return [];
  if (stage.status_cel_proj === 'retornado') {
    const actions: StageAction[] = context.allocation.status === 'retornado' ? ['retornar', 'aprovar'] : ['aprovar'];
    return actions.filter(action => canApprove(operator, stage, action));
  }
  return stage.status_cel_proj && context.allocation.status === stage.status_cel_proj && canApprove(operator, stage, 'liberar') ? ['liberar'] : [];
}

export function queuedProjectActions(queue: readonly OutboxRow[], rpc: RpcName, reference: { field: string; id: string }): { operation: OutboxRow; params: Record<string, unknown> }[] {
  return queue.flatMap(operation => {
    if (operation.rpc_name !== rpc || operation.status === 'completed') return [];
    try { const params = JSON.parse(operation.params_json); return params?.[reference.field] === reference.id ? [{ operation, params }] : []; } catch { return []; }
  });
}

export function cellCompletionRequirements(allocation: Row, records: Row[], photos: Row[], queue: readonly OutboxRow[], catalogsLoaded: boolean) {
  const forms = new Set<string>((allocation.forms_ids ?? []).filter((id: unknown): id is string => typeof id === 'string' && !!id));
  const filled = new Set(records.filter(record => record.projeto_id === allocation.projeto_id && record.celula_id === allocation.celula_id && record.preenchido === true).map(record => record.form_id));
  const required = photos.filter(photo => photo.projeto_id === allocation.projeto_id && photo.celula_id === allocation.celula_id && photo.categoria_foto === 'obrigat_ria' && !photo.lixeira);
  const captured = new Set(required.filter(photo => typeof photo.foto_url === 'string' && !!photo.foto_url.trim()).map(photo => photo.id));
  for (const operation of queue) {
    if (!['pending', 'syncing'].includes(operation.status)) continue;
    let params: Record<string, unknown>; try { params = JSON.parse(operation.params_json); } catch { continue; }
    if (!params || params.p_projeto_id !== allocation.projeto_id || params.p_celula_id !== allocation.celula_id) continue;
    if (operation.rpc_name === 'rm_submit_form_inspection_v1' && typeof params.p_form_id === 'string' && forms.has(params.p_form_id)
      && Array.isArray(params.p_respostas) && params.p_respostas.every(answer => answer && typeof answer.questao_id === 'string' && !!answer.questao_id)) {
      // An existing validated inspection precedes this new status action in the FIFO queue.
      filled.add(params.p_form_id);
    }
    if (operation.rpc_name === 'rm_record_cell_photo_v1' && typeof params.p_foto_id === 'string'
      && (!params.p_celula_projeto_id || params.p_celula_projeto_id === allocation.id)
      && typeof params.p_foto_url === 'string' && /^(https:\/\/|file:|content:|data:)/.test(params.p_foto_url)
      && required.some(photo => photo.id === params.p_foto_id)) captured.add(params.p_foto_id);
  }
  const missingFormIds = [...forms].filter(id => !filled.has(id));
  const missingPhotoIds = required.filter(photo => !captured.has(photo.id)).map(photo => photo.id);
  return { loaded: catalogsLoaded, missingForms: missingFormIds.length, missingPhotos: missingPhotoIds.length, missingFormIds, missingPhotoIds,
    canFinalize: catalogsLoaded && missingFormIds.length === 0 && missingPhotoIds.length === 0 };
}
