import 'react-native-url-polyfill/auto';
import { AppState, Image, Platform } from 'react-native';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import NetInfo from '@react-native-community/netinfo';
import Constants from 'expo-constants';
import * as Crypto from 'expo-crypto';
import * as FileSystem from 'expo-file-system/legacy';
import * as ImageManipulator from 'expo-image-manipulator';
import { LocalDatabase } from './database';
import { cacheIdentity, forgetCachedIdentity, offlineIdentity, refreshCachedIdentity, secureStorage } from './secure';
import { applyOperatorContext } from './operator-policy';
import { operatorWorkshopDenied, readWorkshopOperatorCells } from './operator-workshop';
import { operatorCatalogKey, operatorScopedCatalogTable, readWorkshopCatalogPage, visibleOperatorCatalogRows, type CatalogCursor, type CatalogSession } from './catalog-workshop';
import { sendWorkshopMutation } from './mutation-workshop';
import { assertReceivingDraftUnchanged, ReceivingDraftCoordinator, receivingDraftMeta, type ReceivingDraftEntry, type ReceivingDraftMeta, type ReceivingDraftRemote, type ReceivingDraftTransport } from './receiving-drafts';
import { newReceiving, receivingPayload, restoreReceiving, type Receiving } from '../domain/receiving';
import { documentFileName, documentType, MAX_DOCUMENT_BYTES, privateDocumentPath } from './document-policy';
import { prefetchWithSpaceReserve } from './media-cache-policy';
import { readWorkshopMedia, workshopMediaCacheKey } from './media-workshop';
import { mediaUploadMime, queuedMediaIntents, queuedWorkshopMediaTransfer, receivingMediaTransfer, sendWorkshopMediaUpload, type AuthorizedMediaTransfer, type MediaIntent } from './media-upload-workshop';
import { knownConnection, nextSyncRecovery } from './sync-recovery';
import { EXECUTION_RPC, executionCacheKey, parseExecutionParams, parseExecutionReceipt, parseExecutionSnapshot, type ExecutionSnapshot } from './execution';
import { EXECUTION_CONTEXT_SQL, EXECUTION_OPERATIONS_SQL, acceptExecutionRead, executionContextKeys, executionContexts, executionEpoch, executionEpochKey, executionLocalView, executionReadRefused, parseExecutionCache, refreshExecutionRead, type ExecutionEpoch, type ExecutionLocalView, type ExecutionScope } from './execution-cache';
import { invalidateExecutionRead, storeExecutionAck, storeExecutionFailure, storeExecutionIntention } from './execution-store';
import { readWorkshopExecution } from './execution-workshop';
import { RECEIVING_OPEN_RPC, ReceivingOpeningCoordinator, parseReceivingOpeningState, receivingOpeningKey, storeReceivingOpening, type ReceivingOpeningState } from './receiving-opening';
import { sendScopedReceiving, sendWorkshopReceivingDraft, type ReceivingDraftCommand } from './receiving-workshop';
import { busySyncWithPriority, canonicalJson, decodeBase64, isConnectivityError, isLocalUri, replaceMedia, retryDelay, uploadThenMutate, validateAnswers } from './sync-policy';
import { queueMatchesWorkshop, type QueueScope } from './workshop-queue-scope';
import { WorkshopRestartRequired, workshopDatabaseName } from './workshop-database';
import { TABLES, RPC_NAMES, type Answer, type AppSnapshot, type Bucket, type CatalogFilter, type CatalogTable, type Draft, type DraftContext, type MediaRow, type Operator, type OutboxRow, type Row, type RpcName } from './types';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';
const scopedReceiving = process.env.EXPO_PUBLIC_EM_SCOPED_RECEIVING === 'true';
const scopedOperatorCells = process.env.EXPO_PUBLIC_EM_SCOPED_OPERATOR_CELLS === 'true';
const scopedCatalog = scopedOperatorCells && process.env.EXPO_PUBLIC_EM_SCOPED_CATALOG === 'true';
const scopedMutations = scopedCatalog && process.env.EXPO_PUBLIC_EM_SCOPED_MUTATIONS === 'true';
const scopedMedia = scopedCatalog && process.env.EXPO_PUBLIC_EM_SCOPED_MEDIA === 'true';
const scopedUploads = scopedMedia && scopedMutations && process.env.EXPO_PUBLIC_EM_SCOPED_UPLOADS === 'true';
const scopedDrafts = scopedCatalog && process.env.EXPO_PUBLIC_EM_SCOPED_DRAFTS === 'true';
const scopedDraftMedia = scopedDrafts && scopedUploads && scopedReceiving;
const scopedExecution = scopedMutations && process.env.EXPO_PUBLIC_EM_SCOPED_EXECUTION === 'true';
const androidBuild = Platform.OS === 'android' && scopedDraftMedia && scopedExecution && Constants.expoConfig?.version
  && Constants.expoConfig.android?.versionCode ? `${Constants.expoConfig.version}/${Constants.expoConfig.android.versionCode}` : undefined;
const mediaDirectory = `${FileSystem.documentDirectory}rm-media/`;
const timestamp = () => new Date().toISOString();
const errorText = (error: unknown) => error instanceof Error ? error.message : typeof error === 'object' && error && 'message' in error ? String(error.message) : String(error);

