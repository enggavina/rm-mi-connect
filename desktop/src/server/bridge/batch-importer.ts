import type { Bridge } from './engine';
import { entities, fieldValue, getEntity, type Entity, type Field, type Row } from './mapping';

type Cached = Row & { id: string; bubble_id?: string | null; bubble_modified_at?: string | null };
type Prepared = { raw: Row; row: Row; existing?: Cached; onConflict: 'id' | 'bubble_id' };
export type QuarantineHandler = (raw: Row, error: Error) => void | Promise<void>;
export type ImportPageResult = { loaded: number; unchanged: number };

const message = (error: unknown) => error instanceof Error ? error : new Error(String(error));
const chunks = <T>(rows: T[], size: number): T[][] => {
  const result: T[][] = [];
  for (let i = 0; i < rows.length; i += size) result.push(rows.slice(i, i + size));
  return result;
};

/** Initial/incremental inbox import only. It never exports outbox or credentials.
 * Run under Bridge.withLease. Per-page pending checks also protect bundle children;
 * as with Bridge.apply, they are a conflict guard, not a lock on mobile writers.
 */
export class BatchImporter {
  private readonly byBubble = new Map<string, Map<string, Cached>>();
  private readonly byId = new Map<string, Map<string, Cached>>();
  private readonly resolving = new Map<string, Promise<Cached>>();
  private ready = false;

  constructor(private readonly bridge: Bridge) {}

  private columns(entity: Entity): string {
    const result = ['id', 'bubble_id', 'bubble_modified_at'];
    for (const key of ['projeto_id', 'registro_formulario_id']) if (key in entity.fields) result.push(key);
    if (entity.table === 'rm_users') result.push('auth_user_id', 'email', 'email_corporativo', 'perfil', 'matricula');
    if (entity.table === 'rm_registros_formulario') result.push('form_id', 'codigo');
    return result.join(',');
  }

  private remember(table: string, record: Cached): void {
    let ids = this.byId.get(table);
    if (!ids) this.byId.set(table, ids = new Map());
    let remote = this.byBubble.get(table);
    if (!remote) this.byBubble.set(table, remote = new Map());
    const previous = ids.get(record.id);
    if (previous?.bubble_id && previous.bubble_id !== record.bubble_id) remote.delete(previous.bubble_id);
    const merged = { ...previous, ...record };
    ids.set(record.id, merged);
    if (merged.bubble_id) remote.set(merged.bubble_id, merged);
  }

  async preload(): Promise<void> {
    await this.bridge.loadOptions();
    for (const entity of entities) {
      this.byId.set(entity.table, new Map()); this.byBubble.set(entity.table, new Map());
      // The cache contains metadata/IDs only, never response bodies or secrets.
      for (let offset = 0; ; offset += 1000) {
        const { data, error } = await this.bridge.db.from(entity.table).select(this.columns(entity))
          .order('id').range(offset, offset + 999);
        if (error) throw new Error(`Cache ${entity.table}: ${error.message}`);
        for (const row of data || []) this.remember(entity.table, row as unknown as Cached);
        if (!data || data.length < 1000) break;
      }
    }
    this.ready = true;
  }

