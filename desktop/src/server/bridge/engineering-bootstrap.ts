import { createHash } from 'node:crypto';

type Row = Record<string, any>;
export interface EngineeringLookups {
  matrices: Row[]; cells: Row[]; users: Row[]; options: Row[]; photos: Row[]; stages: Row[];
}
export interface EngineeringBootstrapGroup {
  parent: { id: string; bubble_id: string; celula_id: string; tipo_equipamento_id: string; updated_at: string };
  photos: Row[]; stages: Row[];
}
export interface EngineeringBootstrapPlan {
  version: 1; sourceHash: string; cutoff: string; groups: EngineeringBootstrapGroup[];
  counts: { photos: number; stages: number; parents: number };
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const uuid = (value: unknown): string => {
  if (typeof value !== 'string' || !uuidPattern.test(value)) throw Error('Invalid local reference.');
  return value;
};
const object = (value: unknown): Row => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Expected a record.');
  return value as Row;
};
const date = (value: unknown): string => {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw Error('Invalid source date.');
  return new Date(value).toISOString();
};
const empty = (value: unknown) => value == null || value === '' || (Array.isArray(value) && !value.length);
const text = (value: unknown): string | null => {
  if (empty(value)) return null;
  if (typeof value !== 'string') throw Error('Invalid text.');
  return value;
};
const bool = (value: unknown, fallback: boolean): boolean => {
  if (value == null) return fallback;
  if (typeof value !== 'boolean') throw Error('Invalid boolean.');
  return value;
};
const integer = (value: unknown): number | null => {
  if (value == null) return null;
  if (typeof value !== 'number' || !Number.isInteger(value) || value < -2147483648 || value > 2147483647) throw Error('Invalid integer.');
  return value;
};
const byBubble = (rows: Row[]) => {
  const map = new Map<string, Row>();
  for (const row of rows) if (row.bubble_id) {
    if (map.has(row.bubble_id)) throw Error('Ambiguous Bubble reference.');
    uuid(row.id); map.set(row.bubble_id, row);
  }
  return map;
};
/** A fixed namespace keeps reruns stable without depending on a live database. */
export function engineeringBootstrapId(table: 'rm_fotos' | 'rm_aprovacoes_etapas', bubbleId: string): string {
  const namespace = Buffer.from('f167bbf03d104416a0f98cf66f47318b', 'hex');
  const digest = createHash('sha1').update(namespace).update(`${table}:${bubbleId}`).digest().subarray(0, 16);
  digest[6] = (digest[6] & 15) | 0x50; digest[8] = (digest[8] & 63) | 0x80;
  const h = digest.toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** Strict, insert-only recovery of unallocated Bubble models. No identity, ACL,
 * captured media or operational project is created or rewritten here. */
export function prepareEngineeringBootstrap(input: unknown, lookups: EngineeringLookups): EngineeringBootstrapPlan {
  const source = object(input), cutoff = date(source.cutoff);
  if (!Array.isArray(source.photos) || !Array.isArray(source.stages)) throw Error('Expected photo and approval model lists.');
  const matrices = byBubble(lookups.matrices), cells = byBubble(lookups.cells), users = byBubble(lookups.users);
  const existingPhotos = byBubble(lookups.photos), existingStages = byBubble(lookups.stages);
  const option = (set: string, value: unknown): string | null => {
    if (empty(value)) return null;
    const matches = lookups.options.filter(row => row.option_set_key === set && (row.option_key === value || row.bubble_display === value));
    if (matches.length !== 1) throw Error(`Unknown or ambiguous option: ${set}.`);
    return matches[0].option_key;
  };
  const ref = (map: Map<string, Row>, value: unknown, nullable = false): string | null => {
    if (nullable && empty(value)) return null;
    if (typeof value !== 'string' || !map.has(value)) throw Error('Unresolved source reference.');
    return uuid(map.get(value)!.id);
  };
  const refs = (value: unknown): string[] => {
    if (value == null) return [];
    if (!Array.isArray(value)) throw Error('Invalid source reference list.');
    // Preserve legacy order, duplicates and singular approvers. Memberships are
    // reviewed explicitly in the UI, never granted by a data import.
    return value.map(item => ref(users, item)!);
  };
  const groups = new Map<string, EngineeringBootstrapGroup>();
  const seen = new Set<string>();
  const common = (raw: Row, table: 'rm_fotos' | 'rm_aprovacoes_etapas', existing: Map<string, Row>) => {
    if (typeof raw._id !== 'string' || !/^\d+x\d+$/.test(raw._id)) throw Error('Invalid Bubble ID.');
    const key = `${table}:${raw._id}`;
    if (seen.has(key)) throw Error('Duplicate source model.'); seen.add(key);
    if (!empty(raw.ProjetoRM) || !empty(raw.celula_projeto_id) || !empty(raw.Celula_Projeto)) throw Error('Allocated records are outside this bootstrap.');
    if (!empty(raw.foto) || !empty(raw.fotos) || !empty(raw.foto_url) || !empty(raw.fotos_arquivos_urls) || !empty(raw['Aprovado por']) || !empty(raw['data_aprovação'])) throw Error('Captured media or approval is outside this bootstrap.');
    const parent = matrices.get(String(raw.Celula_Tipo_Equipamento));
    if (!parent) throw Error('Unresolved engineering parent.');
    for (const field of ['id', 'celula_id', 'tipo_equipamento_id']) uuid(parent[field]);
    if (parent.sync_source === 'supabase') throw Error('Locally managed parent cannot be bootstrapped.');
    date(parent.updated_at);
    let group = groups.get(parent.id);
    if (!group) {
      group = { parent: { id: parent.id, bubble_id: parent.bubble_id, celula_id: parent.celula_id, tipo_equipamento_id: parent.tipo_equipamento_id, updated_at: parent.updated_at }, photos: [], stages: [] };
      groups.set(parent.id, group);
    }
    const known = existing.get(raw._id);
    if (known && (known.projeto_id != null || known.celula_projeto_id != null || known.celula_tipo_equipamento_id !== parent.id || !['etl', 'bubble'].includes(known.sync_source))) throw Error('Existing model has incompatible ownership or scope.');
    const modified = date(raw['Modified Date']);
    if (Date.parse(modified) > Date.parse(cutoff)) throw Error('Model exceeds export cutoff.');
    return { group, row: { id: known ? uuid(known.id) : engineeringBootstrapId(table, raw._id), bubble_id: raw._id,
      projeto_id: null, celula_projeto_id: null, celula_tipo_equipamento_id: parent.id,
      created_at: date(raw['Created Date']), bubble_modified_at: modified, sync_source: 'etl' } as Row };
  };
  for (const value of source.photos) {
    const raw = object(value), { group, row } = common(raw, 'rm_fotos', existingPhotos);
    const cell = ref(cells, raw.Celula);
    if (cell !== group.parent.celula_id) throw Error('Photo cell differs from its model parent.');
    if (!text(raw.Titulo)?.trim()) throw Error('Photo title is required.');
    group.photos.push({ ...row, celula_id: cell, cadastro_foto_id: null,
      categoria_foto: option('categoriafoto', raw['Categoria Foto']), etapa: option('etapa', raw.Etapa),
      tipo_recebimento: option('rmtipofoto', raw.tipo), identificador_foto_key: text(raw.identificador_foto_key),
      titulo: raw.Titulo, descricao: text(raw['descrição']), legenda: text(raw.Legenda), tag: text(raw.Tag),
      numero: integer(raw.Numero), numero_foto_complementar: integer(raw['Numero foto complementar']),
      lixeira: bool(raw.Lixeira, false), selecao_relatorio: bool(raw['Seleçao_relatorio'], false) });
  }
  for (const value of source.stages) {
    const raw = object(value), { group, row } = common(raw, 'rm_aprovacoes_etapas', existingStages);
    const origin = ref(cells, raw.celula_origem);
    if (origin !== group.parent.celula_id) throw Error('Stage origin differs from its model parent.');
    const status = option('statusetapa', raw.status) ?? 'nulo';
    if (status !== 'nulo') throw Error('Executed approval is outside this bootstrap.');
    group.stages.push({ ...row, celula_origem_id: origin, celula_destino_id: ref(cells, raw.celula_destino, true),
      bloquear_avanco_sem_aprov: bool(raw.Vinculo_entre_celulas, false), status,
      status_cel_proj: option('status_cel_proj', raw.status_cel_proj), aprovador_id: ref(users, raw.Aprovador, true),
      aprovadores_ids: refs(raw.Aprovadores), aprovadores_retorno_ids: refs(raw.Aprovadores_retorno), ativo: true });
  }
  const sorted = [...groups.values()].sort((a, b) => a.parent.id.localeCompare(b.parent.id));
  for (const group of sorted) for (const rows of [group.photos, group.stages]) rows.sort((a, b) => a.id.localeCompare(b.id));
  return { version: 1, sourceHash: createHash('sha256').update(JSON.stringify(input)).digest('hex'), cutoff, groups: sorted,
    counts: { photos: source.photos.length, stages: source.stages.length, parents: sorted.length } };
}

const photoColumns = ['id','bubble_id','projeto_id','celula_projeto_id','celula_tipo_equipamento_id','created_at','bubble_modified_at','sync_source','celula_id','cadastro_foto_id','categoria_foto','etapa','tipo_recebimento','identificador_foto_key','titulo','descricao','legenda','tag','numero','numero_foto_complementar','lixeira','selecao_relatorio'];
const stageColumns = ['id','bubble_id','projeto_id','celula_projeto_id','celula_tipo_equipamento_id','created_at','bubble_modified_at','sync_source','celula_origem_id','celula_destino_id','bloquear_avanco_sem_aprov','status','status_cel_proj','aprovador_id','aprovadores_ids','aprovadores_retorno_ids','ativo'];
/** One transaction per parent: take the pair lock BEFORE any model row lock.
 * Existing rows must be identical; bootstrap never overwrites them. */
export function engineeringBootstrapSql(group: EngineeringBootstrapGroup, apply = false): string {
  const payload = Buffer.from(JSON.stringify(group), 'utf8').toString('base64');
  const block = (table: string, key: string, columns: string[], pass: 'check' | 'insert') => {
    const comparison = columns.map(column => `current_row.${column}`).join(',');
    const incoming = columns.map(column => `incoming.${column}`).join(',');
    const executionGuard = table === 'rm_fotos'
      ? 'current_row.foto_url is not null or cardinality(current_row.fotos_arquivos_urls)>0'
      : 'current_row.aprovado_por_id is not null or current_row.data_aprovacao is not null';
    return `for item in select value from jsonb_array_elements(payload->'${key}') loop
      incoming := jsonb_populate_record(null::public.${table},item);
      select * into current_row from public.${table} where id=incoming.id or bubble_id=incoming.bubble_id;
      if found then
        if row(${comparison}) is distinct from row(${incoming})
          or ${executionGuard} then
          raise exception 'Bootstrap refuses to overwrite an existing model'; end if;
      else
        ${pass === 'check' ? 'pending := true;' : `insert into public.${table}(${columns.join(',')}) values(${incoming});`}
      end if;
    end loop;`;
  };
  // Separate typed blocks avoid accepting arbitrary table names from source data.
  const photoBlock = (pass: 'check' | 'insert') => `declare incoming public.rm_fotos%rowtype; current_row public.rm_fotos%rowtype; item jsonb; begin ${block('rm_fotos','photos',photoColumns,pass)} end;`;
  const stageBlock = (pass: 'check' | 'insert') => `declare incoming public.rm_aprovacoes_etapas%rowtype; current_row public.rm_aprovacoes_etapas%rowtype; item jsonb; begin ${block('rm_aprovacoes_etapas','stages',stageColumns,pass)} end;`;
  return `begin;
set local lock_timeout='10s';
set local statement_timeout='45s';
do $engineering_bootstrap$
declare payload jsonb := convert_from(decode('${payload}','base64'),'UTF8')::jsonb;
  parent public.rm_celula_tipos_equipamento%rowtype; pending boolean := false;
begin
  if (select require_sso from rm_private.sso_settings where singleton) is distinct from true
    or not exists(select 1 from supabase_migrations.schema_migrations where version='018') then
    raise exception 'Unexpected migration or SSO state'; end if;
  perform rm_private.engineering_pair_lock((payload#>>'{parent,celula_id}')::uuid,(payload#>>'{parent,tipo_equipamento_id}')::uuid,true);
  select * into parent from public.rm_celula_tipos_equipamento where id=(payload#>>'{parent,id}')::uuid for update;
  if not found or parent.bubble_id is distinct from payload#>>'{parent,bubble_id}'
    or parent.celula_id is distinct from (payload#>>'{parent,celula_id}')::uuid
    or parent.tipo_equipamento_id is distinct from (payload#>>'{parent,tipo_equipamento_id}')::uuid
    or parent.sync_source not in ('etl','bubble') then raise exception 'Model parent changed'; end if;
  ${photoBlock('check')}
  ${stageBlock('check')}
  if pending and parent.updated_at is distinct from (payload#>>'{parent,updated_at}')::timestamptz then
    raise exception 'Engineering changed since the export preflight'; end if;
  ${photoBlock('insert')}
  ${stageBlock('insert')}
end $engineering_bootstrap$;
${apply ? 'commit;' : 'rollback;'}
`;
}
