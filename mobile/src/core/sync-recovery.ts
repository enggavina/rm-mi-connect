import type { AppSnapshot, OutboxRow, RpcName } from './types';

type Connection = { isConnected: boolean | null; isInternetReachable: boolean | null };
export function knownConnection(state: Connection): boolean | null {
  if (state.isConnected === false || state.isInternetReachable === false) return false;
  return state.isConnected === true ? true : null;
}

type RecoveryEvent =
  | { type: 'connection'; online: boolean; pending: number }
  | { type: 'interrupted-send' }
  | { type: 'queue'; online: boolean; pendingMedia: number; pendingMutations: number; restoring: boolean };

/** Only the durable upload/outbox counts can confirm that recovery is complete. */
export function nextSyncRecovery(active: boolean, event: RecoveryEvent): boolean {
  if (event.type === 'connection') return !event.online || (active && event.pending > 0);
  if (event.type === 'interrupted-send') return true;
  const pending = event.pendingMedia + event.pendingMutations;
  if (event.online && pending === 0) return false;
  return active || (event.restoring && pending > 0);
}

export function showSyncRecovery(state: { online: boolean; connectionKnown: boolean; syncRecovery: boolean; pendingMedia: number; pendingMutations: number }): boolean {
  return state.connectionKnown && state.syncRecovery && (!state.online || state.pendingMedia + state.pendingMutations > 0);
}

type QueueAccess = Pick<AppSnapshot, 'online' | 'connectionKnown' | 'syncRecovery' | 'pendingMedia' | 'pendingMutations' | 'sessionUserId' | 'operator'>;

export function canOpenSyncQueue(state: QueueAccess): boolean {
  return Boolean(state.sessionUserId && state.operator && state.online && showSyncRecovery(state));
}

const operationLabels: Readonly<Record<RpcName, string>> = {
  rm_submit_recebimento_v1: 'Recebimento',
  rm_submit_form_inspection_v1: 'Formulário',
  rm_submit_form_revision_v1: 'Correção de formulário',
  rm_transition_stage_approval_v1: 'Aprovação de etapa',
  rm_record_cell_photo_v1: 'Registro de foto',
  rm_update_cell_status_v1: 'Atualização de status',
  rm_add_cell_comment_v1: 'Comentário',
  rm_record_execution_event_v1: 'Apontamento de execução',
};

export function syncQueueSummary(row: Pick<OutboxRow, 'id' | 'rpc_name' | 'status' | 'created_at'>) {
  const operation = Object.hasOwn(operationLabels, row.rpc_name) ? operationLabels[row.rpc_name] : 'Registro';
  const status = row.status === 'failed' ? 'Aguardando nova tentativa' : row.status === 'syncing' ? 'Enviando' : 'Aguardando envio';
  return { protocol: row.id, operation, status, createdAt: row.created_at, failed: row.status === 'failed' };
}
