import { randomUUID } from 'node:crypto';
import type { SupabaseClient } from '@supabase/supabase-js';
import { adminClient, bridgeConfig } from '../config';
import { BubbleClient } from './client';
import { entities, getEntity, fieldValue, fieldUrl, type Entity, type Field, type Row } from './mapping';
import { isOperationalProject, scopedGroups } from './scope';
import { preserveImportedPdf } from './pdf-document';

function fail(error: { message: string } | null) { if (error) throw new Error(error.message); }
export class Bridge {
  readonly workerId = randomUUID();
  private options: Row[] = [];
  private resolving = new Set<string>();
  private heartbeatError: unknown;
  constructor(readonly db: SupabaseClient = adminClient(), readonly bubble = new BubbleClient(bridgeConfig())) {}
  async rpc(name: string, params: Row) {
    const { data, error } = await this.db.rpc(name, params); fail(error); return data;
  }
  async loadOptions() {
    const { data, error } = await this.db.from('rm_option_sets').select('*'); fail(error); this.options = data || [];
  }
  private option(set: string, value: unknown, outbound: boolean) {
    if (value === null || value === '') return null;
    const candidates=this.options.filter(o=>o.option_set_key===set);
    const exact=candidates.find(o=>o.option_key===value || o.bubble_display===value);
    const insensitive=candidates.filter(o=>String(o.bubble_display).toLowerCase()===String(value).toLowerCase());
    const found=exact || (insensitive.length===1?insensitive[0]:undefined);
    if (!found) throw new Error(`Option Set desconhecido: ${set}/${String(value)}`);
    return found[outbound ? 'bubble_display' : 'option_key'];
  }
  validate(entity: Entity, raw: Row): void {
    if(typeof raw._id!=='string'||!raw._id)throw new Error('_id Bubble ausente.');
    for(const column of entity.required||[]) {
      const value=fieldValue(raw,entity.fields[column]);
      if(value==null || value==='')throw new Error(`Campo obrigatório ausente: ${column}`);
    }
    for(const field of Object.values(entity.fields)) {
      const value=fieldValue(raw,field);if(value===undefined)continue;
      const values=field.list?value:[value];
      if(!Array.isArray(values))throw new Error(`Lista inválida: ${field.bubble}`);
      for(const item of values) {
        if(field.option)this.option(field.option,item,false);
        if(field.url)fieldUrl(field,item);
        if(field.ref && item!=null && typeof item!=='string')throw new Error(`Referência inválida: ${field.bubble}`);
      }
    }
  }
  async row(table: string, id: string) {
    const { data, error } = await this.db.from(table).select('*').eq('id', id).single(); fail(error);
    if (!data) throw new Error(`Registro ausente: ${table}`); return data as Row;
  }
  private async resolve(table: string, bubbleId: unknown): Promise<string | null> {
    if (bubbleId === null || bubbleId === '') return null;
    if (typeof bubbleId !== 'string') throw new Error(`Referência Bubble inválida em ${table}.`);
    const { data, error } = await this.db.from(table).select('id').eq('bubble_id', bubbleId).maybeSingle(); fail(error);
    if (data) return data.id as string;
    const key = `${table}/${bubbleId}`;
    if (this.resolving.has(key)) throw new Error(`Dependência cíclica não resolvida: ${table}`);
    this.resolving.add(key);
    try { const entity = getEntity(table); return await this.apply(entity, await this.bubble.get(entity.endpoint, bubbleId)); }
    finally { this.resolving.delete(key); }
  }
  async translate(field: Field, value: unknown, outbound = false): Promise<unknown> {
    if (field.list) {
      if (!Array.isArray(value)) throw new Error(`Lista inválida: ${field.bubble}`);
      return Promise.all(value.map(v => this.translate({ ...field, list: false }, v, outbound)));
    }
    if (field.option) return this.option(field.option, value, outbound);
    if (field.ref) {
      if (value === null || value === '') return null;
      if (!outbound) return this.resolve(field.ref, value);
      const row = await this.row(field.ref, String(value));
      if (!row.bubble_id) throw new Error(`Dependência ainda não exportada: ${field.ref}`);
      return row.bubble_id;
    }
    return field.url ? fieldUrl(field,value) : value;
  }
  async apply(entity: Entity, raw: Row): Promise<string> {
    this.validate(entity, raw);
    if (typeof raw._id !== 'string' || !raw._id) throw new Error('_id Bubble obrigatório.');
    const modified = raw['Modified Date'];
    if (typeof modified !== 'string' || !Number.isFinite(Date.parse(modified))) throw new Error('Modified Date Bubble obrigatório.');
    const { data: byBubble, error: readError } = await this.db.from(entity.table).select('*').eq('bubble_id', raw._id).maybeSingle(); fail(readError);
    let existing=byBubble;
    if(!existing && entity.table==='rm_users') {
      const auth=raw.authentication as {email?:{email?:unknown}}|undefined;
      const emails=[raw.email_corporativo,raw.email,auth?.email?.email]
        .filter((value):value is string=>typeof value==='string')
        .map(value=>value.trim().toLowerCase()).filter(value=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value));
      const matches=new Map<string,Row>();
      for(const email of new Set(emails))for(const column of ['email','email_corporativo']){
        const match=await this.db.from('rm_users').select('*').eq(column,email).is('bubble_id',null).limit(2);fail(match.error);
        for(const local of match.data||[])matches.set(String(local.id),local);
      }
      if(matches.size>1)throw new Error('Email corresponde a mais de uma identidade local.');
      if(matches.size)existing=[...matches.values()][0];
    }
    if (existing?.bubble_modified_at && Date.parse(existing.bubble_modified_at) >= Date.parse(modified)) {
      if (entity.table === 'rm_registros_formulario' && existing.codigo != null) await this.rpc('rm_advance_form_sequence_v1',{p_form_id:existing.form_id,p_code:existing.codigo});
      return existing.id;
    }
    const row: Row = { bubble_id: raw._id, bubble_modified_at: modified, sync_source: 'bubble' };
    for (const [column, field] of Object.entries(entity.fields)) {
      const value = fieldValue(raw, field);
      if (value !== undefined) row[column] = await this.translate(field, value);
    }
    if(entity.table==='rm_projetos'){
      row.data_real_de_entrega??=null;
      row.status_pcp??=null;
    }
    if (!existing) for (const key of entity.required || []) if (row[key] == null || row[key] === '') throw new Error(`Campo obrigatório ausente: ${entity.name}.${key}`);
    if(existing)row.id=existing.id;
    if(entity.table==='rm_documentos')preserveImportedPdf(row,existing);
    // Auth account linkage and its locally provisioned role remain authoritative.
    if(entity.table==='rm_users' && existing?.auth_user_id){row.perfil=existing.perfil;row.matricula=existing.matricula;}
    {
      // Guard new children too, including a response's project ancestor.
      const ids = [existing?.id,existing?.registro_formulario_id,existing?.projeto_id,row.registro_formulario_id,row.projeto_id].filter((v): v is string => typeof v === 'string');
      const recordId=row.registro_formulario_id||existing?.registro_formulario_id;
      if(typeof recordId==='string'){
        const parent=await this.row('rm_registros_formulario',recordId);
        if(typeof parent.projeto_id==='string')ids.push(parent.projeto_id);
      }
      if(ids.length){
      const { data: pending, error } = await this.db.from('rm_sync_outbox').select('id').in('record_id', ids).eq('target_system','bubble_data_api').neq('status','completed').limit(1); fail(error);
      if (pending?.length) throw new Error(`Conflito pendente em ${entity.name}; exportar fila antes de aplicar Desktop.`);
      }
    }
    const { data, error } = await this.db.from(entity.table).upsert(row, { onConflict: existing?'id':'bubble_id' }).select('id').single(); fail(error);
    if (!data) throw new Error(`Importação sem resultado: ${entity.name}`);
    if (entity.table === 'rm_registros_formulario' && row.codigo != null) await this.rpc('rm_advance_form_sequence_v1',{p_form_id:row.form_id || existing?.form_id,p_code:row.codigo});
    // Restore the reverse equipment link required by project detail consumers.
    if (entity.table === 'rm_equipamentos' && row.projeto_id) {
      const link = await this.db.from('rm_projetos').update({ equipamento_id: data.id, sync_source: 'bubble' }).eq('id', row.projeto_id); fail(link.error);
    }
    return data.id;
  }
  async exportRow(table: string, id: string): Promise<string> {
    this.checkHeartbeat();
    const entity = getEntity(table); const row = await this.row(table, id); const body: Row = {};
    for (const [column, field] of Object.entries(entity.fields)) {
      if (!field.inboundOnly && row[column] !== undefined) body[field.bubble] = await this.translate(field, row[column], true);
    }
    // The Bubble report workflows join the textual ID to the remote record ID.
    if (table === 'rm_respostas') body.ID_Registro = body.Registro_Formulario;
    const bubbleId = await this.bubble.write(entity.endpoint, row.bubble_id as string | null, id, body);
    const { error } = await this.db.from(table).update({ bubble_id: bubbleId }).eq('id',id); fail(error);
    return bubbleId;
  }
  async related(table: string, column: string, id: string) {
    const result: Row[] = [];
    for (let offset = 0; ; offset += 500) {
      const { data, error } = await this.db.from(table).select('*').eq(column,id).order('id').range(offset,offset+499); fail(error);
      result.push(...(data || [])); if (!data || data.length < 500) break;
    }
    return result;
  }
  async processEvent(event: Row) {
    const id = String(event.record_id);
    if (event.target_system === 'n8n_webhook') {
      const payload = event.payload as Row;
      await this.bubble.webhook(String(payload.webhook_url), payload.body, `rm-outbox-${event.id}`); return;
    }
    if (event.target_system !== 'bubble_data_api') throw new Error('Destino de outbox não implementado.');
    switch (event.entity_type) {
      case 'Recebimento_Bundle': {
        const projectId = await this.exportRow('rm_projetos',id);
        const equipment = await this.related('rm_equipamentos','projeto_id',id);
        for (const eq of equipment) {
          const eqId = await this.exportRow('rm_equipamentos',String(eq.id));
          await this.bubble.write('projetorm',projectId,id,{ Equipamento: eqId });
        }
        for (const foto of await this.related('rm_fotos','projeto_id',id)) await this.exportRow('rm_fotos',String(foto.id));
        return;
      }
      case 'Registro_Formulario_Bundle':
      case 'Registro_Formulario_Revision': {
        const regId = await this.exportRow('rm_registros_formulario',id); const responseIds: string[] = [];
        for (const response of await this.related('rm_respostas','registro_formulario_id',id)) responseIds.push(await this.exportRow('rm_respostas',String(response.id)));
        await this.bubble.write('registro_formulario',regId,id,{ Respostas: responseIds }); return;
      }
      case 'Fotos_RM_Sync': await this.exportRow('rm_fotos',id); return;
      case 'Celula_Projeto_Status': await this.exportRow('rm_celulas_projeto',id); return;
      case 'Comentario_Celula': await this.exportRow('rm_comentarios',id); return;
      case 'Aprovacao_Etapa_Transition': {
        const stage = await this.row('rm_aprovacoes_etapas',id);
        await this.exportRow('rm_aprovacoes_etapas',id);
        const payload = (event.payload || {}) as Row;
        for (const reverse of Array.isArray(payload.affected_approval_ids) ? payload.affected_approval_ids : []) {
          if (String(reverse) !== id) await this.exportRow('rm_aprovacoes_etapas',String(reverse));
        }
        for (const cell of await this.related('rm_celulas_projeto','projeto_id',String(stage.projeto_id))) await this.exportRow('rm_celulas_projeto',String(cell.id));
        if (payload.log_id) await this.exportRow('rm_logs_aprovacao',String(payload.log_id));
        if (payload.comentario_id) await this.exportRow('rm_comentarios',String(payload.comentario_id));
        return;
      }
      default: throw new Error(`Evento não suportado: ${String(event.entity_type)}`);
    }
  }
  async outbox(): Promise<{ completed: number; failed: number }> {
    const stats = { completed: 0, failed: 0 };
    // Claim one at a time. Long bundles renew only their own lease.
    for (let n = 0; n < 25; n++) {
      this.checkHeartbeat();
      const events = await this.rpc('rm_claim_sync_events_v1',{ p_worker_id:this.workerId,p_limit:1 }) as Row[];
      if (!events?.length) break;
      const event = events[0]; let errorMessage: string | null = null;
      const renew = setInterval(() => { void this.rpc('rm_renew_sync_event_v1',{p_id:event.id,p_worker_id:this.workerId}).then(ok => { if (!ok) this.heartbeatError = new Error('Lease de evento perdida.'); }).catch(e => { this.heartbeatError = e; }); },60_000);
      try { await this.processEvent(event); this.checkHeartbeat(); }
      catch (error) { errorMessage = error instanceof Error ? error.message : 'Falha de sincronização'; }
      finally { clearInterval(renew); }
      const done = await this.rpc('rm_finish_sync_event_v1',{p_id:event.id,p_worker_id:this.workerId,p_error:errorMessage});
      if (!done) throw new Error('Lease expirada antes de confirmar evento.');
      if (errorMessage) stats.failed++; else stats.completed++;
    }
    return stats;
  }
  private checkHeartbeat() { if (this.heartbeatError) throw new Error('Lease de sincronização perdida; ciclo interrompido.'); }
  async sourceRows(table: string, columns: string): Promise<Row[]> {
    const result: Row[]=[];
    for(let offset=0;;offset+=500){
      const {data,error}=await this.db.from(table).select(columns).order('id').range(offset,offset+499);fail(error);
      result.push(...((data||[]) as unknown as Row[]));if(!data||data.length<500)return result;
    }
  }
  async pull(): Promise<{ imported: number; errors: string[] }> {
    const stats = { imported: 0, errors: [] as string[] };
    // Leave a lag and overlap to tolerate timestamp granularity and clock skew.
    const until = new Date(Date.now()-60_000).toISOString();
    const projectRows=await this.sourceRows('rm_projetos','id,bubble_id,status_pcp,data_real_de_entrega');
    const projects=new Map(projectRows.filter(row=>row.bubble_id).map(row=>[String(row.bubble_id),row]));
    const changedProjects=new Map<string,string>();
    const checkpointResult=await this.db.from('rm_bridge_checkpoints').select('endpoint,cursor_at');fail(checkpointResult.error);
    const checkpoints=new Map((checkpointResult.data||[]).map(row=>[String(row.endpoint),String(row.cursor_at)]));
    const initial=process.env.SYNC_INITIAL_CURSOR||'1970-01-01T00:00:00.000Z';
    for (const entity of entities) {
      const errors=new Map<string,number>();
      const recordError=(error:unknown)=>{const message=error instanceof Error?error.message:'falha';errors.set(message,(errors.get(message)||0)+1);};
      try {
        this.checkHeartbeat();
        const cursor = checkpoints.get(entity.endpoint)||initial;
        // Revisit project transitions until every child checkpoint has passed them.
        // This persists hydration retries without a second queue or a lossy in-memory flag.
        // A child with no checkpoint already reads its whole active scope and
        // therefore does not force the project cursor back to epoch by itself.
        const projectFloor=entity.table==='rm_projetos'?Math.min(...['projetorm','equipamento','celula_projeto','fotosrm','registro_formulario','aprovacao_etapas','comentarios','log_aprocacao','docs','documentos'].map(endpoint=>Date.parse(checkpoints.get(endpoint)||cursor))):Date.parse(cursor);
        const since = new Date(Math.max(0,projectFloor-120_000)).toISOString();
        const active=[...projects].filter(([,row])=>isOperationalProject(row)).map(([id])=>id);
        const hydrateProjects=active.filter(id=>Date.parse(changedProjects.get(id)||'')>Date.parse(cursor));
        let revisionIds:string[]=[];
        if(entity.table==='rm_respostas'){
          const activeLocalIds=new Set(active.map(id=>String(projects.get(id)?.id)));
          revisionIds=(await this.sourceRows('rm_registros_formulario','id,bubble_id,projeto_id,status'))
            .filter(row=>row.bubble_id&&row.status==='direcionado'&&activeLocalIds.has(String(row.projeto_id)))
            .map(row=>String(row.bubble_id));
        }
        // Revision answers are deliberately re-read in full: a status transition may
        // expose answers whose own Modified Date predates the answer checkpoint.
        const hydrateRevisions=revisionIds;
        const isChild=['rm_equipamentos','rm_celulas_projeto','rm_fotos','rm_registros_formulario','rm_aprovacoes_etapas','rm_comentarios','rm_logs_aprovacao','rm_docs','rm_documentos'].includes(entity.table);
        const hydrateIds=entity.table==='rm_respostas'?hydrateRevisions:hydrateProjects;
        const windows=(isChild||entity.table==='rm_respostas')?[
          {since:'1970-01-01T00:00:00.000Z',groups:scopedGroups(entity,hydrateProjects,hydrateRevisions)},
          {since,groups:scopedGroups(entity,active.filter(id=>!hydrateIds.includes(id)),revisionIds.filter(id=>!hydrateIds.includes(id)))},
        ]:[{since,groups:[[]]}];
        for(const window of windows)for(const constraints of window.groups){
          try{
            for await(const page of this.bubble.pages(entity.endpoint,window.since,until,constraints))for(const raw of page){
              this.checkHeartbeat();
              // Existing projects must receive terminal/delivery transitions before their children leave the scope.
              if(entity.table==='rm_projetos'&&!isOperationalProject(raw)&&!projects.has(String(raw._id)))continue;
              try{
                const id=await this.apply(entity,raw);stats.imported++;
                if(entity.table==='rm_projetos'){
                  projects.set(String(raw._id),{...raw,id});
                  if(isOperationalProject(raw))changedProjects.set(String(raw._id),String(raw['Modified Date']));
                }
              }catch(error){recordError(error);}
            }
          }catch(error){recordError(error);}
        }
        if(!errors.size)await this.rpc('rm_advance_bridge_checkpoint_v1',{p_endpoint:entity.endpoint,p_cursor_at:until});
      } catch (error) { recordError(error); }
      for(const [message,count] of errors)stats.errors.push(`${entity.name}: ${count} falha(s): ${message}`);
    }
    return stats;
  }
  async withLease<T>(run: () => Promise<T>): Promise<T> {
    if (!await this.rpc('rm_acquire_bridge_lease_v1',{p_worker_id:this.workerId,p_seconds:300})) throw new Error('BRIDGE_BUSY');
    const timer = setInterval(() => { void this.rpc('rm_acquire_bridge_lease_v1',{p_worker_id:this.workerId,p_seconds:300}).then(ok => { if (!ok) this.heartbeatError = new Error('Lease perdida.'); }).catch(e => { this.heartbeatError = e; }); },60_000);
    try { await this.loadOptions(); return await run(); }
    finally { clearInterval(timer); await this.rpc('rm_release_bridge_lease_v1',{p_worker_id:this.workerId}); }
  }
  async cycle() {
    return this.withLease(async () => ({
      outbox: process.env.SYNC_OUTBOX_ENABLED === 'true'
        ? await this.outbox()
        : { completed: 0, failed: 0, disabled: true },
      inbox: await this.pull(),
    }));
  }
}
