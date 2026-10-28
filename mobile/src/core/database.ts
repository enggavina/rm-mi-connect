import * as SQLite from 'expo-sqlite';
import { RM_MOBILE_SQLITE_DDL } from './schema';
import { TABLES, type CatalogFilter, type CatalogTable, type Row } from './types';
import { QUEUE_DOCUMENTS_MIGRATION, QUEUE_DOCUMENTS_VERSION } from './queue-migration';

const EXTENSION_DDL = `
CREATE TABLE IF NOT EXISTS local_catalog (
  table_name TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
  updated_at TEXT NOT NULL, PRIMARY KEY(table_name,id)
);
CREATE TABLE IF NOT EXISTS local_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS local_draft_context (
  draft_id TEXT PRIMARY KEY REFERENCES local_form_drafts(draft_id) ON DELETE CASCADE,
  registro_formulario_id TEXT
);
CREATE TABLE IF NOT EXISTS local_answer_payload (
  draft_id TEXT NOT NULL REFERENCES local_form_drafts(draft_id) ON DELETE CASCADE,
  questao_id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(draft_id,questao_id)
);
CREATE TABLE IF NOT EXISTS local_queue_meta (
  id TEXT PRIMARY KEY, next_retry_at INTEGER NOT NULL DEFAULT 0,
  actor_id TEXT, token_key TEXT, draft_id TEXT, result_json TEXT
);
CREATE TABLE IF NOT EXISTS local_media_download_queue (url TEXT PRIMARY KEY, local_uri TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS idx_local_catalog_table ON local_catalog(table_name);
CREATE INDEX IF NOT EXISTS idx_local_catalog_record ON local_catalog(table_name,json_extract(payload,'$.registro_formulario_id'));
CREATE INDEX IF NOT EXISTS idx_local_outbox_pending ON local_rpc_outbox(status,created_at);
CREATE INDEX IF NOT EXISTS idx_local_media_pending ON local_media_upload_queue(status,created_at);
`;