  private localUser(raw: Row): Cached | undefined {
    const auth = raw.authentication as { email?: { email?: unknown } } | undefined;
    const emails = [raw.email_corporativo, raw.email, auth?.email?.email]
      .filter((v): v is string => typeof v === 'string').map(v => v.trim().toLowerCase())
      .filter(v => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v));
    const candidates = [...(this.byId.get('rm_users')?.values() || [])].filter(row => !row.bubble_id &&
      [row.email, row.email_corporativo].some(value => typeof value === 'string' && emails.includes(value.trim().toLowerCase())));
    if (candidates.length > 1) throw new Error('Email corresponde a mais de uma identidade local.');
    return candidates[0];
  }

  private async resolveReference(table: string, value: unknown): Promise<string | null> {
    if (value === null || value === '') return null;
    if (typeof value !== 'string') throw new Error(`Referência Bubble inválida em ${table}.`);
    const cached = this.byBubble.get(table)?.get(value);
    if (cached) return cached.id;
    const key = `${table}/${value}`;
    let pending = this.resolving.get(key);
    if (!pending) {
      pending = (async () => {
        const entity = getEntity(table);
        // A dependency may have been imported recursively since preload.
        const known = await this.bridge.db.from(table).select(this.columns(entity)).eq('bubble_id', value).maybeSingle();
        if (known.error) throw new Error(known.error.message);
        if (known.data) return known.data as unknown as Cached;
        const raw = await this.bridge.bubble.get(entity.endpoint, value);
        this.bridge.validate(entity, raw);
        const id = await this.bridge.apply(entity, raw);
        const imported = await this.bridge.db.from(table).select(this.columns(entity)).eq('id', id).single();
        if (imported.error || !imported.data) throw new Error(imported.error?.message || `Dependência não persistida: ${table}`);
        return imported.data as unknown as Cached;
      })();
      this.resolving.set(key, pending);
    }
    try {
      const row = await pending;
      this.remember(table, row);
      return row.id;
    } finally {
      this.resolving.delete(key);
    }
  }

  private async translate(field: Field, value: unknown): Promise<unknown> {
    if (!field.ref) return this.bridge.translate(field, value);
    if (field.list) {
      if (!Array.isArray(value)) throw new Error(`Lista inválida: ${field.bubble}`);
      return Promise.all(value.map(item => this.resolveReference(field.ref!, item)));
    }
    return this.resolveReference(field.ref, value);
  }

  private guardedIds(item: Prepared): string[] {
    const recordId = item.row.registro_formulario_id || item.existing?.registro_formulario_id;
    const recordProject = typeof recordId === 'string' ? this.byId.get('rm_registros_formulario')?.get(recordId)?.projeto_id : undefined;
    return [item.existing?.id, item.existing?.projeto_id, item.existing?.registro_formulario_id,
      item.row.projeto_id, item.row.registro_formulario_id, recordProject].filter((value): value is string => typeof value === 'string');
  }

  private async pendingIds(rows: Prepared[]): Promise<Set<string>> {
    const ids = [...new Set(rows.flatMap(item => this.guardedIds(item)))];
    const pending = new Set<string>();
    for (const group of chunks(ids, 200)) {
      const result = await this.bridge.db.from('rm_sync_outbox').select('record_id').in('record_id', group)
        .eq('target_system', 'bubble_data_api').neq('status', 'completed');
      if (result.error) throw new Error(result.error.message);
      for (const event of result.data || []) pending.add(String(event.record_id));
    }
    return pending;
  }

  private async persist(entity: Entity, rows: Prepared[], quarantine: QuarantineHandler): Promise<Prepared[]> {
    if (!rows.length) return [];
    const result = await this.bridge.db.from(entity.table).upsert(rows.map(item => item.row), {
      onConflict: rows[0].onConflict,
      defaultToNull: false,
    }).select(this.columns(entity));
    if (result.error) {
      // Only isolate actual record/constraint errors. Never turn auth, network or
      // missing-column failures into hundreds of misleading quarantined records.
      if (!/^(22|23)/.test(result.error.code || '')) throw new Error(`${entity.table}: ${result.error.message}`);
      if (rows.length === 1) {
        await quarantine(rows[0].raw, new Error(`${entity.table}: ${result.error.message}`));
        return [];
      }
      const middle = Math.floor(rows.length / 2);
      return [...await this.persist(entity, rows.slice(0, middle), quarantine),
        ...await this.persist(entity, rows.slice(middle), quarantine)];
    }
    const returned = new Map((result.data || []).map(row => [String((row as unknown as Cached).bubble_id), row as unknown as Cached]));
    for (const item of rows) {
      const record = returned.get(String(item.row.bubble_id));
      if (!record?.id) throw new Error(`Importação sem resultado: ${entity.name}`);
      this.remember(entity.table, record);
      item.row.id = record.id;
    }
    return rows;
  }

  private async finishLinks(entity: Entity, changed: Prepared[], sequenced: Cached[]): Promise<void> {
    if (entity.table === 'rm_equipamentos') {
      for (const group of chunks(changed.filter(item => typeof item.row.projeto_id === 'string'), 8)) {
        await Promise.all(group.map(async item => {
          const result = await this.bridge.db.from('rm_projetos')
            .update({ equipamento_id: item.row.id, sync_source: 'bubble' }).eq('id', item.row.projeto_id);
          if (result.error) throw new Error(`Vínculo de equipamento: ${result.error.message}`);
        }));
      }
    }
    if (entity.table === 'rm_registros_formulario') {
      const maximum = new Map<string, number>();
      for (const row of [...sequenced, ...changed.map(item => item.row)]) {
        const code = Number(row.codigo);
        if (typeof row.form_id === 'string' && row.codigo !== null && row.codigo !== undefined && Number.isSafeInteger(code) && code >= 0) {
          maximum.set(row.form_id, Math.max(maximum.get(row.form_id) || 0, code));
        }
      }
      for (const [form, code] of maximum) await this.bridge.rpc('rm_advance_form_sequence_v1', { p_form_id: form, p_code: code });
    }
  }

  async importPage(entity: Entity, rawRows: Row[], onQuarantine: QuarantineHandler): Promise<ImportPageResult> {
    if (!this.ready) throw new Error('Execute BatchImporter.preload antes da carga.');
    const stats = { loaded: 0, unchanged: 0 };
    const prepared: Prepared[] = [], sequenced: Cached[] = [];
    const unique = new Map<string, Row>();
    for (const raw of rawRows) {
      if (typeof raw._id !== 'string' || !raw._id) { await onQuarantine(raw, new Error('_id Bubble obrigatório.')); continue; }
      const previous = unique.get(raw._id);
      if (previous) {
        stats.unchanged++;
        if (Date.parse(String(previous['Modified Date'])) > Date.parse(String(raw['Modified Date']))) continue;
      }
      unique.set(raw._id, raw);
    }
    for (const raw of unique.values()) {
      try {
        const modified = raw['Modified Date'];
        if (typeof modified !== 'string' || !Number.isFinite(Date.parse(modified))) throw new Error('Modified Date Bubble obrigatório.');
        const existing = this.byBubble.get(entity.table)?.get(String(raw._id)) || (entity.table === 'rm_users' ? this.localUser(raw) : undefined);
        if (existing?.bubble_modified_at && Date.parse(existing.bubble_modified_at) >= Date.parse(modified)) {
          stats.unchanged++; sequenced.push(existing); continue;
        }
        this.bridge.validate(entity, raw);
        const row: Row = { bubble_id: raw._id, bubble_modified_at: modified, sync_source: 'bubble' };
        for (const [column, field] of Object.entries(entity.fields)) {
          const value = fieldValue(raw, field);
          if (value !== undefined) row[column] = await this.translate(field, value);
        }
        // Bubble full-record responses omit cleared optional fields. These two
        // fields determine operational scope, so preserving their old values
        // would hide a reopened project indefinitely.
        if (entity.table === 'rm_projetos') {
          for (const key of ['data_real_de_entrega', 'status_pcp']) {
            if (fieldValue(raw, entity.fields[key]) === undefined) row[key] = null;
          }
        }
        if (existing) row.id = existing.id;
        // Never map auth_user_id or credential fields from a Bubble payload.
        if (entity.table === 'rm_users' && existing?.auth_user_id) {
          row.perfil = existing.perfil;
          if (existing.matricula) row.matricula = existing.matricula;
        }
        if (entity.table === 'rm_users' && typeof row.matricula === 'string' && !row.matricula.trim()) row.matricula = null;
        prepared.push({ raw, row, existing, onConflict: existing ? 'id' : 'bubble_id' });
      } catch (error) { await onQuarantine(raw, message(error)); }
    }
    const pending = await this.pendingIds(prepared);
    const groups = new Map<string, Prepared[]>();
    for (const item of prepared) {
      if (this.guardedIds(item).some(id => pending.has(id))) {
        await onQuarantine(item.raw, new Error(`Conflito pendente em ${entity.name}; exportar fila antes de aplicar Desktop.`));
        continue;
      }
      // Identical column sets prevent bulk JSON from converting omitted defaults
      // to explicit nulls. defaultToNull:false preserves INSERT defaults as well.
      const key = `${item.onConflict}:${Object.keys(item.row).sort().join(',')}`;
      const group = groups.get(key) || [];
      group.push(item); groups.set(key, group);
    }
    const changed: Prepared[] = [];
    for (const group of groups.values()) for (const page of chunks(group, 100)) changed.push(...await this.persist(entity, page, onQuarantine));
    await this.finishLinks(entity, changed, sequenced);
    stats.loaded = changed.length;
    return stats;
  }
}
