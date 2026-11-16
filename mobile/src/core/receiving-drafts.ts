import { canonicalJson } from './sync-policy';
import type { Receiving } from '../domain/receiving';

export interface ReceivingDraftRemote {
  id: string; revision: number; state: 'draft' | 'finalized'; payload: Receiving;
  result?: Record<string, unknown> | null;
}
export interface ReceivingDraftRequest {
  saveId: string; payload: Receiving; localVersion: number; expectedRevision: number;
}
export interface ReceivingDraftMeta {
  id: string; revision: number; localVersion: number; syncedVersion: number;
  pending?: ReceivingDraftRequest; state: 'pending' | 'saved' | 'conflict' | 'finalized';
  error?: string; result?: Record<string, unknown> | null;
}
export interface ReceivingDraftEntry { data: Receiving; meta: ReceivingDraftMeta }
export function assertReceivingDraftUnchanged(current: ReceivingDraftEntry | null, expected: ReceivingDraftEntry): void {
  if (canonicalJson(current) !== canonicalJson(expected)) throw Object.assign(new Error('O rascunho mudou durante a confirmação. Confira os dados antes de concluir.'), { code: 'RECEIVING_CHANGED' });
}
export interface ReceivingDraftStore {
  load(actor: string): Promise<ReceivingDraftEntry | null>;
  change(actor: string, change: (entry: ReceivingDraftEntry | null) => ReceivingDraftEntry): Promise<ReceivingDraftEntry>;
  archive(actor: string, entry: ReceivingDraftEntry): Promise<void>;
}
export interface ReceivingDraftTransport {
  read(id: string | null): Promise<ReceivingDraftRemote | null>;
  save(id: string, request: ReceivingDraftRequest): Promise<ReceivingDraftRemote>;
}
export function receivingDraftMeta(data: Receiving): ReceivingDraftMeta {
  return { id: data.id, revision: 0, localVersion: 1, syncedVersion: 0, state: 'pending' };
}
function adopted(remote: ReceivingDraftRemote): ReceivingDraftEntry {
  return { data: { ...remote.payload, submitted: remote.state === 'finalized' }, meta: {
    id: remote.id, revision: remote.revision, localVersion: 1, syncedVersion: 1,
    state: remote.state === 'finalized' ? 'finalized' : 'saved', result: remote.result,
  } };
}
const message = (error: unknown) => error instanceof Error ? error.message : (error as {message?: string})?.message || 'Falha ao salvar no banco. O rascunho permanece neste dispositivo.';
const isConflict = (error: unknown) => (error as { code?: string })?.code === 'PT409';

/** Uses the existing local receiving draft; cloud snapshots never create projects.
 * An in-flight request is durable, so a lost response is retried with the exact
 * same save UUID, payload and expected revision before newer edits are sent.
 */
export class ReceivingDraftCoordinator {
  private syncs = new Map<string, Promise<void>>();
  private finalizing = new Set<string>();
  constructor(private store: ReceivingDraftStore, private uuid: () => string) {}

  async open(actor: string, fresh: () => Receiving, remote?: ReceivingDraftTransport): Promise<ReceivingDraftEntry> {
    let local = await this.store.load(actor);
    if (remote) {
      try {
        const cloud = await remote.read(local?.data.id ?? null);
        if (cloud && (!local || cloud.id === local.data.id)) {
          if (cloud.state === 'finalized' && local) {
            // Keep the original local fields/media even when another device finished.
            if (local.meta.state !== 'finalized' && !local.data.submitted) await this.store.archive(actor, local);
            local = await this.store.change(actor, previous => {
              if (!previous || previous.data.id !== cloud.id) return previous ?? adopted(cloud);
              return { data: { ...previous.data, submitted: true }, meta: { ...previous.meta,
                revision: cloud.revision, state: 'finalized', result: cloud.result, pending: undefined, error: undefined } };
            });
          } else if (!local || (!local.data.submitted && !local.meta.pending && local.meta.localVersion === local.meta.syncedVersion)) {
            local = await this.store.change(actor, previous => {
              if (previous && (previous.data.id !== cloud.id || previous.meta.pending || previous.meta.localVersion !== previous.meta.syncedVersion)) return previous;
              return adopted(cloud);
            });
          }
        }
      } catch { /* Opening never sacrifices a durable local draft to a network failure. */ }
    }
    if (!local) local = await this.store.change(actor, previous => previous ?? (() => { const data = fresh(); return { data, meta: receivingDraftMeta(data) }; })());
    return local;
  }

  async save(actor: string, data: Receiving): Promise<ReceivingDraftEntry> {
    return this.store.change(actor, previous => {
      if (previous && previous.data.id !== data.id && !previous.data.submitted && previous.meta.state !== 'finalized') throw new Error('Conclua o rascunho atual antes de iniciar outro recebimento.');
      if (previous?.data.id === data.id && (previous.data.submitted || previous.meta.state === 'finalized')) {
        if (canonicalJson(previous.data) !== canonicalJson(data)) throw new Error('Este recebimento já foi confirmado. Inicie outro recebimento.');
        return previous;
      }
      const meta = previous?.data.id === data.id ? previous.meta : receivingDraftMeta(data);
      return { data, meta: { ...meta, localVersion: meta.localVersion + 1,
        state: meta.state === 'conflict' ? 'conflict' : 'pending', error: meta.state === 'conflict' ? meta.error : undefined } };
    });
  }