export class LocalDatabase {
  private db?: SQLite.SQLiteDatabase;
  private writes: Promise<unknown> = Promise.resolve();
  async initialize() {
    this.db = await SQLite.openDatabaseAsync('rm-mi-connect.db');
    await this.db.execAsync(RM_MOBILE_SQLITE_DDL + EXTENSION_DDL);
    if ((await this.local<number>('queue_schema_version') ?? 0) < QUEUE_DOCUMENTS_VERSION) {
      await this.write(db => db.execAsync(QUEUE_DOCUMENTS_MIGRATION));
    }
    await this.db.runAsync("UPDATE local_rpc_outbox SET status='pending' WHERE status='syncing'");
    await this.db.runAsync("UPDATE local_media_upload_queue SET status='pending' WHERE status='uploading'");
  }
  connection() { if (!this.db) throw new Error('Banco local ainda não está pronto.'); return this.db; }
  /** A single write lane avoids async transaction interleaving across autosave and sync. */
  write<T>(fn: (db: SQLite.SQLiteDatabase) => Promise<T>): Promise<T> {
    const operation = this.writes.then(async () => {
      let result!: T;
      await this.connection().withExclusiveTransactionAsync(async tx => { result = await fn(tx); });
      return result;
    });
    this.writes = operation.catch(() => undefined);
    return operation;
  }
  async idle() { await this.writes; }
  async local<T>(key: string): Promise<T | null> {
    await this.idle();
    const record = await this.connection().getFirstAsync<{value: string}>('SELECT value FROM local_meta WHERE key=?', key);
    return record ? JSON.parse(record.value) as T : null;
  }
  async saveLocal(key: string, value: unknown) {
    await this.write(db => db.runAsync('INSERT INTO local_meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', key, JSON.stringify(value)));
  }
  assertTable(table: string): asserts table is CatalogTable {
    if (!(TABLES as readonly string[]).includes(table)) throw new Error('Catálogo local não permitido.');
  }
  async list(table: string, filter?: CatalogFilter): Promise<Row[]> {
    this.assertTable(table);
    if (filter && !['registro_formulario_id', 'projeto_id', 'form_id', 'celula_id'].includes(filter.field)) throw new Error('Filtro de catálogo inválido.');
    const records = filter
      ? await this.connection().getAllAsync<{payload: string}>(`SELECT payload FROM local_catalog WHERE table_name=? AND json_extract(payload,'$.${filter.field}')=?`, table, filter.value)
      : await this.connection().getAllAsync<{payload: string}>('SELECT payload FROM local_catalog WHERE table_name=?', table);
    return records.map(r => JSON.parse(r.payload) as Row);
  }
  async get(table: string, id: string): Promise<Row | null> {
    this.assertTable(table);
    const r = await this.connection().getFirstAsync<{payload: string}>('SELECT payload FROM local_catalog WHERE table_name=? AND id=?', table, id);
    return r ? JSON.parse(r.payload) : null;
  }
  async cache(table: CatalogTable, records: Row[]) {
    await this.write(async db => {
      for (const r of records) {
        const updated = String(r.updated_at ?? new Date().toISOString());
        await db.runAsync('INSERT INTO local_catalog(table_name,id,payload,updated_at) VALUES (?,?,?,?) ON CONFLICT(table_name,id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at', table, r.id, JSON.stringify(r), updated);
        // Preserve the supplied concrete SQLite cache tables; richer fields remain losslessly in local_catalog.
        if (table === 'rm_projetos') await db.runAsync(`INSERT INTO local_projetos_cache(id,numero,nome,cliente_nome,escopo_abreviado,status,status_pcp,updated_at)
          VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET numero=excluded.numero,nome=excluded.nome,cliente_nome=excluded.cliente_nome,escopo_abreviado=excluded.escopo_abreviado,status=excluded.status,status_pcp=excluded.status_pcp,updated_at=excluded.updated_at`,
          r.id, r.numero ?? null, r.nome ?? null, r.cliente_nome_exportacao ?? null, r.escopo_abreviado ?? null, r.status ?? null, r.status_pcp ?? null, updated);
        if (table === 'rm_celulas_projeto') await db.runAsync(`INSERT INTO local_celulas_projeto_cache(id,projeto_id,celula_id,numero_projeto,status,visibilidade,bloqueada,motivo_bloqueio,prioridade,data_inicio,data_limite,forms_ids_json,updated_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,visibilidade=excluded.visibilidade,bloqueada=excluded.bloqueada,motivo_bloqueio=excluded.motivo_bloqueio,prioridade=excluded.prioridade,data_inicio=excluded.data_inicio,data_limite=excluded.data_limite,forms_ids_json=excluded.forms_ids_json,updated_at=excluded.updated_at`,
          r.id, r.projeto_id, r.celula_id, r.numero_projeto ?? null, r.status, r.visibilidade ? 1 : 0, r.bloqueada ?? null, r.motivo_bloqueio ?? null, r.prioridade == null ? null : String(r.prioridade), r.data_inicio ?? null, r.data_limite ?? null, JSON.stringify(r.forms_ids ?? []), updated);
        if (table === 'rm_forms') await db.runAsync(`INSERT INTO local_forms_cache(id,titulo,descricao,tipo,updated_at) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET titulo=excluded.titulo,descricao=excluded.descricao,tipo=excluded.tipo,updated_at=excluded.updated_at`, r.id, r.titulo, r.descricao ?? null, r.tipo ?? null, updated);
        if (table === 'rm_fotos' && r.projeto_id && r.celula_id) await db.runAsync(`INSERT INTO local_fotos_slots_cache(id,bubble_id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,descricao,legenda,numero,foto_url,updated_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET titulo=excluded.titulo,descricao=excluded.descricao,legenda=excluded.legenda,foto_url=excluded.foto_url,updated_at=excluded.updated_at`,
          r.id, r.bubble_id ?? null, r.projeto_id, r.celula_id, r.celula_projeto_id ?? null, r.categoria_foto ?? 'obrigat_ria', r.titulo ?? 'Foto', r.descricao ?? null, r.legenda ?? null, r.numero ?? null, r.foto_url ?? null, updated);
      }
    });
  }
  async removeMissing(table: CatalogTable, present: Set<string>) {
    this.assertTable(table);
    const records = await this.connection().getAllAsync<{id: string}>('SELECT id FROM local_catalog WHERE table_name=?', table);
    const cacheTables: Partial<Record<CatalogTable, string>> = {
      rm_projetos: 'local_projetos_cache', rm_celulas_projeto: 'local_celulas_projeto_cache',
      rm_forms: 'local_forms_cache', rm_fotos: 'local_fotos_slots_cache',
    };
    await this.write(async db => {
      for (const r of records) if (!present.has(r.id)) {
        await db.runAsync('DELETE FROM local_catalog WHERE table_name=? AND id=?', table, r.id);
        const concrete = cacheTables[table];
        if (concrete) await db.runAsync(`DELETE FROM ${concrete} WHERE id=?`, r.id);
      }
    });
  }
}
