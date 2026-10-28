import 'react-native-url-polyfill/auto';
import { AppState, Image } from 'react-native';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import NetInfo from '@react-native-community/netinfo';
import * as Crypto from 'expo-crypto';
import * as FileSystem from 'expo-file-system/legacy';
import * as ImageManipulator from 'expo-image-manipulator';
import { LocalDatabase } from './database';
import { cacheIdentity, forgetCachedIdentity, offlineIdentity, refreshCachedIdentity, secureStorage } from './secure';
import { applyOperatorContext } from './operator-policy';
import { documentFileName, documentType, MAX_DOCUMENT_BYTES, privateDocumentPath } from './document-policy';
import { prefetchWithSpaceReserve } from './media-cache-policy';
import { knownConnection, nextSyncRecovery } from './sync-recovery';
import { canonicalJson, decodeBase64, isConnectivityError, isLocalUri, replaceMedia, retryDelay, uploadThenMutate, validateAnswers } from './sync-policy';
import { TABLES, RPC_NAMES, type Answer, type AppSnapshot, type Bucket, type CatalogFilter, type CatalogTable, type Draft, type DraftContext, type MediaRow, type Operator, type OutboxRow, type Row, type RpcName } from './types';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '';
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
  private debounce?: ReturnType<typeof setTimeout>;
  private identityBusy = false;
  private mediaWork = new Set<Promise<string>>();
  private catalogRevision = 0;

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
    await this.database.initialize();
    await FileSystem.makeDirectoryAsync(mediaDirectory, { intermediates: true });
    const owner = await secureStorage.getItem('rm.device.owner');
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
        else this.client?.auth.stopAutoRefresh();
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
        await cacheIdentity(identity.operator, identity.token, password, owner);
        } catch (error) {
          if (!isConnectivityError(error)) throw error;
          identity = await offlineIdentity(matricula,password,owner);
        }
      } else identity = await offlineIdentity(matricula, password, owner);
      this.operatorToken = identity.token;
      this.update({ operator: identity.operator, error: null });
      await this.database.write(async db => {
        const o = identity.operator;
        await db.runAsync(`INSERT INTO local_operator_session(operador_id,matricula,nome,cargo,perfil,perfil_assinante_json,equipe_id,celulas_vinculadas_json,authenticated_at)
          VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(operador_id) DO UPDATE SET nome=excluded.nome,perfil=excluded.perfil,perfil_assinante_json=excluded.perfil_assinante_json,celulas_vinculadas_json=excluded.celulas_vinculadas_json,authenticated_at=excluded.authenticated_at`,
          o.operador_id, o.matricula, o.nome, o.cargo ?? null, o.perfil, JSON.stringify(o.perfil_assinante ?? []), o.equipe_id ?? null, JSON.stringify(o.celulas_vinculadas ?? []), o.authenticated_at);
      });
      // Refresh only this actor's queued grants. Other operators retain their original attribution.
      const pending = await this.listQueue();
      for (const item of pending) if (item.actor_id === identity.operator.operador_id) {
        await secureStorage.setItem(item.token_key, identity.token);
      }
      this.scheduleSync();
    } finally { this.identityBusy = false; }
  }
  async switchOperator() {
    await Promise.allSettled([...this.mediaWork]);
    await this.database.idle();
    this.operatorToken = null; this.update({ operator: null, error: null });
  }
  list = (table: string, filter?: CatalogFilter) => this.database.list(table, filter);
  get = (table: string, id: string) => this.database.get(table, id);
  getLocal = <T = unknown>(key: string) => this.database.local<T>(key);
  async saveLocal(key: string, value: unknown) { await this.database.saveLocal(key, value); this.update({}); }
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
  async enqueue(rpc: RpcName, params: Record<string, unknown>, id = Crypto.randomUUID(), draftId?: string) {
    if (!(RPC_NAMES as readonly string[]).includes(rpc)) throw new Error('Operação não permitida.');
    const actor = this.actor(), tokenKey = `rm.operation.${id}`, token = this.operatorToken!;
    const payload = {...params,p_operador_id:actor.operador_id};
    await this.database.write(async db => {
      const already = await db.getFirstAsync<{id: string; rpc_name: string; params_json: string}>('SELECT id,rpc_name,params_json FROM local_rpc_outbox WHERE id=?', id);
      if (already) {
        if (already.rpc_name !== rpc || canonicalJson(JSON.parse(already.params_json)) !== canonicalJson(payload)) throw new Error('Este protocolo já foi enviado com outros dados. Consulte o envio antes de alterar o registro.');
        return;
      }
      await secureStorage.setItem(tokenKey,token);
      await db.runAsync(`INSERT INTO local_rpc_outbox(id,rpc_name,params_json,created_at) VALUES (?,?,?,?)`, id, rpc, JSON.stringify(payload), timestamp());
      await db.runAsync('INSERT INTO local_queue_meta(id,actor_id,token_key,draft_id) VALUES (?,?,?,?)', id, actor.operador_id, tokenKey, draftId ?? null);
      if (draftId) await db.runAsync("UPDATE local_form_drafts SET status='ready_to_sync' WHERE draft_id=?", draftId);
    });
    await this.refreshCounts();
    this.scheduleSync();
    return id;
  }
  async listQueue(): Promise<OutboxRow[]> {
    return this.database.connection().getAllAsync<OutboxRow>(`SELECT o.*,m.next_retry_at,m.actor_id,m.token_key,m.draft_id,m.result_json FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE status<>'completed' ORDER BY o.created_at,o.rowid`);
  }
  async operation(id: string): Promise<(OutboxRow & { result?: unknown }) | null> {
    const row = await this.database.connection().getFirstAsync<OutboxRow>('SELECT o.*,m.next_retry_at,m.actor_id,m.token_key,m.draft_id,m.result_json FROM local_rpc_outbox o JOIN local_queue_meta m USING(id) WHERE o.id=?', id);
    return row ? { ...row, result: row.result_json ? JSON.parse(row.result_json) : undefined } : null;
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
    const cached = await this.getMediaUrl(uri);
    if (isLocalUri(cached)) return cached;
    if (!this.snapshot.online) throw new Error('Este documento ainda não foi baixado. Conecte uma vez para disponibilizá-lo offline.');
    if (!/^https:\/\//.test(uri)) throw new Error('Endereço de documento inválido.');
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
    return destination;
  }
  async getMediaUrl(uri: string): Promise<string> {
    if (!uri || isLocalUri(uri)) return uri;
    const local = await this.database.local<string>(`media:${uri}`);
    if (local && (await FileSystem.getInfoAsync(local)).exists) return local;
    return uri;
  }
  async sync(force = false): Promise<void> {
    if (this.syncPromise) return this.syncPromise;
    if (!this.snapshot.ready || !this.snapshot.online || !this.client || !this.snapshot.sessionUserId) return;
    this.syncPromise = this.runSync(force).finally(() => { this.syncPromise = undefined; });
    return this.syncPromise;
  }
  private async runSync(force: boolean) {
    this.update({ syncing: true, error: null });
    try {
      const { data, error } = await this.supabase().auth.getSession();
      if (error || !data.session) throw new Error('Renove o login do dispositivo para sincronizar. Os dados continuam salvos.');
      if (data.session.user.id !== await secureStorage.getItem('rm.device.owner')) throw new Error('A sessão pertence a outra conta.');
      await this.refreshOperatorPermissions();
      let pushError: unknown;
      try { await uploadThenMutate(() => this.pushMedia(force), () => this.pushMutations(force)); }
      catch (error) {
        pushError = error;
        if (isConnectivityError(error)) this.update({ syncRecovery: nextSyncRecovery(this.snapshot.syncRecovery, { type: 'interrupted-send' }) });
      }
      // Sending and downloading catalogs are independent: hide recovery once sends are confirmed.
      await this.refreshCounts();
      // Pull remains useful while one invalid mutation waits for operator intervention.
      await this.pull();
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
        await forgetCachedIdentity(operator.matricula);
      }
      throw error;
    }
    const refreshed = applyOperatorContext(operator, data as Operator);
    await refreshCachedIdentity(refreshed, token, owner);
    await this.database.write(db => db.runAsync(
      'UPDATE local_operator_session SET perfil=?,perfil_assinante_json=?,celulas_vinculadas_json=? WHERE operador_id=?',
      refreshed.perfil, JSON.stringify(refreshed.perfil_assinante ?? []), JSON.stringify(refreshed.celulas_vinculadas), refreshed.operador_id,
    ));
    if (this.operatorToken === token && this.snapshot.operator?.operador_id === operator.operador_id) this.update({ operator: refreshed });
  }
  private async pushMedia(force: boolean) {
    const rows = await this.database.connection().getAllAsync<MediaRow>(`SELECT q.*,m.next_retry_at FROM local_media_upload_queue q JOIN local_queue_meta m USING(id) WHERE q.status<>'uploaded' ORDER BY q.created_at,q.rowid`);
    for (const row of rows) {
      if (!force && row.next_retry_at > Date.now()) throw new Error('Envio de mídia aguardando nova tentativa automática.');
      await this.database.write(db => db.runAsync("UPDATE local_media_upload_queue SET status='uploading' WHERE id=?", row.id));
      try {
        const base64 = await FileSystem.readAsStringAsync(row.local_uri, { encoding: FileSystem.EncodingType.Base64 });
        const { error } = await this.supabase().storage.from(row.bucket).upload(row.remote_path, decodeBase64(base64), { contentType: row.mime_type || (row.bucket === 'rm-assinaturas' ? 'image/png' : 'image/jpeg'), upsert: true });
        if (error) throw error;
        const { data } = this.supabase().storage.from(row.bucket).getPublicUrl(row.remote_path);
        const remoteUrl = row.bucket === 'rm-documentos' ? `${url}/storage/v1/object/authenticated/rm-documentos/${row.remote_path}` : data.publicUrl;
        await this.database.write(db => db.runAsync("UPDATE local_media_upload_queue SET status='uploaded',public_url=?,last_error=NULL WHERE id=?", remoteUrl, row.id));
        await this.database.saveLocal(`media:${remoteUrl}`, row.local_uri);
      } catch (error) {
        await this.fail('local_media_upload_queue', row.id, row.attempts, error);
        throw error;
      }
    }
  }
  private async pushMutations(force: boolean) {
    const media = await this.database.connection().getAllAsync<{local_uri: string; public_url: string}>("SELECT local_uri,public_url FROM local_media_upload_queue WHERE status='uploaded'");
    const uploaded = new Map(media.map(m => [m.local_uri, m.public_url]));
    for (const row of await this.listQueue()) {
      if (!force && row.next_retry_at > Date.now()) throw new Error('Uma operação aguarda nova tentativa automática.');
      await this.database.write(db => db.runAsync("UPDATE local_rpc_outbox SET status='syncing' WHERE id=?", row.id));
      try {
        const token = await secureStorage.getItem(row.token_key);
        if (!token) throw new Error('Identifique novamente o operador responsável para autorizar o envio.');
        const params = replaceMedia(JSON.parse(row.params_json), uploaded);
        const { data, error } = await this.supabase().rpc('rm_mobile_mutate_v1', {
          p_client_submission_id: row.id, p_rpc_name: row.rpc_name,
          p_params: params, p_operator_token: token,
        });
        if (error) throw error;
        await this.database.write(async db => {
          await db.runAsync("UPDATE local_rpc_outbox SET status='completed',last_error=NULL WHERE id=?", row.id);
          await db.runAsync('UPDATE local_queue_meta SET result_json=? WHERE id=?', JSON.stringify(data), row.id);
          if (row.draft_id) await db.runAsync("UPDATE local_form_drafts SET status='synced' WHERE draft_id=?", row.draft_id);
        });
        await secureStorage.removeItem(row.token_key).catch(() => undefined);
      } catch (error) {
        await this.fail('local_rpc_outbox', row.id, row.attempts, error);
        throw error; // Strict FIFO: later RPCs cannot overtake this operation.
      }
    }
  }
  private async fail(table: 'local_rpc_outbox' | 'local_media_upload_queue', id: string, attempts: number, error: unknown) {
    await this.database.write(async db => {
      await db.runAsync(`UPDATE ${table} SET status='failed',attempts=attempts+1,last_error=? WHERE id=?`, errorText(error), id);
      await db.runAsync('UPDATE local_queue_meta SET next_retry_at=? WHERE id=?', Date.now() + retryDelay(attempts + 1), id);
    });
  }
  private async pull() {
    try {
    for (const table of TABLES) {
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
  private async cacheRecordMedia(table: CatalogTable, record: Row) {
    const urls: string[] = table === 'rm_fotos' ? [record.foto_url] : table === 'rm_respostas' ? [...(record.fotos_urls ?? []), record.assinatura_url] : [];
    // Documents are downloaded on demand; their metadata stays available offline.
    for (const uri of urls.filter(u => typeof u === 'string' && /^https:\/\//.test(u))) {
      if (await this.database.local(`media:${uri}`)) continue;
      const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, uri);
      const target = `${mediaDirectory}cache-${hash}`;
      await this.database.write(db => db.runAsync('INSERT OR IGNORE INTO local_media_download_queue(url,local_uri) VALUES (?,?)', uri, target));
    }
  }
  private async downloadPendingMedia() {
    const pending = await this.database.connection().getAllAsync<{url: string; local_uri: string}>('SELECT * FROM local_media_download_queue LIMIT 50');
    const pause = await prefetchWithSpaceReserve(pending, () => FileSystem.getFreeDiskStorageAsync(), async item => {
      try {
        const result = await FileSystem.downloadAsync(item.url, item.local_uri);
        if (result.status >= 200 && result.status < 300) {
          await this.database.saveLocal(`media:${item.url}`, item.local_uri);
          await this.database.write(db => db.runAsync('DELETE FROM local_media_download_queue WHERE url=?', item.url));
        }
      } catch { /* Durable download queue retries on the next synchronization. */ }
    });
    const mediaCacheNotice = pause === 'low_space'
      ? 'Pouco espaço no dispositivo: o download automático de fotos foi pausado para preservar espaço para novas atividades. Os arquivos existentes e os envios pendentes foram mantidos.'
      : pause === 'space_unavailable'
        ? 'Não foi possível verificar o espaço do dispositivo. O download automático de fotos foi pausado; os arquivos existentes e os envios pendentes foram mantidos.'
        : null;
    if (mediaCacheNotice !== this.snapshot.mediaCacheNotice) this.update({ mediaCacheNotice });
  }
  private async refreshCounts() {
    const db = this.database.connection();
    const counts = await db.getFirstAsync<{pendingMedia: number; pendingMutations: number}>(`SELECT
      (SELECT count(*) FROM local_media_upload_queue WHERE status<>'uploaded') AS pendingMedia,
      (SELECT count(*) FROM local_rpc_outbox WHERE status<>'completed') AS pendingMutations`);
    const pendingMedia = counts?.pendingMedia ?? 0, pendingMutations = counts?.pendingMutations ?? 0;
    this.update({ pendingMedia, pendingMutations, syncRecovery: nextSyncRecovery(this.snapshot.syncRecovery, {
      type: 'queue', online: this.snapshot.online, pendingMedia, pendingMutations, restoring: !this.snapshot.ready,
    }) });
  }
}

export const service = new MobileService();