class MobileService {
  private database = new LocalDatabase();
  private client: SupabaseClient | null = null;
  private snapshot: AppSnapshot = {
    ready: false, configured: /^https:\/\//.test(url) && anonKey.length > 20,
    online: false, connectionKnown: false, syncing: false, syncRecovery: false, sessionUserId: null, operator: null,
    pendingMedia: 0, pendingMutations: 0, lastSync: null, error: null, mediaCacheNotice: null, revision: 0,
  };
  private listeners = new Set<() => void>();
  private initialized?: Promise<void>;
  private syncPromise?: Promise<void>;
  private operatorToken: string | null = null;
  private tabletUserId: string | null = null;
  private localWorkshop: string | null = null;
  private debounce?: ReturnType<typeof setTimeout>;
  private identityBusy = false;
  private mediaWork = new Set<Promise<string>>();
  private scopedDownloads = new Map<string, Promise<string>>();
  private catalogRevision = 0;
  private receivingDebounce?: ReturnType<typeof setTimeout>;
  private receivingDrafts = new ReceivingDraftCoordinator({
    load: async actor => { await this.database.idle(); return this.readReceivingEntry(this.database.connection(), actor); },
    change: async (actor, change) => this.database.write(async db => {
      const next = change(await this.readReceivingEntry(db, actor));
      await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', `recebimento:${actor}`, JSON.stringify(next.data));
      await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', `receiving-sync:${actor}`, JSON.stringify(next.meta));
      return next;
    }),
    archive: async (actor, entry) => this.database.saveLocal(`receiving-recovery:${actor}:${entry.data.id}:${Crypto.randomUUID()}`, entry),
  }, () => Crypto.randomUUID());
  private receivingOpenings = new ReceivingOpeningCoordinator({
    assertOwner: owner => { if (this.snapshot.sessionUserId !== owner) throw new Error('A conta mudou durante a abertura. O recebimento original foi preservado.'); },
    list: () => this.listQueue(),
    read: async (owner, row) => parseReceivingOpeningState(await this.database.local(receivingOpeningKey(owner, row.actor_id, row.id)), owner, row.actor_id, row.id),
    write: async (row, state) => {
      await this.database.write(async db => {
        if (this.snapshot.sessionUserId !== state.owner) throw new Error('A conta mudou durante a abertura.');
        await storeReceivingOpening(db, row, state);
        if (this.snapshot.sessionUserId !== state.owner) throw new Error('A conta mudou durante a abertura.');
      });
      this.update({});
    },
    send: async (owner, row, params) => {
      const scope = scopedCatalog ? await this.operatorWorkshop() : null;
      if (scope && (scope.owner !== owner || !queueMatchesWorkshop(row, scope))) throw new Error('Confirme o operador e a oficina do recebimento original.');
      const { data: auth, error: authError } = await this.supabase().auth.getSession();
      if (authError || !auth.session || auth.session.user.id !== owner || owner !== await secureStorage.getItem('rm.device.owner') || this.snapshot.sessionUserId !== owner) throw new Error('Renove o login da conta original para solicitar a abertura. O recebimento permanece salvo.');
      const token = await secureStorage.getItem(row.token_key);
      if (!token) throw new Error('Identifique novamente o operador responsável para autorizar a abertura.');
      if (this.snapshot.sessionUserId !== owner) throw new Error('A conta mudou durante a abertura.');
      scope?.assertCurrent();
      const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 20_000);
      try {
        if (scopedReceiving) return await sendScopedReceiving({
          deviceToken: auth.session.access_token, operatorToken: token, submission: row.id, phase: 'open',
          payload: params, workshopOrigin: row.workshop_id ?? undefined,
        }, controller.signal);
        const { data, error } = await this.supabase().rpc(RECEIVING_OPEN_RPC, { p_client_submission_id: row.id, p_params: params, p_operator_token: token }).abortSignal(controller.signal);
        if (error) throw error; return data;
      } finally { clearTimeout(timeout); }
    },
  });

  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  getSnapshot = () => this.snapshot;
  // Autosave, network notices and upload counters do not invalidate catalog reads.
  getCatalogRevision = () => this.snapshot.ready ? this.catalogRevision : -1;
  private update(patch: Partial<AppSnapshot>) {
    this.snapshot = { ...this.snapshot, ...patch, revision: this.snapshot.revision + 1 };
    this.listeners.forEach(listener => listener());
  }
  private supabase() { if (!this.client) throw new Error('Configure o Supabase em mobile/.env antes de entrar.'); return this.client; }
  initialize = (): Promise<void> => {
    if (!this.initialized) this.initialized = this.start().catch(error => {
      this.initialized = undefined;
      this.update({ ready: false, error: errorText(error) });
      throw error;
    });
    return this.initialized;
  };
  private async start() {
    const owner = await secureStorage.getItem('rm.device.owner');
    const workshop = owner ? await secureStorage.getItem(`rm.workshop.device.${owner}`) : null;
    const baseOffice = owner ? await secureStorage.getItem(`rm.workshop.local-base.${owner}`) : null;
    await this.database.initialize(workshopDatabaseName(workshop, baseOffice));
    this.localWorkshop = workshop;
    await FileSystem.makeDirectoryAsync(mediaDirectory, { intermediates: true });
    this.tabletUserId = await secureStorage.getItem('rm.device.rm_user');
    this.update({ sessionUserId: owner, lastSync: await this.database.local<string>('last_sync') });
    if (this.snapshot.configured) {
      this.client = createClient(url, anonKey, {
        auth: { storage: secureStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
        global: { headers: { 'X-Client-Info': 'rm-mi-connect-mobile/1.0' } },
      });
      this.client.auth.onAuthStateChange(event => {
        if (event === 'TOKEN_REFRESHED') this.scheduleSync();
      });
      this.client.channel('rm-mobile-updates').on('postgres_changes', { event: '*', schema: 'public' }, () => this.scheduleSync()).subscribe();
      AppState.addEventListener('change', state => {
        if (state === 'active') { this.client?.auth.startAutoRefresh(); this.scheduleSync(); }
        else { void this.syncReceivingDraft().catch(() => undefined); this.client?.auth.stopAutoRefresh(); }
      });
    }
    NetInfo.addEventListener(state => {
      const online = knownConnection(state);
      if (online === null) return;
      this.update({ online, connectionKnown: true, syncRecovery: nextSyncRecovery(this.snapshot.syncRecovery, {
        type: 'connection', online, pending: this.snapshot.pendingMedia + this.snapshot.pendingMutations,
      }) });
      if (online) this.scheduleSync();
    });
    setInterval(() => { if (this.snapshot.online && AppState.currentState === 'active') this.scheduleSync(); }, 30_000);
    await this.refreshCounts();
    this.update({ ready: true });
    this.scheduleSync();
  }
  private scheduleSync() {
    // Independent of an already-running upload batch: a newly requested
    // receiving must reach the portal before unrelated photos finish sending.
    void this.prioritizeReceivingOpenings().catch(() => undefined);
    if (this.debounce) clearTimeout(this.debounce);
    this.debounce = setTimeout(() => { void this.sync().catch(error => this.update({ error: errorText(error) })); }, 600);
  }
  async login(email: string, password: string) {
    const existingOwner = await secureStorage.getItem('rm.device.owner');
    const { data, error } = await this.supabase().auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw error;
    if (existingOwner && existingOwner !== data.user.id) {
      await this.supabase().auth.signOut({ scope: 'local' });
      this.update({ sessionUserId: existingOwner, operator: null });
      throw new Error('Este dispositivo contém dados de outra conta. Entre com a conta original para preservar os rascunhos e a fila.');
    }
    const { data: rmUser, error: userError } = await this.supabase().from('rm_users').select('id,status').eq('auth_user_id', data.user.id).single();
    if (userError || !rmUser || rmUser.status !== 'ativo') throw new Error('A conta precisa estar vinculada a um usuário RM ativo no Supabase.');
    this.tabletUserId = rmUser.id;
    await secureStorage.setItem('rm.device.owner', data.user.id);
    await secureStorage.setItem('rm.device.rm_user', rmUser.id);
    this.update({ sessionUserId: data.user.id, error: null });
    this.scheduleSync();
  }
  async identify(matricula: string, password: string) {
    if (this.identityBusy) throw new Error('Aguarde a validação em andamento.');
    const owner = this.snapshot.sessionUserId;
    if (!owner) throw new Error('Entre primeiro com a conta do dispositivo.');
    this.identityBusy = true;
    try {
      let identity: {operator: Operator; token: string};
      let verifiedWorkshop: string | undefined;
      if (this.snapshot.online) {
        try {
        const { data, error } = await this.supabase().rpc('rm_authenticate_operator_v1', {
          p_matricula: matricula.trim(), p_palavra_chave: password,
          p_tablet_user_id: this.tabletUserId, p_local: 'EM / MI Electric Brasil',
        });
        if (error) throw error;
        if (data?.authenticated === false) throw new Error(data.error ?? 'Credenciais inválidas.');
        if (!data?.operator_token || !data?.operador_id) throw new Error('A migração 006 de autenticação e sincronização precisa estar aplicada.');
        const { operator_token: token, ...operator } = data;
        identity = { operator: operator as Operator, token: String(token) };
        if (scopedOperatorCells) {
          try {
            const scoped = await this.scopeOperator(owner, identity.operator, identity.token, true);
            identity.operator = scoped.operator;
            verifiedWorkshop = scoped.workshopId;
          } catch (failure) {
            if (operatorWorkshopDenied(failure)) await this.forgetWorkshopOperator(owner, identity.operator);
            throw failure;
          }
        }
        await cacheIdentity(identity.operator, identity.token, password, owner);
        if (verifiedWorkshop) await secureStorage.setItem(`rm.workshop.operator.${owner}.${identity.operator.operador_id}`, verifiedWorkshop);
        } catch (error) {
          if (!isConnectivityError(error)) throw error;
          identity = await offlineIdentity(matricula,password,owner);
        }
      } else identity = await offlineIdentity(matricula, password, owner);
      if (scopedOperatorCells && !verifiedWorkshop) {
        const office = await secureStorage.getItem(`rm.workshop.device.${owner}`);
        const confirmed = await secureStorage.getItem(`rm.workshop.operator.${owner}.${identity.operator.operador_id}`);
        if (!office || office !== confirmed || office !== this.localWorkshop || await secureStorage.getItem(`rm.workshop.suspended.${owner}`)) {
          throw new Error('Conecte-se para confirmar a oficina deste operador. Os trabalhos salvos foram preservados.');
        }
      }
      this.operatorToken = identity.token;
      this.update({ operator: identity.operator, error: null });
      await this.database.write(async db => {
        const o = identity.operator;
        await db.runAsync(`INSERT INTO local_operator_session(operador_id,matricula,nome,cargo,perfil,perfil_assinante_json,equipe_id,celulas_vinculadas_json,authenticated_at)
          VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(operador_id) DO UPDATE SET nome=excluded.nome,perfil=excluded.perfil,perfil_assinante_json=excluded.perfil_assinante_json,celulas_vinculadas_json=excluded.celulas_vinculadas_json,authenticated_at=excluded.authenticated_at`,
          o.operador_id, o.matricula, o.nome, o.cargo ?? null, o.perfil, JSON.stringify(o.perfil_assinante ?? []), o.equipe_id ?? null, JSON.stringify(o.celulas_vinculadas ?? []), o.authenticated_at);
      });
      // Refresh only this actor's queued grants. Other operators retain their original attribution.
      const actor = identity.operator.operador_id;
      const workshop = verifiedWorkshop ?? (scopedCatalog ? await secureStorage.getItem(`rm.workshop.device.${owner}`) : null);
      for (const item of await this.pendingQueue()) {
        if (item.actor_id !== actor || (scopedCatalog && (!workshop || !queueMatchesWorkshop(item, { actor, workshop })))) continue;
        await secureStorage.setItem(item.token_key, identity.token);
      }
      this.scheduleSync();
    } finally {
      this.identityBusy = false;
      this.catalogRevision++;
      // After a process restart, scoped rows are invisible until their author
      // identifies again. Restore the recovery notice from that durable queue.
      await this.refreshCounts(Boolean(this.snapshot.operator)).catch(() => undefined);
    }
  }
  async switchOperator() {
    await Promise.allSettled([...this.mediaWork]);
    await this.database.idle();
    this.operatorToken = null; this.update({ operator: null, error: null });
    await this.refreshCounts();
  }
  list = async (table: string, filter?: CatalogFilter) => {
    const rows = await this.database.list(table, filter);
    return this.visibleCatalogRows(table, rows);
  };
  get = async (table: string, id: string) => {
    const row = await this.database.get(table, id);
    return row ? (await this.visibleCatalogRows(table, [row]))[0] ?? null : null;
  };

  private async visibleCatalogRows(table: string, rows: Row[]): Promise<Row[]> {
    if (!scopedCatalog) return rows;
    const operator = this.snapshot.operator;
    const scope = await this.operatorWorkshop().catch(() => null);
    if (!scope || operator?.operador_id !== scope.actor) return [];
    if (!operatorScopedCatalogTable(table)) return rows;
    const manifest = await this.database.local<string[]>(operatorCatalogKey(scope.workshop, scope.actor, table));
    scope.assertCurrent();
    return visibleOperatorCatalogRows(table, rows, operator, manifest ?? null);
  }
  getLocal = <T = unknown>(key: string) => this.database.local<T>(key);
  async saveLocal(key: string, value: unknown) { await this.database.saveLocal(key, value); this.update({}); }
  private async readReceivingEntry(db: ReturnType<LocalDatabase['connection']>, actor: string): Promise<ReceivingDraftEntry | null> {
    const rows = await db.getAllAsync<{key: string; value: string}>('SELECT key,value FROM local_meta WHERE key IN (?,?)', `recebimento:${actor}`, `receiving-sync:${actor}`);
    const raw = rows.find(row => row.key === `recebimento:${actor}`);
    if (!raw) return null;
    const data = restoreReceiving(JSON.parse(raw.value), '', timestamp());
    const stored = rows.find(row => row.key === `receiving-sync:${actor}`);
    const meta = stored ? JSON.parse(stored.value) as ReceivingDraftMeta : null;
    return { data, meta: meta?.id === data.id ? meta : receivingDraftMeta(data) };
  }
  private receivingTransport(token: string): ReceivingDraftTransport {
    const invoke = async (args: ReceivingDraftCommand): Promise<ReceivingDraftRemote | null> => {
      const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), scopedDrafts ? 25_000 : 8_000);
      try {
        let data;
        if (scopedDrafts) {
          const scope = await this.operatorWorkshop();
          const session = await this.supabase().auth.getSession();
          scope.assertCurrent();
          if (session.error || !session.data.session || session.data.session.user.id !== scope.owner || scope.token !== token) {
            throw new Error('Confirme o operador original para sincronizar o rascunho.');
          }
          data = await sendWorkshopReceivingDraft({ deviceToken: session.data.session.access_token, operatorToken: token,
            workshopOrigin: scope.workshop, args }, controller.signal);
          scope.assertCurrent();
        } else {
          const params = args.action === 'save' ? { p_payload: args.payload, p_expected_revision: args.expectedRevision, p_save_id: args.saveId } : {};
          const result = await this.supabase().rpc('rm_receiving_draft_v1', { p_operator_token: token, p_action: args.action,
            p_draft_id: args.draftId, ...params }).abortSignal(controller.signal);
          if (result.error) throw result.error;
          data = result.data;
        }
        if (data == null) return null;
        if (typeof data.id !== 'string' || !Number.isSafeInteger(data.revision) || data.revision < 1 || !['draft', 'finalized'].includes(data.state) || data.payload?.id !== data.id) throw new Error('Resposta de rascunho inválida.');
        return { ...data, payload: restoreReceiving(data.payload, '', timestamp()) } as ReceivingDraftRemote;
      } finally { clearTimeout(timeout); }
    };
    return {
      read: id => invoke({ action: 'read', draftId: id }),
      save: async (id, request) => {
        const saved = await invoke({ action: 'save', draftId: id, payload: request.payload,
          expectedRevision: request.expectedRevision, saveId: request.saveId });
        if (!saved) throw new Error('O banco não confirmou o salvamento do rascunho.');
        return saved;
      },
    };
  }
  async openReceivingDraft(): Promise<Receiving> {
    const actor = this.actor(), token = this.operatorToken!;
    const origin = await this.receivingDraftOrigin(actor.operador_id);
    const entry = await this.receivingDrafts.open(actor.operador_id, () => newReceiving(Crypto.randomUUID(), timestamp()),
      this.snapshot.online ? this.receivingTransport(token) : undefined, origin);
    if (await this.operation(entry.data.id)) {
      entry.data = { ...entry.data, submitted: true };
      await this.database.saveLocal(`recebimento:${actor.operador_id}`, entry.data);
    }
    this.scheduleReceivingSync(); this.update({});
    return entry.data;
  }
  async saveReceivingDraft(data: Receiving, operatorId = this.snapshot.operator?.operador_id): Promise<void> {
    // Local writes keep the actor captured when editing began, even if the turn
    // expires or the operator changes while SQLite is draining pending writes.
    if (!operatorId) throw new Error('O responsável pelo rascunho não foi identificado.');
    await this.receivingDrafts.save(operatorId, data, await this.receivingDraftOrigin(operatorId));
    this.update({}); this.scheduleReceivingSync();
  }
  private async receivingDraftOrigin(actor: string): Promise<ReceivingDraftMeta['origin']> {
    if (!scopedDraftMedia || this.snapshot.operator?.operador_id !== actor) return undefined;
    const scope = await this.operatorWorkshop().catch(() => null);
    if (scope?.actor === actor) return { workshop: scope.workshop, device: scope.owner };
  }
  private async assertReceivingDraftOrigin(actor: string, entry?: ReceivingDraftEntry | null) {
    if (!scopedDraftMedia || !entry?.meta.origin) return;
    const current = await this.receivingDraftOrigin(actor);
    if (current?.workshop !== entry.meta.origin.workshop || current.device !== entry.meta.origin.device) {
      throw new Error('O rascunho pertence à oficina ou ao dispositivo original. Os dados continuam salvos.');
    }
  }
  async receivingDraftInfo(): Promise<ReceivingDraftMeta | null> {
    const actor = this.snapshot.operator;
    if (!actor) return null;
    await this.database.idle();
    return (await this.readReceivingEntry(this.database.connection(), actor.operador_id))?.meta ?? null;
  }
  async recoverReceivingDraft(): Promise<Receiving> {
    const actor = this.actor(), token = this.operatorToken!;
    if (!this.snapshot.online) throw new Error('Conecte para consultar a versão do banco. Seu rascunho local está salvo.');
    await this.database.idle();
    const local = await this.readReceivingEntry(this.database.connection(), actor.operador_id);
    if (local && await this.operation(local.data.id)) throw new Error('Consulte o recebimento já colocado na fila antes de trocar o rascunho.');
    const entry = await this.receivingDrafts.recover(actor.operador_id, this.receivingTransport(token), await this.receivingDraftOrigin(actor.operador_id));
    this.update({}); return entry.data;
  }
  private scheduleReceivingSync() {
    if (this.receivingDebounce) clearTimeout(this.receivingDebounce);
    this.receivingDebounce = setTimeout(() => { void this.syncReceivingDraft().catch(() => undefined); }, 1_200);
  }
  private async syncReceivingDraft(): Promise<void> {
    const actor = this.snapshot.operator, token = this.operatorToken;
    if (!actor || !token || !this.snapshot.online || !this.client) return;
    // A newly opened slot can coexist locally with an older confirmed receiving
    // in FIFO. Let those receipts finalize first instead of treating its still
    // active cloud draft as a permanent version conflict for the new slot.
    if ((await this.listQueue()).some(row => row.actor_id === actor.operador_id && row.rpc_name === 'rm_submit_recebimento_v1')) return;
    const media = await this.database.connection().getAllAsync<{local_uri: string; public_url: string}>("SELECT local_uri,public_url FROM local_media_upload_queue WHERE status='uploaded'");
    const uploaded = new Map(media.map(row => [row.local_uri, row.public_url]));
    try {
      if (scopedDraftMedia) await this.assertReceivingDraftOrigin(actor.operador_id, await this.readReceivingEntry(this.database.connection(), actor.operador_id));
      await this.receivingDrafts.sync(actor.operador_id, this.receivingTransport(token), value => replaceMedia(value, uploaded), async id => !!await this.operation(id));
    } finally { this.update({}); }
  }
  async submitReceivingDraft(): Promise<string> {
    const actor = this.actor();
    return this.receivingDrafts.submission(actor.operador_id, async entry => {
      if (this.snapshot.operator?.operador_id !== actor.operador_id) throw new Error('O operador mudou. Retome com o responsável antes de enviar.');
      if (await this.operation(entry.data.id)) return entry.data.id;
      await this.assertReceivingDraftOrigin(actor.operador_id, entry);
      if (this.snapshot.online) {
        const transport = this.receivingTransport(this.operatorToken!);
        const cloud = await transport.read(entry.data.id).catch(() => null);
        if (cloud?.state === 'finalized') {
          await this.receivingDrafts.open(actor.operador_id, () => entry.data, transport);
          this.update({});
          throw Object.assign(new Error('Este recebimento já foi concluído no banco. O protocolo original foi preservado.'), { code: 'RECEIVING_FINALIZED' });
        }
      }
      if (this.snapshot.operator?.operador_id !== actor.operador_id) throw new Error('O operador mudou. Retome com o responsável antes de enviar.');
      return this.enqueue('rm_submit_recebimento_v1', { ...receivingPayload(entry.data), p_receiving_draft_id: entry.data.id,
        p_receiving_draft_revision: entry.meta.revision, p_receiving_draft_save_id: entry.meta.pending?.saveId ?? null,
        p_receiving_draft_snapshot: { ...entry.data, submitted: false } }, entry.data.id, undefined, entry);
    });
  }
  private actor() {
    if (!this.snapshot.operator || !this.operatorToken) throw new Error('Identifique o operador antes de registrar dados.');
    if (Date.now() - Date.parse(this.snapshot.operator.authenticated_at) >= 86_400_000 || Date.parse(this.snapshot.operator.token_expires_at ?? '') < Date.now()) {
      this.operatorToken = null;
      this.update({ operator: null });
      throw new Error('A identificação do turno expirou. Identifique-se novamente; seus rascunhos estão preservados.');
    }
    return this.snapshot.operator;
  }
  async startNewDraft(context: DraftContext): Promise<Draft> {
    const actor = this.actor();
    await this.database.write(async db => {
      const old = await db.getFirstAsync<{draft_id: string; status: string}>('SELECT draft_id,status FROM local_form_drafts WHERE projeto_id=? AND celula_id=? AND form_id=? AND operador_id=?', context.projeto_id, context.celula_id, context.form_id, actor.operador_id);
      if (old && old.status !== 'synced') throw new Error('Conclua e sincronize o rascunho atual antes de iniciar outro preenchimento.');
      if (old) await db.runAsync('DELETE FROM local_form_drafts WHERE draft_id=?', old.draft_id);
    });
    return this.getDraft(context);
  }
  async getDraft(context: DraftContext): Promise<Draft> {
    const actor = this.actor();
    const db = this.database.connection();
    let draft = await db.getFirstAsync<Omit<Draft, 'answers'>>('SELECT d.*, c.registro_formulario_id FROM local_form_drafts d LEFT JOIN local_draft_context c USING(draft_id) WHERE projeto_id=? AND celula_id=? AND form_id=? AND operador_id=?', context.projeto_id, context.celula_id, context.form_id, actor.operador_id);
    const sourceRecord = context.registro_formulario_id ? await this.get('rm_registros_formulario', context.registro_formulario_id) : null;
    const sourceVersion = draft ? await this.database.local<string>(`draft_version:${draft.draft_id}`) : null;
    const newRevisionCycle = draft?.status === 'synced' && sourceRecord?.status === 'direcionado' && sourceRecord.updated_at !== sourceVersion;
    if (draft && ((draft.registro_formulario_id ?? null) !== (context.registro_formulario_id ?? null) || newRevisionCycle)) {
      if (draft.status !== 'synced') throw new Error('Há um rascunho ou envio pendente deste formulário. Conclua e sincronize antes de iniciar outro registro.');
      await this.database.write(tx => tx.runAsync('DELETE FROM local_form_drafts WHERE draft_id=?', draft!.draft_id));
      draft = null;
    }
    if (!draft) {
      const id = Crypto.randomUUID();
      const created: Omit<Draft, 'answers'> = { ...context, draft_id: id, client_submission_id: Crypto.randomUUID(), operador_id: actor.operador_id, started_at: timestamp(), status: 'in_progress' };
      await this.database.write(async tx => {
        await tx.runAsync(`INSERT INTO local_form_drafts(draft_id,client_submission_id,projeto_id,celula_id,form_id,operador_id,started_at) VALUES (?,?,?,?,?,?,?)`, id, created.client_submission_id, context.projeto_id, context.celula_id, context.form_id, actor.operador_id, created.started_at);
        await tx.runAsync('INSERT INTO local_draft_context(draft_id,registro_formulario_id) VALUES (?,?)', id, context.registro_formulario_id ?? null);
      });
      draft = created;
      if (sourceRecord) await this.database.saveLocal(`draft_version:${id}`, sourceRecord.updated_at);
      if (context.registro_formulario_id) {
        // Historical snapshots without a surviving question are read-only; they never become editable drafts.
        const originals = (await this.list('rm_respostas', { field: 'registro_formulario_id', value: context.registro_formulario_id })).filter(r => typeof r.questao_id === 'string' && !!r.questao_id);
        for (const r of originals) await this.saveAnswer(id, { ...r, resposta_id: r.id, is_na: r.resposta === 'N/A' } as unknown as Answer);
      }
    }
    const answers = await db.getAllAsync<{payload: string}>('SELECT payload FROM local_answer_payload WHERE draft_id=?', draft.draft_id);
    return { ...draft, answers: answers.map(a => JSON.parse(a.payload) as Answer) };
  }
  async saveAnswer(draftId: string, answer: Answer) {
    const actor = this.actor();
    await this.database.write(async db => {
      const draft = await db.getFirstAsync<{status: string; operador_id: string}>('SELECT status,operador_id FROM local_form_drafts WHERE draft_id=?', draftId);
      if (draft?.operador_id !== actor.operador_id) throw new Error('Este rascunho pertence a outro operador.');
      if (draft.status !== 'in_progress') throw new Error('Este formulário já foi colocado na fila de envio.');
      await db.runAsync(`INSERT INTO local_answer_payload(draft_id,questao_id,payload) VALUES (?,?,?) ON CONFLICT(draft_id,questao_id) DO UPDATE SET payload=excluded.payload`, draftId, answer.questao_id, JSON.stringify(answer));
      await db.runAsync(`INSERT INTO local_respostas_draft(id,draft_id,questao_id,indice,enunciado,tipo,dimensoes,resposta,itens_json,itens_questoes_ids_json,local_fotos_uris_json,uploaded_fotos_urls_json,local_assinatura_uri,uploaded_assinatura_url,date_inicio,data_fim,hora,is_na,updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(draft_id,questao_id) DO UPDATE SET resposta=excluded.resposta,itens_json=excluded.itens_json,itens_questoes_ids_json=excluded.itens_questoes_ids_json,local_fotos_uris_json=excluded.local_fotos_uris_json,uploaded_fotos_urls_json=excluded.uploaded_fotos_urls_json,local_assinatura_uri=excluded.local_assinatura_uri,uploaded_assinatura_url=excluded.uploaded_assinatura_url,date_inicio=excluded.date_inicio,data_fim=excluded.data_fim,hora=excluded.hora,is_na=excluded.is_na,updated_at=excluded.updated_at`,
        Crypto.randomUUID(), draftId, answer.questao_id, answer.indice, answer.enunciado, answer.tipo, answer.dimensoes ?? null, answer.resposta ?? null, JSON.stringify(answer.itens ?? []), JSON.stringify(answer.itens_questoes_ids ?? []),
        JSON.stringify((answer.fotos_urls ?? []).filter(isLocalUri)), JSON.stringify((answer.fotos_urls ?? []).filter(u => !isLocalUri(u))),
        answer.assinatura_url && isLocalUri(answer.assinatura_url) ? answer.assinatura_url : null,
        answer.assinatura_url && !isLocalUri(answer.assinatura_url) ? answer.assinatura_url : null,
        answer.date_inicio ?? null, answer.data_fim ?? null, answer.hora ?? null, answer.is_na ? 1 : 0, timestamp());
    });
  }
  saveDraft = (draftId: string, answer: Answer) => this.saveAnswer(draftId, answer);
  async submitDraft(draftId: string, revisionRecordId?: string) {
    await this.database.idle();
    const row = await this.database.connection().getFirstAsync<DraftContext>('SELECT d.*, c.registro_formulario_id FROM local_form_drafts d LEFT JOIN local_draft_context c USING(draft_id) WHERE draft_id=?', draftId);
    if (!row) throw new Error('Rascunho não encontrado.');
    const draft = await this.getDraft(row);
    if (draft.status !== 'in_progress') return draft.client_submission_id;
    const questions = await this.list('rm_questoes', { field: 'form_id', value: draft.form_id });
    const recordId = revisionRecordId ?? draft.registro_formulario_id;
    const submittedAnswers = recordId ? draft.answers.filter(a => a.revisar === true) : draft.answers;
    const submittedQuestions = recordId ? questions.filter(q => submittedAnswers.some(a => a.questao_id === q.id)) : questions;
    const missing = validateAnswers(submittedQuestions, submittedAnswers);
    if (missing.length) throw new Error(`Preencha as questões obrigatórias: ${missing.join(', ')}`);
    if (recordId && !submittedAnswers.length) throw new Error('Não há respostas devolvidas para correção neste registro. Sincronize o formulário.');
    const rpc: RpcName = recordId ? 'rm_submit_form_revision_v1' : 'rm_submit_form_inspection_v1';
    const params = recordId ? { p_registro_formulario_id: recordId, p_respostas_corrigidas: submittedAnswers }
      : { p_client_submission_id: draft.client_submission_id, p_projeto_id: draft.projeto_id, p_celula_id: draft.celula_id, p_form_id: draft.form_id, p_tablet_user_id: this.tabletUserId, p_tempo_de_vida: Math.max(0, Math.floor((Date.now() - Date.parse(draft.started_at)) / 1000)), p_respostas: draft.answers };
    return this.enqueue(rpc, params, draft.client_submission_id, draftId);
  }
  async enqueue(rpc: RpcName, params: Record<string, unknown>, id = Crypto.randomUUID(), draftId?: string, receiving?: ReceivingDraftEntry) {
    if (!(RPC_NAMES as readonly string[]).includes(rpc)) throw new Error('Operação não permitida.');
    const actor = this.actor(), tokenKey = `rm.operation.${id}`, token = this.operatorToken!, owner = this.snapshot.sessionUserId;
    const scope = scopedCatalog ? await this.operatorWorkshop() : null;
    const payload = {...params,p_operador_id:actor.operador_id};
    await this.database.write(async db => {
      const already = await db.getFirstAsync<{id: string; rpc_name: string; params_json: string; actor_id: string | null}>('SELECT o.id,o.rpc_name,o.params_json,m.actor_id FROM local_rpc_outbox o LEFT JOIN local_queue_meta m USING(id) WHERE o.id=?', id);
      if (already) {
        if (already.rpc_name !== rpc || canonicalJson(JSON.parse(already.params_json)) !== canonicalJson(payload) || rpc === EXECUTION_RPC && already.actor_id !== actor.operador_id) throw new Error('Este protocolo já foi enviado com outros dados. Consulte o envio antes de alterar o registro.');
        return;
      }
      scope?.assertCurrent();
      if (receiving) {
        if (rpc !== 'rm_submit_recebimento_v1' || receiving.data.id !== id) throw new Error('Contexto de recebimento inválido.');
        assertReceivingDraftUnchanged(await this.readReceivingEntry(db, actor.operador_id), receiving);
      }
      await secureStorage.setItem(tokenKey,token);
      if (rpc === EXECUTION_RPC) {
        if (!owner) throw new Error('A conta do dispositivo não está disponível.');
        await storeExecutionIntention(db, { id, owner, actor: actor.operador_id, tokenKey, params: payload, createdAt: timestamp() });
      } else {
        await db.runAsync(`INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES (?,?,?,?)`, id, rpc, JSON.stringify(payload), timestamp());
        await db.runAsync('INSERT INTO local_queue_meta(id,actor_id,token_key,draft_id) VALUES (?,?,?,?)', id, actor.operador_id, tokenKey, draftId ?? null);
      }
      if (scope) {
        scope.assertCurrent();
        await db.runAsync('UPDATE local_queue_meta SET workshop_id=? WHERE id=?', scope.workshop, id);
      }
      if (draftId) await db.runAsync("UPDATE local_form_drafts SET status='ready_to_sync' WHERE draft_id=?", draftId);
      if (receiving) await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', `recebimento:${actor.operador_id}`, JSON.stringify({ ...receiving.data, submitted: true }));
    });
    await this.refreshCounts();
    if (rpc === 'rm_submit_recebimento_v1') void this.prioritizeReceivingOpenings().catch(() => undefined);
    this.scheduleSync();
    return id;
  }
  /** Execution intentions live only in the atomic outbox+author transaction.
   * There is no independent submitted marker that can get ahead of the queue. */
  async recordExecutionEvent(params: unknown, submissionId: string) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(submissionId)) throw new Error('Protocolo de apontamento inválido.');
    return this.enqueue(EXECUTION_RPC, parseExecutionParams(params), submissionId);
  }
  private async executionState(db: ReturnType<LocalDatabase['connection']>, scope: ExecutionScope) {
    const cacheKey = executionCacheKey(scope.owner, scope.operatorId, scope.allocationId, scope.workshopId);
    const epochKey = executionEpochKey(scope.owner, scope.operatorId);
    const values = await db.getAllAsync<{ key: string; value: string }>('SELECT key,value FROM local_meta WHERE key IN (?,?)', cacheKey, epochKey);
    const epoch = executionEpoch(values.some(r => r.key === epochKey) ? JSON.parse(values.find(r => r.key === epochKey)!.value) : null);
    const cache = parseExecutionCache(values.some(r => r.key === cacheKey) ? JSON.parse(values.find(r => r.key === cacheKey)!.value) : null, scope);
    const office = scope.workshopId ?? null;
    const operations = await db.getAllAsync<OutboxRow>(EXECUTION_OPERATIONS_SQL,
      EXECUTION_RPC, scope.operatorId, office, office, EXECUTION_RPC, scope.operatorId, office, office);
    const rows = await db.getAllAsync<{ key: string; value: string }>(EXECUTION_CONTEXT_SQL, JSON.stringify(executionContextKeys(scope, cache, operations)));
    return { cache, epoch, view: executionLocalView(cache, epoch, operations, executionContexts(rows, scope, epoch)) };
  }
  async executionSnapshot(allocationId: string, refresh = true): Promise<ExecutionLocalView> {
    const operator = this.snapshot.operator, owner = this.snapshot.sessionUserId, token = this.operatorToken;
    if (!operator || !owner || !token) throw new Error('Identifique o operador para consultar seus apontamentos.');
    const office = scopedExecution ? await this.operatorWorkshop() : null;
    const actorId = operator.operador_id, scope = { owner, operatorId: actorId, allocationId, workshopId: office?.workshop };
    const current = () => this.snapshot.sessionUserId === owner && this.snapshot.operator?.operador_id === actorId && this.operatorToken === token;
    const guard = () => {
      if (!current()) throw new Error('O operador mudou durante a consulta. Seus registros foram preservados.');
      office?.assertCurrent();
    };
    const read = () => this.database.write(async db => { guard(); const state = await this.executionState(db, scope); guard(); return state.view; });
    if (!refresh || !this.snapshot.online) return read();
    return refreshExecutionRead(read, async () => {
      guard();
      try {
        if (office) {
          const { data, error } = await this.supabase().auth.getSession();
          guard();
          if (error || !data.session || data.session.user.id !== owner) throw Object.assign(new Error('Renove a sessão original do dispositivo.'), { code: '28000' });
          const result = await readWorkshopExecution({ deviceToken: data.session.access_token, operatorToken: token,
            workshopOrigin: office.workshop, operatorId: actorId, allocation: allocationId });
          guard();
          return result;
        }
        const { data, error } = await this.supabase().rpc('rm_mobile_execution_snapshot_v1', { p_operator_token: token, p_allocation_id: allocationId });
        guard();
        if (error) throw error;
        return parseExecutionSnapshot(data, actorId, allocationId);
      } catch (error) {
        if (executionReadRefused(error)) {
          await this.database.write(async db => { guard(); await invalidateExecutionRead(db, owner, actorId); guard(); });
          this.update({}); // SQLite-only consumers see the persistent read fence.
        }
        throw error;
      }
    }, (ticket: ExecutionEpoch, parsed: ExecutionSnapshot) => this.database.write(async db => {
      guard(); const state = await this.executionState(db, scope); guard();
      const accepted = acceptExecutionRead(state.cache, state.epoch, ticket, parsed, scope);
      if (accepted && accepted !== state.cache) await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        executionCacheKey(owner, actorId, allocationId, scope.workshopId), JSON.stringify(accepted));
      guard();
      const committed = await this.executionState(db, scope); guard();
      return committed.view;
    }));
  }
  private async pendingQueue(): Promise<OutboxRow[]> {
    return this.database.connection().getAllAsync<OutboxRow>(`SELECT o.*,m.next_retry_at,m.actor_id,m.token_key,m.draft_id,m.result_json,m.workshop_id FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE status<>'completed' ORDER BY o.created_at,o.rowid`);
  }
  async listQueue(): Promise<OutboxRow[]> {
    if (!scopedCatalog) return this.pendingQueue();
    const scope = await this.operatorWorkshop().catch(() => null);
    if (!scope) return [];
    const rows = await this.pendingQueue();
    scope.assertCurrent();
    return rows.filter(row => queueMatchesWorkshop(row, scope));
  }
  async operation(id: string): Promise<(OutboxRow & { result?: unknown }) | null> {
    const scope = scopedCatalog ? await this.operatorWorkshop().catch(() => null) : null;
    if (scopedCatalog && !scope) return null;
    const row = await this.database.connection().getFirstAsync<OutboxRow>('SELECT o.*,m.next_retry_at,m.actor_id,m.token_key,m.draft_id,m.result_json,m.workshop_id FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.id=?', id);
    scope?.assertCurrent();
    return row && (!scope || queueMatchesWorkshop(row, scope)) ? { ...row, result: row.result_json ? JSON.parse(row.result_json) : undefined } : null;
  }
  async receivingOpeningInfo(id: string): Promise<ReceivingOpeningState | null> {
    const owner = this.snapshot.sessionUserId, actor = this.snapshot.operator?.operador_id;
    if (!owner || !actor) return null;
    const row = await this.operation(id);
    if (!row || row.rpc_name !== 'rm_submit_recebimento_v1' || row.actor_id !== actor) return null;
    const raw = await this.database.local(receivingOpeningKey(owner, actor, id));
    if (this.snapshot.sessionUserId !== owner || this.snapshot.operator?.operador_id !== actor) return null;
    return parseReceivingOpeningState(raw, owner, actor, id);
  }
  private async prioritizeReceivingOpenings(force = false): Promise<void> {
    const owner = this.snapshot.sessionUserId;
    if (!owner || !this.snapshot.ready || !this.snapshot.online || !this.client) return;
    return this.receivingOpenings.run(owner, force);
  }
  addMedia(uri: string, bucket: Bucket): Promise<string> {
    const work = this.persistMedia(uri,bucket);
    this.mediaWork.add(work);
    void work.finally(() => this.mediaWork.delete(work)).catch(() => undefined);
    return work;
  }
  addDocument(uri: string, name: string, mimeType?: string): Promise<string> {
    const work = this.persistDocument(uri, name, mimeType);
    this.mediaWork.add(work);
    void work.finally(() => this.mediaWork.delete(work)).catch(() => undefined);
    return work;
  }
  private async persistDocument(uri: string, name: string, mimeType?: string): Promise<string> {
    this.actor();
    if (!this.snapshot.sessionUserId) throw new Error('Entre com a conta do dispositivo.');
    const type = documentType(name, mimeType), id = Crypto.randomUUID();
    const info = await FileSystem.getInfoAsync(uri);
    if (!info.exists || !info.size) throw new Error('O arquivo está vazio ou indisponível.');
    if (info.size > MAX_DOCUMENT_BYTES) throw new Error('O arquivo deve ter até 20 MB.');
    const destination = `${mediaDirectory}${id}.${type.extension}`;
    await FileSystem.copyAsync({ from: uri, to: destination });
    await this.database.write(async db => {
      await db.runAsync('INSERT INTO local_media_upload_queue(id,bucket,local_uri,remote_path,created_at,mime_type,file_name) VALUES (?,?,?,?,?,?,?)', id, 'rm-documentos', destination, `${this.snapshot.sessionUserId}/${id}.${type.extension}`, timestamp(), type.mimeType, name);
      await db.runAsync('INSERT INTO local_queue_meta(id) VALUES (?)', id);
    });
    await this.database.saveLocal(`document:${destination}`, { name, mimeType: type.mimeType });
    await this.refreshCounts();
    this.scheduleSync();
    return destination;
  }
  async documentInfo(uri: string): Promise<{name: string; mimeType?: string}> {
    return await this.database.local<{name: string; mimeType?: string}>(`document:${uri}`) ?? { name: documentFileName(uri) };
  }
  private async resolveDocumentUrl(uri: string): Promise<string> {
    const path = privateDocumentPath(uri, url);
    if (!path) return uri;
    const { data, error } = await this.supabase().storage.from('rm-documentos').createSignedUrl(path, 300);
    if (error || !data?.signedUrl) throw error ?? new Error('Não foi possível acessar o documento.');
    return data.signedUrl;
  }
  async getDocumentFile(uri: string): Promise<string> {
    const cached = await this.cachedMediaFile(uri);
    if (cached) return cached;
    if (!this.snapshot.online) throw new Error('Este documento ainda não foi baixado. Conecte uma vez para disponibilizá-lo offline.');
    if (!/^https:\/\//.test(uri)) throw new Error('Endereço de documento inválido.');
    if (scopedMedia) return this.downloadAuthorizedMedia(uri, true);
    const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, uri);
    const suffix = documentFileName(uri).match(/\.(pdf|png|jpe?g|docx?|xlsx?|txt|xml)$/i)?.[1] ?? 'pdf';
    const target = `${mediaDirectory}document-${hash}.${suffix}`;
    const result = await FileSystem.downloadAsync(await this.resolveDocumentUrl(uri), target);
    if (result.status < 200 || result.status >= 300) throw new Error('Não foi possível baixar o documento. Tente novamente com conexão.');
    await this.database.saveLocal(`media:${uri}`, target);
    const mimeType = result.headers?.['Content-Type'] ?? result.headers?.['content-type'];
    await this.database.saveLocal(`document:${target}`, { name: documentFileName(uri), mimeType: mimeType?.split(';')[0] });
    this.update({});
    return target;
  }
  private async persistMedia(uri: string, bucket: Bucket): Promise<string> {
    this.actor();
    if (!this.snapshot.sessionUserId) throw new Error('A sessão do dispositivo é obrigatória.');
    const id = Crypto.randomUUID(), signature = bucket === 'rm-assinaturas';
    const destination = `${mediaDirectory}${id}.${signature ? 'png' : 'jpg'}`;
    let input = uri;
    if (/^data:image\/png;base64,/.test(uri)) {
      await FileSystem.writeAsStringAsync(destination, uri.split(',')[1], { encoding: FileSystem.EncodingType.Base64 });
      input = destination;
    } else if (signature) await FileSystem.copyAsync({ from: input, to: destination });
    if (!signature) {
      const size = await new Promise<{width: number; height: number}>((resolve, reject) => Image.getSize(input, (width, height) => resolve({ width, height }), reject));
      const actions = Math.max(size.width, size.height) > 1800
        ? [{ resize: size.width >= size.height ? { width: 1800 } : { height: 1800 } }] : [];
      const image = await ImageManipulator.manipulateAsync(input, actions, { compress: 0.78, format: ImageManipulator.SaveFormat.JPEG });
      await FileSystem.copyAsync({ from: image.uri, to: destination });
    }
    const info = await FileSystem.getInfoAsync(destination);
    if (!info.exists || !info.size) throw new Error('Não foi possível salvar a mídia no dispositivo.');
    if (info.size > (signature ? 5 : 15) * 1024 * 1024) throw new Error('A mídia excede o limite de tamanho.');
    await this.database.write(async db => {
      await db.runAsync('INSERT INTO local_media_upload_queue(id,bucket,local_uri,remote_path,created_at) VALUES (?,?,?,?,?)', id, bucket, destination, `${this.snapshot.sessionUserId}/${id}.${signature ? 'png' : 'jpg'}`, timestamp());
      await db.runAsync('INSERT INTO local_queue_meta(id) VALUES (?)', id);
    });
    await this.refreshCounts();
    this.scheduleSync();
    return destination;
  }
  private async operatorWorkshop() {
    const owner = this.snapshot.sessionUserId, actor = this.snapshot.operator?.operador_id, token = this.operatorToken;
    if (!owner || !actor || !token || this.identityBusy) throw new Error('Identifique o operador para confirmar a oficina.');
    const workshop = await secureStorage.getItem(`rm.workshop.device.${owner}`);
    const confirmed = await secureStorage.getItem(`rm.workshop.operator.${owner}.${actor}`);
    const assertCurrent = () => {
      if (!workshop || this.identityBusy || this.snapshot.sessionUserId !== owner
        || this.snapshot.operator?.operador_id !== actor || this.operatorToken !== token) throw new Error('O vínculo do operador com a oficina mudou.');
    };
    if (!workshop || workshop !== confirmed || workshop !== this.localWorkshop || await secureStorage.getItem(`rm.workshop.suspended.${owner}`)) {
      throw new Error('Confirme a oficina deste dispositivo e operador.');
    }
    assertCurrent();
    return { owner, actor, token, workshop, assertCurrent };
  }
  private async locateMedia(key: string) {
    const local = await this.database.local<string>(key);
    return local && (await FileSystem.getInfoAsync(local)).exists ? local : null;
  }
  async cachedMediaFile(uri: string): Promise<string | null> {
    if (!uri) return null;
    if (isLocalUri(uri)) return uri;
    if (!scopedMedia) return this.locateMedia(`media:${uri}`);
    const scope = await this.operatorWorkshop();
    const local = await this.locateMedia(workshopMediaCacheKey(scope.workshop, scope.actor, uri));
    scope.assertCurrent();
    return local;
  }
  private async mediaLinks(scope: Awaited<ReturnType<MobileService['operatorWorkshop']>>, urls: string[]) {
    const { data, error } = await this.supabase().auth.getSession();
    scope.assertCurrent();
    if (error || !data.session || data.session.user.id !== scope.owner) throw new Error('Renove a sessão para abrir o arquivo.');
    const links = await readWorkshopMedia({ deviceToken: data.session.access_token, operatorToken: scope.token, workshopId: scope.workshop }, urls, url);
    scope.assertCurrent();
    return links;
  }
  private async saveAuthorizedMedia(scope: Awaited<ReturnType<MobileService['operatorWorkshop']>>, reference: string, source: string, document = false) {
    const key = workshopMediaCacheKey(scope.workshop, scope.actor, reference);
    const existing = this.scopedDownloads.get(key);
    if (existing) return existing;
    const download = (async () => {
      const cached = await this.locateMedia(key) ?? await this.locateMedia(`media:${reference}`);
      scope.assertCurrent();
      if (cached) {
        await this.database.saveLocal(key, cached);
        scope.assertCurrent();
        return cached;
      }
      const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, key);
      const extension = document ? '.' + (documentFileName(reference).match(/\.(pdf|png|jpe?g|docx?|xlsx?|txt|xml)$/i)?.[1] ?? 'pdf') : '';
      const target = `${mediaDirectory}workshop-${hash}${extension}`;
      const result = await FileSystem.downloadAsync(source, target);
      if (result.status < 200 || result.status >= 300) {
        await FileSystem.deleteAsync(target, { idempotent: true });
        throw new Error('Não foi possível baixar o arquivo da oficina.');
      }
      scope.assertCurrent();
      if (document) {
        const mimeType = result.headers?.['Content-Type'] ?? result.headers?.['content-type'];
        await this.database.saveLocal(`document:${target}`, { name: documentFileName(reference), mimeType: mimeType?.split(';')[0] });
      }
      await this.database.saveLocal(key, target);
      scope.assertCurrent();
      return target;
    })().finally(() => this.scopedDownloads.delete(key));
    this.scopedDownloads.set(key, download);
    return download;
  }
  private async downloadAuthorizedMedia(reference: string, document = false) {
    const scope = await this.operatorWorkshop();
    const link = (await this.mediaLinks(scope, [reference])).get(reference);
    if (!link) throw new Error('Arquivo indisponível para este operador na oficina.');
    return this.saveAuthorizedMedia(scope, reference, link, document);
  }
  async getMediaUrl(uri: string): Promise<string> {
    const cached = await this.cachedMediaFile(uri);
    if (cached || !scopedMedia) return cached ?? uri;
    return uri && this.snapshot.online ? this.downloadAuthorizedMedia(uri) : '';
  }
  async sync(force = false): Promise<void> {
    const active = busySyncWithPriority(this.syncPromise, force, () => this.prioritizeReceivingOpenings(true));
    if (active) return active;
    if (!this.snapshot.ready || !this.snapshot.online || !this.client || !this.snapshot.sessionUserId) return;
    this.syncPromise = this.runSync(force).finally(() => { this.syncPromise = undefined; });
    return this.syncPromise;
  }
  private async runSync(force: boolean) {
    if (scopedOperatorCells && (!this.operatorToken || this.identityBusy)) return;
    this.update({ syncing: true, error: null });
    try {
      const { data, error } = await this.supabase().auth.getSession();
      if (error || !data.session) throw new Error('Renove o login do dispositivo para sincronizar. Os dados continuam salvos.');
      if (data.session.user.id !== await secureStorage.getItem('rm.device.owner')) throw new Error('A sessão pertence a outra conta.');
      await this.prioritizeReceivingOpenings(force).catch(() => undefined);
      await this.refreshOperatorPermissions();
      if (scopedOperatorCells && (!this.operatorToken || this.identityBusy)) return;
      let pushError: unknown;
      try { await uploadThenMutate(() => this.pushMedia(force), async () => {
        await this.syncReceivingDraft().catch(() => undefined);
        await this.pushMutations(force);
      }); }
      catch (error) {
        pushError = error;
        if (isConnectivityError(error)) this.update({ syncRecovery: nextSyncRecovery(this.snapshot.syncRecovery, { type: 'interrupted-send' }) });
      }
      // Sending and downloading catalogs are independent: hide recovery once sends are confirmed.
      await this.refreshCounts();
      // Pull remains useful while one invalid mutation waits for operator intervention.
      let catalogSession: CatalogSession | undefined;
      if (scopedCatalog) {
        const operatorToken = this.operatorToken;
        const workshopId = await secureStorage.getItem(`rm.workshop.device.${data.session.user.id}`);
        const operatorId = this.snapshot.operator?.operador_id;
        if (!operatorToken || !operatorId || !workshopId || this.operatorToken !== operatorToken) throw new Error('Identifique o operador antes de sincronizar o catálogo.');
        catalogSession = { deviceToken: data.session.access_token, operatorToken, operatorId, workshopId };
      }
      await this.pull(catalogSession);
      const at = timestamp();
      await this.database.saveLocal('last_sync', at);
      this.update({ lastSync: at });
      if (pushError) throw pushError;
    } catch (error) {
      if (isConnectivityError(error) && this.snapshot.pendingMedia + this.snapshot.pendingMutations > 0) {
        this.update({ syncRecovery: nextSyncRecovery(this.snapshot.syncRecovery, { type: 'interrupted-send' }) });
      }
      this.update({ error: errorText(error) });
      throw error;
    } finally { await this.refreshCounts(); this.update({ syncing: false }); }
  }
  private async scopeOperator(owner: string, operator: Operator, token: string, identifying = false) {
    const { data, error } = await this.supabase().auth.getSession();
    if (error || !data.session || data.session.user.id !== owner) throw Object.assign(new Error('Renove a sessão do dispositivo.'), { code: '28000' });
    const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 12_000);
    let scoped: Awaited<ReturnType<typeof readWorkshopOperatorCells>>;
    try { scoped = await readWorkshopOperatorCells(owner, data.session.access_token, operator, token, controller.signal, { androidBuild }); }
    finally { clearTimeout(timeout); }
    const pinKey = `rm.workshop.device.${owner}`;
    const suspendedKey = `rm.workshop.suspended.${owner}`;
    const baseKey = `rm.workshop.local-base.${owner}`;
    const pinned = await secureStorage.getItem(pinKey);
    const isCurrent = () => this.snapshot.sessionUserId === owner
      && (identifying ? this.identityBusy : !this.identityBusy && this.operatorToken === token);
    if (!isCurrent()) throw new Error('O operador mudou durante a confirmação da oficina.');

    const openedOffice = this.localWorkshop;
    if (openedOffice && openedOffice !== scoped.workshopId) {
      await secureStorage.setItem(suspendedKey, 'true');
      if (identifying && scopedCatalog && isCurrent()) {
        const base = await secureStorage.getItem(baseKey);
        workshopDatabaseName(scoped.workshopId, base ?? openedOffice);
        if (!base) await secureStorage.setItem(baseKey, openedOffice);
        await this.database.idle();
        if (!isCurrent()) throw new Error('O operador mudou durante a confirmação da oficina.');
        await secureStorage.setItem(pinKey, scoped.workshopId);
        // Never change SQLite while autosaves or acknowledgments can still target the open database.
        throw new WorkshopRestartRequired();
      }
      throw Object.assign(new Error('A oficina deste dispositivo mudou. Identifique-se com conexão para confirmar o novo vínculo.'), { code: '42501' });
    }
    if (pinned !== scoped.workshopId) {
      if (!identifying) throw Object.assign(new Error('Identifique-se para confirmar a oficina atual.'), { code: '42501' });
      await secureStorage.setItem(pinKey, scoped.workshopId);
    }
    this.localWorkshop = scoped.workshopId;
    await secureStorage.removeItem(suspendedKey);
    return scoped;
  }
  private async forgetWorkshopOperator(owner: string, operator: Operator) {
    await secureStorage.removeItem(`rm.workshop.operator.${owner}.${operator.operador_id}`);
    await forgetCachedIdentity(operator.matricula);
  }
  private async refreshOperatorPermissions() {
    const operator = this.snapshot.operator, token = this.operatorToken, owner = this.snapshot.sessionUserId;
    if (!operator || !token || !owner || this.identityBusy) return;
    const { data, error } = await this.supabase().rpc('rm_operator_context_v1', { p_operator_token: token });
    // A response for a previous operator must never replace the current identity.
    if (this.operatorToken !== token || this.snapshot.operator?.operador_id !== operator.operador_id) return;
    if (error) {
      if (['28000', '42501'].includes(error.code)) {
        this.operatorToken = null;
        this.update({ operator: null });
        if (scopedOperatorCells) await this.forgetWorkshopOperator(owner, operator);
        else await forgetCachedIdentity(operator.matricula);
      }
      throw error;
    }
    let refreshed = applyOperatorContext(operator, data as Operator);
    if (scopedOperatorCells) {
      try { refreshed = (await this.scopeOperator(owner, refreshed, token)).operator; }
      catch (failure) {
        if (this.operatorToken === token && this.snapshot.operator?.operador_id === operator.operador_id && operatorWorkshopDenied(failure)) {
          this.operatorToken = null;
          this.update({ operator: null });
          await this.forgetWorkshopOperator(owner, operator);
        }
        throw failure;
      }
      if (this.operatorToken !== token || this.snapshot.operator?.operador_id !== operator.operador_id) return;
    }
    await refreshCachedIdentity(refreshed, token, owner);
    await this.database.write(db => db.runAsync(
      'UPDATE local_operator_session SET perfil=?,perfil_assinante_json=?,celulas_vinculadas_json=? WHERE operador_id=?',
      refreshed.perfil, JSON.stringify(refreshed.perfil_assinante ?? []), JSON.stringify(refreshed.celulas_vinculadas), refreshed.operador_id,
    ));
    if (this.operatorToken === token && this.snapshot.operator?.operador_id === operator.operador_id) this.update({ operator: refreshed });
  }
  private async mediaReadyToSend() {
    const scope = await this.operatorWorkshop().catch(() => null);
    const queue = scope ? (await this.pendingQueue()).filter(row => queueMatchesWorkshop(row, scope)) : [];
    const intents = queuedMediaIntents(queue);
    const actor = scope?.actor;
    const entry = actor ? await this.readReceivingEntry(this.database.connection(), actor) : null;
    scope?.assertCurrent();
    const draft = scopedDraftMedia && entry && !entry.data.submitted ? entry : null;
    const cloudDraft = new Set(draft ? [draft.data.arquivoNotaFiscal, ...draft.data.fotos.map(photo => photo.uri)] : []);
    const waitsForReceiving = queue.some(row => row.rpc_name === 'rm_submit_recebimento_v1' && row.actor_id === actor);
    return { intents, scope, draft, waitsForReceiving, included: (uri: string) => intents.has(uri) || cloudDraft.has(uri) };
  }
  private async resolveScopedMediaTransfer(row: MediaRow, scope: QueueScope & { token: string; assertCurrent(): void },
    intent?: MediaIntent, draft?: ReceivingDraftEntry | null): Promise<AuthorizedMediaTransfer> {
    scope.assertCurrent();
    if (intent) {
      const transfer = queuedWorkshopMediaTransfer(intent, scope, row.local_uri, scopedDraftMedia);
      const operatorToken = await secureStorage.getItem(intent.row.token_key);
      scope.assertCurrent();
      if (!operatorToken) throw new Error('Identifique o operador do protocolo original para enviar o arquivo.');
      return { ...transfer, workshopOrigin: scope.workshop, operatorToken };
    }
    if (scopedDraftMedia && !intent && draft) {
      await this.assertReceivingDraftOrigin(scope.actor, draft);
      scope.assertCurrent();
      const kind = row.local_uri === draft.data.arquivoNotaFiscal ? 'document' : 'photo';
      return { ...receivingMediaTransfer(draft.data.id, scope.actor, draft.data.cliente, draft.data.projeto_id, row.local_uri, kind),
        workshopOrigin: scope.workshop, operatorToken: scope.token };
    }
    throw new Error('Confirme a oficina e o operador do arquivo. O envio continua salvo no dispositivo.');
  }
  private async uploadScopedMedia(row: MediaRow, transfer: AuthorizedMediaTransfer, scope: { owner: string; assertCurrent(): void }, file: Uint8Array): Promise<string> {
    const { data, error } = await this.supabase().auth.getSession();
    if (error || data.session?.user.id !== scope.owner) {
      throw new Error('Identifique novamente o operador do protocolo original para enviar o arquivo.');
    }
    const mime = mediaUploadMime(row.bucket, row.mime_type);
    const digest = new Uint8Array(await Crypto.digest(Crypto.CryptoDigestAlgorithm.SHA256, new Uint8Array(file)));
    const sha256 = Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('');
    const name = row.remote_path.split('/').at(-1) || row.id;
    const attachment = { uri: row.local_uri, name, type: mime } as unknown as Blob;
    scope.assertCurrent();
    return sendWorkshopMediaUpload({ ...transfer, deviceToken: data.session.access_token, asset: row.id,
      reference: row.local_uri, mime, size: file.byteLength, sha256 }, attachment, url);
  }
  private async uploadLegacyMedia(row: MediaRow, file: Uint8Array) {
    const bucket = this.supabase().storage.from(row.bucket);
    const { error } = await bucket.upload(row.remote_path, file, { contentType: row.mime_type || (row.bucket === 'rm-assinaturas' ? 'image/png' : 'image/jpeg'), upsert: true });
    if (error) throw error;
    return row.bucket === 'rm-documentos' ? `${url}/storage/v1/object/authenticated/rm-documentos/${row.remote_path}` : bucket.getPublicUrl(row.remote_path).data.publicUrl;
  }
  private async pushMedia(force: boolean) {
    const rows = await this.database.connection().getAllAsync<MediaRow>(`SELECT q.*,m.next_retry_at FROM local_media_upload_queue q JOIN local_queue_meta m USING(id) WHERE q.status<>'uploaded' ORDER BY q.created_at,q.rowid`);
    const selection = scopedUploads ? await this.mediaReadyToSend() : null;
    for (const row of rows) {
      if (selection && (!selection.scope || !selection.included(row.local_uri))) continue;
      selection?.scope?.assertCurrent();
      const intent = selection?.intents.get(row.local_uri);
      if (scopedDraftMedia && !intent && selection?.draft && (selection.waitsForReceiving
        || !selection.draft.data.cliente && !selection.draft.data.projeto_id)) continue;
      if (!force && row.next_retry_at > Date.now()) throw new Error('Envio de mídia aguardando nova tentativa automática.');
      await this.database.write(db => db.runAsync("UPDATE local_media_upload_queue SET status='uploading' WHERE id=?", row.id));
      try {
        const base64 = await FileSystem.readAsStringAsync(row.local_uri, { encoding: FileSystem.EncodingType.Base64 });
        const bytes = decodeBase64(base64);
        let transfer: AuthorizedMediaTransfer | undefined;
        let remoteUrl: string;
        if (selection?.scope) {
          transfer = await this.resolveScopedMediaTransfer(row, selection.scope, intent, selection.draft);
          remoteUrl = await this.uploadScopedMedia(row, transfer, selection.scope, bytes);
        } else remoteUrl = await this.uploadLegacyMedia(row, bytes);
        await this.database.write(db => db.runAsync("UPDATE local_media_upload_queue SET status='uploaded',public_url=?,last_error=NULL WHERE id=?", remoteUrl, row.id));
        await this.database.saveLocal(`media:${remoteUrl}`, row.local_uri);
        if (transfer?.operation === 'receiving_draft' && typeof transfer.payload.p_operador_id === 'string') {
          await this.database.saveLocal(workshopMediaCacheKey(transfer.workshopOrigin, transfer.payload.p_operador_id, remoteUrl), row.local_uri);
        }
      } catch (error) {
        await this.fail('local_media_upload_queue', row.id, row.attempts, error);
        throw error;
      }
    }
  }
  private async pushMutations(force: boolean) {
    const owner = this.snapshot.sessionUserId;
    if (!owner) throw new Error('A sessão do dispositivo não está disponível.');
    const media = await this.database.connection().getAllAsync<{local_uri: string; public_url: string}>("SELECT local_uri,public_url FROM local_media_upload_queue WHERE status='uploaded'");
    const uploaded = new Map(media.map(m => [m.local_uri, m.public_url]));
    const scope = scopedCatalog ? await this.operatorWorkshop() : null;
    const queue = await this.pendingQueue();
    for (const row of queue) {
      if (scope && !queueMatchesWorkshop(row, scope)) continue;
      scope?.assertCurrent();
      if (!force && row.next_retry_at > Date.now()) throw new Error('Uma operação aguarda nova tentativa automática.');
      await this.database.write(db => db.runAsync("UPDATE local_rpc_outbox SET status='syncing' WHERE id=?", row.id));
      try {
        const token = await secureStorage.getItem(row.token_key);
        if (!token) throw new Error('Identifique novamente o operador responsável para autorizar o envio.');
        scope?.assertCurrent();
        // Execution has no media fields. A free-text note beginning with file:
        // remains text and must not become a missing-upload dependency.
        const raw = JSON.parse(row.params_json);
        const params = row.rpc_name === EXECUTION_RPC ? raw : replaceMedia(raw, uploaded);
        const data = scopedReceiving && row.rpc_name === 'rm_submit_recebimento_v1'
          ? await this.completeScopedReceiving(owner, row, params, token)
          : await this.sendMutation(row, params, token);
        if (row.rpc_name === EXECUTION_RPC) {
          const receipt = parseExecutionReceipt(data);
          if (receipt.event_id !== row.id || receipt.session_id !== raw.p_session_id) throw new Error('Não foi possível confirmar o protocolo do apontamento. O envio foi preservado para nova tentativa.');
        }
        await this.database.write(async db => {
          if (row.rpc_name === EXECUTION_RPC) await storeExecutionAck(db, owner, row.actor_id, row.id, parseExecutionReceipt(data));
          else {
            await db.runAsync("UPDATE local_rpc_outbox SET status='completed',last_error=NULL WHERE id=?", row.id);
            await db.runAsync('UPDATE local_queue_meta SET result_json=? WHERE id=?', JSON.stringify(data), row.id);
          }
          if (row.draft_id) await db.runAsync("UPDATE local_form_drafts SET status='synced' WHERE draft_id=?", row.draft_id);
          if (row.rpc_name === 'rm_submit_recebimento_v1') {
            const receiving = await this.readReceivingEntry(db, row.actor_id);
            if (receiving?.data.id === row.id) {
              await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', `recebimento:${row.actor_id}`, JSON.stringify({ ...receiving.data, submitted: true }));
              await db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', `receiving-sync:${row.actor_id}`, JSON.stringify({ ...receiving.meta, state: 'finalized', pending: undefined, error: undefined, result: data }));
            }
          }
        });
        await secureStorage.removeItem(row.token_key).catch(() => undefined);
      } catch (error) {
        if (row.rpc_name === EXECUTION_RPC) {
          const fenced = await this.database.write(db => storeExecutionFailure(db, { owner, actor: row.actor_id, eventId: row.id, error, message: errorText(error), nextRetryAt: Date.now() + retryDelay(row.attempts + 1) }));
          if (fenced) this.update({});
        } else await this.fail('local_rpc_outbox', row.id, row.attempts, error);
        throw error; // Strict FIFO: later RPCs cannot overtake this operation.
      }
    }
  }

  private async sendMutation(row: OutboxRow, params: Record<string, unknown>, token: string) {
    if (scopedMutations && row.rpc_name !== 'rm_submit_recebimento_v1') {
      const { data, error } = await this.supabase().auth.getSession();
      if (error || !data.session || data.session.user.id !== this.snapshot.sessionUserId) {
        throw new Error('Renove a sessão original do dispositivo. O registro permanece na fila.');
      }
      return sendWorkshopMutation({ deviceToken: data.session.access_token, operatorToken: token,
        submission: row.id, operation: row.rpc_name, payload: params, workshopOrigin: row.workshop_id ?? undefined });
    }
    const { data, error } = await this.supabase().rpc('rm_mobile_mutate_v1', {
      p_client_submission_id: row.id, p_rpc_name: row.rpc_name, p_params: params, p_operator_token: token,
    });
    if (error) throw error;
    return data;
  }

  private async completeScopedReceiving(owner: string, row: OutboxRow, payload: Record<string, unknown>, operatorToken: string) {
    const { data, error } = await this.supabase().auth.getSession();
    if (error || data.session?.user.id !== owner || this.snapshot.sessionUserId !== owner) {
      throw new Error('Renove a sessão do dispositivo original. O recebimento permanece salvo.');
    }
    const controller = new AbortController(), timeout = setTimeout(() => controller.abort(), 20_000);
    try {
      const response = await sendScopedReceiving({ deviceToken: data.session.access_token, operatorToken, submission: row.id, phase: 'complete',
        payload, workshopOrigin: row.workshop_id ?? undefined }, controller.signal);
      if (this.snapshot.sessionUserId !== owner) throw new Error('A conta mudou durante o recebimento. O protocolo original permanece salvo.');
      return response;
    } finally { clearTimeout(timeout); }
  }

  private async fail(table: 'local_rpc_outbox' | 'local_media_upload_queue', id: string, attempts: number, error: unknown) {
    await this.database.write(async db => {
      await db.runAsync(`UPDATE ${table} SET status='failed',attempts=attempts+1,last_error=? WHERE id=?`, errorText(error), id);
      await db.runAsync('UPDATE local_queue_meta SET next_retry_at=? WHERE id=?', Date.now() + retryDelay(attempts + 1), id);
    });
  }
  private async pull(scope?: CatalogSession) {
    try {
    for (const table of TABLES) {
      if (scope) {
        await this.pullWorkshopCatalog(table, scope);
        continue;
      }
      const cursor = await this.database.local<string>(`cursor:${table}`);
      let after: {at: string; id: string} | null = cursor ? { at: new Date(Date.parse(cursor) - 1000).toISOString(), id: '00000000-0000-0000-0000-000000000000' } : null;
      let latest = cursor;
      for (;;) {
        let query = this.supabase().from(table).select('*').order('updated_at').order('id').limit(250);
        if (table === 'rm_projetos') {
          // This schema has no `ativo`; delivered/cancelled projects leave the operational catalog.
          query = query.is('data_real_de_entrega', null).or(after
            ? `and(or(status_pcp.not.in.(cancelado,finalizando_para_faturar),status_pcp.is.null),or(updated_at.gt.${after.at},and(updated_at.eq.${after.at},id.gt.${after.id})))`
            : 'status_pcp.not.in.(cancelado,finalizando_para_faturar),status_pcp.is.null');
        } else if (after) query = query.or(`updated_at.gt.${after.at},and(updated_at.eq.${after.at},id.gt.${after.id})`);
        const { data, error } = await query;
        if (error) throw error;
        const rows = (data ?? []) as Row[];
        if (!rows.length) break;
        await this.database.cache(table, rows);
        for (const record of rows) await this.cacheRecordMedia(table, record);
        const last = rows[rows.length - 1];
        after = { at: last.updated_at, id: last.id }; latest = last.updated_at;
        if (rows.length < 250) break;
      }
      if (latest) await this.database.saveLocal(`cursor:${table}`, latest);
      const reconciled = await this.database.local<number>(`reconciled:${table}`) ?? 0;
      if (table === 'rm_projetos' || Date.now() - reconciled > 15 * 60_000) await this.reconcile(table);
    }
    await this.downloadPendingMedia();
    } finally {
      // A partially successful pull also exposes its durable rows after a later failure.
      this.catalogRevision++;
      this.update({});
    }
  }
  private async pullWorkshopCatalog(table: CatalogTable, scope: CatalogSession) {
    const personal = operatorScopedCatalogTable(table);
    const partition = personal ? `${scope.workshopId}:${scope.operatorId}` : scope.workshopId;
    const cursorKey = `workshop-cursor:${partition}:${table}`;
    const reconcileKey = `workshop-reconciled:${partition}:${table}`;
    const cursor = await this.database.local<CatalogCursor>(cursorKey);
    let after = cursor ? { at: new Date(Date.parse(cursor.at) - 1000).toISOString(), id: '00000000-0000-0000-0000-000000000000' } : null;
    let latest = cursor;
    const verifyOperator = () => {
      if (this.operatorToken !== scope.operatorToken) throw new Error('O operador mudou durante a sincronização do catálogo.');
    };
    for (;;) {
      const { rows, complete } = await readWorkshopCatalogPage(scope, table, after, false);
      verifyOperator();
      if (rows.length) {
        await this.database.cache(table, rows);
        for (const row of rows) await this.cacheRecordMedia(table, row, scope);
        const last = rows[rows.length - 1];
        if (last.id === after?.id && last.updated_at === after.at) throw new Error('O catálogo devolveu a mesma posição de sincronização.');
        after = { at: last.updated_at, id: last.id };
        latest = after;
      }
      if (complete) break;
    }
    verifyOperator();
    if (latest) await this.database.saveLocal(cursorKey, latest);
    const lastReconciled = await this.database.local<number>(reconcileKey) ?? 0;
    if (table !== 'rm_projetos' && Date.now() - lastReconciled <= 15 * 60_000) return;

    const ids = new Set<string>();
    after = null;
    for (;;) {
      const { rows, complete } = await readWorkshopCatalogPage(scope, table, after, true);
      verifyOperator();
      for (const row of rows) {
        if (ids.has(row.id)) throw new Error('O catálogo devolveu um identificador repetido.');
        ids.add(row.id);
      }
      if (complete) break;
      const last = rows[rows.length - 1];
      after = { at: last.updated_at, id: last.id };
    }
    if (personal) await this.database.saveLocal(operatorCatalogKey(scope.workshopId, scope.operatorId, table), [...ids]);
    else await this.database.removeMissing(table, ids);
    await this.database.saveLocal(reconcileKey, Date.now());
  }
  private async reconcile(table: CatalogTable) {
    // Lightweight ID manifests remove hard-deleted records without deleting any drafts/outbox.
    const ids = new Set<string>(); let after = '';
    for (;;) {
      let query = this.supabase().from(table).select('id').order('id').limit(1000);
      if (table === 'rm_projetos') query = query.is('data_real_de_entrega', null).or('status_pcp.not.in.(cancelado,finalizando_para_faturar),status_pcp.is.null');
      if (after) query = query.gt('id', after);
      const { data, error } = await query;
      if (error) throw error;
      for (const row of data ?? []) ids.add(row.id);
      if (!data?.length || data.length < 1000) break;
      after = data[data.length - 1].id;
    }
    await this.database.removeMissing(table, ids);
    await this.database.saveLocal(`reconciled:${table}`, Date.now());
  }
  private async cacheRecordMedia(table: CatalogTable, record: Row, scope?: CatalogSession) {
    const urls: string[] = table === 'rm_fotos' ? [record.foto_url] : table === 'rm_respostas' ? [...(record.fotos_urls ?? []), record.assinatura_url] : [];
    // Documents are downloaded on demand; their metadata stays available offline.
    for (const uri of urls.filter(u => typeof u === 'string' && /^https:\/\//.test(u))) {
      const key = scopedMedia && scope ? workshopMediaCacheKey(scope.workshopId, scope.operatorId, uri) : `media:${uri}`;
      if (await this.database.local(key)) continue;
      const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, uri);
      const target = `${mediaDirectory}cache-${hash}`;
      await this.database.write(db => db.runAsync('INSERT OR IGNORE INTO local_media_download_queue(url,local_uri) VALUES (?,?)', uri, target));
    }
  }
  private async downloadPendingMedia() {
    const pending = await this.database.connection().getAllAsync<{url: string; local_uri: string}>(
      `SELECT * FROM local_media_download_queue LIMIT ${scopedMedia ? 25 : 50}`);
    const scope = scopedMedia && pending.length ? await this.operatorWorkshop() : null;
    let links: Promise<Map<string, string>> | undefined;
    const pause = await prefetchWithSpaceReserve(pending, () => FileSystem.getFreeDiskStorageAsync(), async item => {
      try {
        if (scope) {
          links ??= this.mediaLinks(scope, pending.map(media => media.url));
          const resolved = await links;
          scope.assertCurrent();
          const source = resolved.get(item.url);
          if (source) await this.saveAuthorizedMedia(scope, item.url, source);
        } else {
          const result = await FileSystem.downloadAsync(item.url, item.local_uri);
          if (result.status < 200 || result.status >= 300) return;
          await this.database.saveLocal(`media:${item.url}`, item.local_uri);
        }
        await this.database.write(db => db.runAsync('DELETE FROM local_media_download_queue WHERE url=?', item.url));
      } catch { /* Durable download queue retries on the next synchronization. */ }
    });
    const mediaCacheNotice = pause === 'low_space'
      ? 'Pouco espaço no dispositivo: o download automático de fotos foi pausado para preservar espaço para novas atividades. Os arquivos existentes e os envios pendentes foram mantidos.'
      : pause === 'space_unavailable'
        ? 'Não foi possível verificar o espaço do dispositivo. O download automático de fotos foi pausado; os arquivos existentes e os envios pendentes foram mantidos.'
        : null;
    if (mediaCacheNotice !== this.snapshot.mediaCacheNotice) this.update({ mediaCacheNotice });
  }
  private async refreshCounts(restoring = false) {
    const db = this.database.connection();
    const counts = await db.getFirstAsync<{pendingMedia: number; pendingMutations: number}>(`SELECT
      (SELECT count(*) FROM local_media_upload_queue WHERE status<>'uploaded') AS pendingMedia,
      (SELECT count(*) FROM local_rpc_outbox WHERE status<>'completed') AS pendingMutations`);
    let pendingMedia = counts?.pendingMedia ?? 0;
    const pendingMutations = scopedCatalog ? (await this.listQueue().catch(() => [])).length : counts?.pendingMutations ?? 0;
    if (scopedUploads && pendingMedia) {
      const selection = await this.mediaReadyToSend().catch(() => null);
      const candidates = await db.getAllAsync<{ local_uri: string }>("SELECT local_uri FROM local_media_upload_queue WHERE status<>'uploaded'");
      pendingMedia = candidates.filter(row => selection?.included(row.local_uri)).length;
    }
    this.update({ pendingMedia, pendingMutations, syncRecovery: nextSyncRecovery(this.snapshot.syncRecovery, {
      type: 'queue', online: this.snapshot.online, pendingMedia, pendingMutations, restoring: restoring || !this.snapshot.ready,
    }) });
  }
}

export const service = new MobileService();
