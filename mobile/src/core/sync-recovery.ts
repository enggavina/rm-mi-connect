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