  sync(actor: string, remote: ReceivingDraftTransport, resolveMedia: (value: Receiving) => Receiving, queued: (id: string) => Promise<boolean>): Promise<void> {
    const running = this.syncs.get(actor);
    if (running) return running;
    if (this.finalizing.has(actor)) return Promise.resolve();
    const work = this.push(actor, remote, resolveMedia, queued).finally(() => { this.syncs.delete(actor); });
    this.syncs.set(actor, work);
    return work;
  }
  private async push(actor: string, remote: ReceivingDraftTransport, resolveMedia: (value: Receiving) => Receiving, queued: (id: string) => Promise<boolean>) {
    for (let pass = 0; pass < 3; pass++) {
      let entry = await this.store.load(actor);
      if (!entry || this.finalizing.has(actor) || entry.data.submitted || entry.meta.state === 'conflict' || entry.meta.state === 'finalized' || await queued(entry.data.id)) return;
      if (!entry.meta.pending && entry.meta.localVersion === entry.meta.syncedVersion) return;
      try {
        if (!entry.meta.pending) {
          const snapshot = resolveMedia(entry.data), id = entry.data.id;
          const request = { saveId: this.uuid(), payload: snapshot, localVersion: entry.meta.localVersion, expectedRevision: entry.meta.revision };
          entry = await this.store.change(actor, previous => {
            if (!previous || previous.data.id !== id) throw new Error('O rascunho mudou durante o salvamento.');
            return previous.meta.pending ? previous : { ...previous, meta: { ...previous.meta, pending: request } };
          });
        }
        const sent = entry.meta.pending!, id = entry.data.id;
        const saved = await remote.save(id, sent);
        if (saved.id !== id || saved.state !== 'draft' || saved.revision < sent.expectedRevision + 1) throw new Error('Resposta de rascunho inválida.');
        await this.store.change(actor, previous => {
          if (!previous || previous.data.id !== id || previous.meta.pending?.saveId !== sent.saveId) throw new Error('O rascunho mudou durante o salvamento.');
          const synced = Math.max(previous.meta.syncedVersion, sent.localVersion);
          return { ...previous, meta: { ...previous.meta, revision: saved.revision, syncedVersion: synced,
            pending: undefined, error: undefined, state: synced === previous.meta.localVersion ? 'saved' : 'pending' } };
        });
      } catch (error) {
        const id = entry.data.id;
        await this.store.change(actor, previous => {
          if (!previous) throw new Error('Rascunho não encontrado.');
          return previous.data.id !== id ? previous : { ...previous,
            meta: { ...previous.meta, state: isConflict(error) ? 'conflict' : 'pending', error: message(error) } };
        });
        throw error;
      }
    }
  }

  /** Stops cloud writes before freezing the existing durable mutation envelope. */
  async submission<T>(actor: string, run: (entry: ReceivingDraftEntry) => Promise<T>): Promise<T> {
    if (this.finalizing.has(actor)) throw new Error('Aguarde o envio em andamento.');
    this.finalizing.add(actor);
    try {
      await this.syncs.get(actor)?.catch(() => undefined);
      const entry = await this.store.load(actor);
      if (!entry) throw new Error('Rascunho não encontrado.');
      if (entry.meta.state === 'finalized') throw new Error('Este recebimento já foi concluído no banco.');
      if (entry.meta.state === 'conflict') throw new Error('Há uma versão diferente no banco. Confira o rascunho antes de concluir.');
      return await run(entry);
    } finally { this.finalizing.delete(actor); }
  }

  async recover(actor: string, remote: ReceivingDraftTransport): Promise<ReceivingDraftEntry> {
    if (this.finalizing.has(actor)) throw new Error('Aguarde o envio em andamento.');
    this.finalizing.add(actor);
    try {
      await this.syncs.get(actor)?.catch(() => undefined);
      const local = await this.store.load(actor);
      if (local?.data.submitted) throw new Error('Consulte o protocolo já colocado na fila antes de trocar o rascunho.');
      const cloud = await remote.read(local?.data.id ?? null) ?? await remote.read(null);
      if (!cloud) throw new Error('Nenhum rascunho foi encontrado no banco. Seus dados locais foram preservados.');
      if (local) await this.store.archive(actor, local);
      return this.store.change(actor, previous => {
        if (canonicalJson(previous) !== canonicalJson(local)) throw new Error('O rascunho mudou durante a consulta. Seus dados locais foram preservados; tente novamente.');
        return adopted(cloud);
      });
    } finally { this.finalizing.delete(actor); }
  }
}
