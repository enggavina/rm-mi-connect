import { createHash } from 'node:crypto';
import { z } from 'zod';

type Row = Record<string, any>;
export interface FormReviewerBootstrapLookups {
  projects: Row[]; allocations: Row[]; cells: Row[]; forms: Row[]; users: Row[];
  links: Row[]; records: Row[]; assignments: Row[];
}
export interface FormReviewerBootstrapPayload {
  id: string; bubble_id: string; legacy_source_ids: string[];
  projeto_id: string; celula_id: string; celula_projeto_id: string; form_id: string; avaliador_user_id: string;
  expected_project_updated_at: string; expected_allocation_updated_at: string;
  created_at: string; bubble_modified_at: string;
}
export interface FormReviewerBootstrapEntry {
  payload: FormReviewerBootstrapPayload;
  existing: boolean; linked: boolean; reviewer_active: boolean; reviewer_cell_linked: boolean;
  closed: boolean; approved: boolean; record_count: number; records_without_evaluator: number;
  records_with_other_evaluator: number;
}
export interface FormReviewerBootstrapQuarantine { source_ids: string[]; reason: string }
export interface FormReviewerBootstrapPlan {
  version: 1; sourceHash: string; cutoff: string; entries: FormReviewerBootstrapEntry[];
  quarantine: FormReviewerBootstrapQuarantine[];
  counts: { source: number; contexts: number; source_ids: number; existing: number; linked: number;
    unlinked: number; closed: number; approved: number; without_records: number; quarantined_rows: number };
}
const uuid = (value: unknown) => z.string().uuid().parse(value);
const bubble = (value: unknown): string => {
  if (typeof value !== 'string' || !/^\d+x\d+$/.test(value)) throw Error('Invalid Bubble ID.');
  return value;
};
const object = (value: unknown): Row => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Expected a record.');
  return value as Row;
};
const timestamp = (value: unknown): string => {
  const parsed = z.string().datetime({ offset: true }).parse(value);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/.test(parsed)
    || !Number.isFinite(Date.parse(parsed))) throw Error('Invalid timestamp.');
  // Keep the exact database string; Date would truncate microseconds.
  return parsed;
};
const micros = (value: string): bigint => {
  const fraction = value.match(/\.(\d+)(?:Z|[+-]\d{2}:\d{2})$/)?.[1] ?? '';
  return BigInt(Math.floor(Date.parse(value) / 1000)) * 1_000_000n + BigInt(fraction.padEnd(6, '0'));
};
const sameTime = (a: unknown, b: string) => { try { return micros(timestamp(a)) === micros(b); } catch { return false; } };
const contextKey = (p: string, c: string, f: string) => `${p}|${c}|${f}`;
const byBubble = (rows: Row[]) => {
  const result = new Map<string, Row>(), localIds = new Set<string>();
  for (const row of rows) if (row.bubble_id != null) {
    const key = bubble(row.bubble_id); uuid(row.id);
    if (result.has(key) || localIds.has(row.id)) throw Error('Ambiguous local Bubble crosswalk.');
    localIds.add(row.id);
    result.set(key, row);
  }
  return result;
};

/** Stable by local context, independent of export/page order or duplicate rows. */
export function formReviewerBootstrapId(projectId: string, cellId: string, formId: string): string {
  [projectId, cellId, formId].forEach(uuid);
  const namespace = Buffer.from('13b21634123643a19d811fde8ddc0706', 'hex');
  const digest = createHash('sha1').update(namespace).update(contextKey(projectId, cellId, formId)).digest().subarray(0, 16);
  digest[6] = (digest[6] & 15) | 0x50; digest[8] = (digest[8] & 63) | 0x80;
  const h = digest.toString('hex'); return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** Pure planner. Only explicit complete Bubble contexts are considered. A record
 * pointer is historical evidence, never permission to invent missing context. */
export function prepareFormReviewerBootstrap(input: unknown, lookups: FormReviewerBootstrapLookups): FormReviewerBootstrapPlan {
  const source = object(input), cutoff = timestamp(source.cutoff);
  if (!Array.isArray(source.assignments)) throw Error('Expected an assignment export.');
  const projects = byBubble(lookups.projects), cells = byBubble(lookups.cells), forms = byBubble(lookups.forms), users = byBubble(lookups.users);
  const allocations = new Map<string, Row>(), existing = new Map<string, Row>(), bySourceId = new Map<string, Row>();
  for (const row of lookups.allocations) {
    const key = `${uuid(row.projeto_id)}|${uuid(row.celula_id)}`; uuid(row.id);
    if (allocations.has(key)) throw Error('Ambiguous local allocation.'); allocations.set(key, row);
  }
  for (const row of lookups.assignments) {
    const key = contextKey(uuid(row.projeto_id), uuid(row.celula_id), uuid(row.form_id)); uuid(row.id);
    if (existing.has(key)) throw Error('Ambiguous local assignment.'); existing.set(key, row);
    for (const id of [...(row.legacy_source_ids ?? []), ...(row.bubble_id ? [row.bubble_id] : [])]) {
      bubble(id); if (bySourceId.has(id) && bySourceId.get(id)!.id !== row.id) throw Error('Ambiguous assignment provenance.'); bySourceId.set(id, row);
    }
  }
  const groups = new Map<string, Row[]>(), quarantine: FormReviewerBootstrapQuarantine[] = [], seen = new Set<string>();
  const sourceRows = source.assignments.map(object);
  for (const row of sourceRows) {
    const id = bubble(row._id); if (seen.has(id)) throw Error('Duplicate source record ID.'); seen.add(id);
    if (![row.ProjetoRM, row.Celula, row.Form].every(v => typeof v === 'string' && /^\d+x\d+$/.test(v))) {
      quarantine.push({ source_ids: [id], reason: 'missing_context' }); continue;
    }
    const key = contextKey(row.ProjetoRM, row.Celula, row.Form); groups.set(key, [...(groups.get(key) ?? []), row]);
  }
  const entries: FormReviewerBootstrapEntry[] = [];
  for (const group of groups.values()) {
    const sourceIds = group.map(row => row._id as string).sort();
    const reject = (reason: string) => quarantine.push({ source_ids: sourceIds, reason });
    if (sourceIds.length > 100) { reject('too_many_duplicate_sources'); continue; }
    const first = group[0], project = projects.get(first.ProjetoRM), cell = cells.get(first.Celula), form = forms.get(first.Form);
    if (!project) { reject('project_not_imported'); continue; }
    if (!cell || !form) { reject('unresolved_context_reference'); continue; }
    const reviewers = new Set(group.map(row => row.Aprovador));
    if (reviewers.size !== 1) { reject('conflicting_reviewers'); continue; }
    if (!first.Aprovador) { reject('missing_reviewer'); continue; }
    const reviewer = users.get(first.Aprovador);
    if (!reviewer) { reject('unresolved_reviewer'); continue; }
    const allocation = allocations.get(`${project.id}|${cell.id}`);
    if (!allocation) { reject('allocation_missing'); continue; }
    let created: string[], modified: string[];
    try {
      created = group.map(row => timestamp(row['Created Date'])); modified = group.map(row => timestamp(row['Modified Date']));
      if (modified.some(value => micros(value) > micros(cutoff))) throw Error('Source exceeds cutoff.');
      if (created.some((value, index) => micros(value) > micros(modified[index]))) throw Error('Invalid source chronology.');
    } catch { reject('invalid_source_dates_or_cutoff'); continue; }
    created.sort((a, b) => micros(a) < micros(b) ? -1 : micros(a) > micros(b) ? 1 : a.localeCompare(b));
    modified.sort((a, b) => micros(a) > micros(b) ? -1 : micros(a) < micros(b) ? 1 : a.localeCompare(b));
    const key = contextKey(project.id, cell.id, form.id), current = existing.get(key);
    const payload: FormReviewerBootstrapPayload = {
      id: current?.id ?? formReviewerBootstrapId(project.id, cell.id, form.id), bubble_id: sourceIds[0], legacy_source_ids: sourceIds,
      projeto_id: project.id, celula_id: cell.id, celula_projeto_id: allocation.id, form_id: form.id, avaliador_user_id: reviewer.id,
      expected_project_updated_at: timestamp(project.updated_at), expected_allocation_updated_at: timestamp(allocation.updated_at),
      created_at: created[0], bubble_modified_at: modified[0],
    };
    if (sourceIds.some(id => bySourceId.has(id) && bySourceId.get(id)!.id !== payload.id)) { reject('provenance_used_by_other_context'); continue; }
    if (current && (current.sync_source !== 'bubble' || current.celula_projeto_id !== allocation.id || current.avaliador_user_id !== reviewer.id
      || current.created_by_id != null || current.updated_by_id != null
      || current.bubble_id !== payload.bubble_id || JSON.stringify([...(current.legacy_source_ids ?? [])].sort()) !== JSON.stringify(sourceIds)
      || !sameTime(current.created_at, payload.created_at) || !sameTime(current.bubble_modified_at, payload.bubble_modified_at))) {
      reject('existing_assignment_conflict'); continue;
    }
    const records = lookups.records.filter(row => row.projeto_id === project.id && row.celula_id === cell.id && row.form_id === form.id);
    entries.push({ payload, existing: !!current, linked: (allocation.forms_ids ?? []).includes(form.id), reviewer_active: reviewer.status === 'ativo',
      reviewer_cell_linked: lookups.links.some(link => link.celula_id === cell.id && link.identidade_id === reviewer.id),
      closed: !!project.data_real_de_entrega || ['cancelado', 'finalizando_para_faturar'].includes(project.status_pcp),
      approved: records.some(row => row.status === 'aprovado'), record_count: records.length,
      records_without_evaluator: records.filter(row => !row.avaliador_user_id).length,
      records_with_other_evaluator: records.filter(row => row.avaliador_user_id && row.avaliador_user_id !== reviewer.id).length });
  }
  entries.sort((a, b) => a.payload.id.localeCompare(b.payload.id)); quarantine.sort((a, b) => a.source_ids[0].localeCompare(b.source_ids[0]));
  const normalizedSource = sourceRows.map(row => Object.fromEntries(['_id', 'ProjetoRM', 'Celula', 'Form', 'Aprovador', 'Created Date', 'Modified Date'].map(key => [key, row[key] ?? null])))
    .sort((a, b) => String(a._id).localeCompare(String(b._id)));
  return { version: 1, cutoff, sourceHash: createHash('sha256').update(JSON.stringify({ cutoff, assignments: normalizedSource })).digest('hex'), entries, quarantine,
    counts: { source: sourceRows.length, contexts: entries.length, source_ids: entries.reduce((n, entry) => n + entry.payload.legacy_source_ids.length, 0),
      existing: entries.filter(entry => entry.existing).length, linked: entries.filter(entry => entry.linked).length, unlinked: entries.filter(entry => !entry.linked).length,
      closed: entries.filter(entry => entry.closed).length, approved: entries.filter(entry => entry.approved).length,
      without_records: entries.filter(entry => !entry.record_count).length, quarantined_rows: quarantine.reduce((n, item) => n + item.source_ids.length, 0) } };
}

/** Only GET to this application's Live Data API. A connector export may be used
 * as input when the endpoint is not publicly exposed; there is no write fallback. */
export async function readBubbleFormReviewerAssignments(config: { baseUrl: string; token: string; cutoff: string; fetcher?: typeof fetch }): Promise<Row[]> {
  const base = new URL(config.baseUrl), cutoff = timestamp(config.cutoff);
  if (base.protocol !== 'https:' || base.hostname !== 'rmmi.bubbleapps.io' || base.pathname.replace(/\/$/, '') !== '/api/1.1'
    || base.username || base.password || base.search || base.hash || base.port) throw Error('Expected the pinned Bubble Live Data API.');
  const rows: Row[] = []; let cursor = 0;
  for (let page = 0; page < 1000; page++) {
    const url = new URL(`${base.origin}/api/1.1/obj/aprovacao_form`);
    url.search = new URLSearchParams({ cursor: String(cursor), limit: '100', sort_field: 'Modified Date', descending: 'false',
      constraints: JSON.stringify([{ key: 'Modified Date', constraint_type: 'less than', value: cutoff }]) }).toString();
    const response = await (config.fetcher ?? fetch)(url, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(30000), headers: { Authorization: `Bearer ${config.token}` } });
    if (!response.ok) throw Error(`Bubble assignment export HTTP ${response.status}.`);
    const body = await response.json(), result = body?.response;
    if (!result || !Array.isArray(result.results) || !Number.isInteger(result.remaining) || result.remaining < 0
      || result.cursor !== cursor || !result.results.length && result.remaining > 0) throw Error('Invalid or stalled Bubble assignment page.');
    rows.push(...result.results.map(object)); if (result.remaining === 0) return rows; cursor += result.results.length;
  }
  throw Error('Bubble assignment export exceeded its explicit page limit.');
}

/** Reviewable SQL only. Existing RM/private data and old assignments are compared
 * in full; only the service-only insert primitive is called. Rehearsal rolls back. */
export function formReviewerBootstrapSql(plan: FormReviewerBootstrapPlan, apply = false): string {
  if (plan.version !== 1 || !/^[0-9a-f]{64}$/.test(plan.sourceHash)) throw Error('Invalid reviewed bootstrap plan.');
  if (!Array.isArray(plan.entries) || plan.entries.length > 100000) throw Error('Invalid reviewed bootstrap entries.');
  const payload = Buffer.from(JSON.stringify(plan.entries.map(entry => entry.payload)), 'utf8').toString('base64');
  return `begin isolation level repeatable read;
set local lock_timeout='10s';
set local statement_timeout='120s';
do $$ begin
 if (select require_sso from rm_private.sso_settings where singleton) is distinct from true
  or not exists(select 1 from supabase_migrations.schema_migrations where version='026') then raise exception 'Unexpected EM bootstrap baseline'; end if;
end $$;
create temporary table reviewer_bootstrap_before(schema_name text,table_name text,row_count bigint,state_hash text) on commit drop;
create temporary table reviewer_assignments_before on commit drop as select id,to_jsonb(a) as row from public.rm_form_reviewer_assignments a;
create temporary table reviewer_bootstrap_expected(id uuid primary key,payload jsonb not null) on commit drop;
insert into reviewer_bootstrap_expected select (value->>'id')::uuid,value
 from jsonb_array_elements(convert_from(decode('${payload}','base64'),'UTF8')::jsonb);
do $$ declare t record; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\\_%' escape '\\' and c.relname<>'rm_form_reviewer_assignments') or n.nspname='rm_private')
  order by n.nspname,c.relname loop
  execute format('insert into reviewer_bootstrap_before select %L,%L,count(*),md5(coalesce(string_agg(md5(to_jsonb(r)::text),'''' order by md5(to_jsonb(r)::text)),'''')) from %I.%I r',t.nspname,t.relname,t.nspname,t.relname);
 end loop;
 if (select count(*) from reviewer_bootstrap_before)<>67 then raise exception 'Unexpected complete preservation scope'; end if;
end $$;
do $reviewer_bootstrap$
declare items jsonb:=convert_from(decode('${payload}','base64'),'UTF8')::jsonb; item jsonb; result jsonb;
begin
 for item in select value from jsonb_array_elements(items) order by value->>'projeto_id',value->>'id' loop
  result:=public.rm_bootstrap_form_reviewer_assignment_v1(item);
  if result->>'status' not in ('inserted','existing') or result->>'id' is distinct from item->>'id'
   or result->>'projeto_id' is distinct from item->>'projeto_id' or result->>'celula_projeto_id' is distinct from item->>'celula_projeto_id'
   or result->>'form_id' is distinct from item->>'form_id' then raise exception 'Bootstrap result differs from reviewed assignment'; end if;
 end loop;
end $reviewer_bootstrap$;
do $$ declare t record; n bigint; h text; expected public.rm_form_reviewer_assignments%rowtype; actual public.rm_form_reviewer_assignments%rowtype;
 item jsonb; before_count bigint; pending_count bigint; begin
 for t in select * from reviewer_bootstrap_before loop
  execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(r)::text),'''' order by md5(to_jsonb(r)::text)),'''')) from %I.%I r',t.schema_name,t.table_name) into n,h;
  if n<>t.row_count or h<>t.state_hash then raise exception 'Bootstrap changed unrelated RM/private data'; end if;
 end loop;
 if exists(select 1 from reviewer_assignments_before b left join public.rm_form_reviewer_assignments a on a.id=b.id where to_jsonb(a) is distinct from b.row) then
  raise exception 'Bootstrap changed an existing assignment'; end if;
 for item in select payload from reviewer_bootstrap_expected loop
  expected:=jsonb_populate_record(null::public.rm_form_reviewer_assignments,item);
  select * into actual from public.rm_form_reviewer_assignments where id=expected.id;
  if not found or row(actual.bubble_id,actual.legacy_source_ids,actual.projeto_id,actual.celula_id,actual.celula_projeto_id,
    actual.form_id,actual.avaliador_user_id,actual.created_at,actual.bubble_modified_at,actual.sync_source,actual.created_by_id,actual.updated_by_id)
   is distinct from row(expected.bubble_id,expected.legacy_source_ids,expected.projeto_id,expected.celula_id,expected.celula_projeto_id,
    expected.form_id,expected.avaliador_user_id,expected.created_at,expected.bubble_modified_at,'bubble'::text,null::uuid,null::uuid) then
   raise exception 'Imported assignment differs from its reviewed context or provenance'; end if;
 end loop;
 select count(*) into before_count from reviewer_assignments_before;
 select count(*) into pending_count from reviewer_bootstrap_expected e where not exists(select 1 from reviewer_assignments_before b where b.id=e.id);
 if (select count(*) from public.rm_form_reviewer_assignments)<>before_count+pending_count
  or exists(select 1 from public.rm_form_reviewer_assignments a where not exists(select 1 from reviewer_assignments_before b where b.id=a.id)
    and not exists(select 1 from reviewer_bootstrap_expected e where e.id=a.id)) then
  raise exception 'Bootstrap created a different assignment set'; end if;
end $$;
select '${plan.sourceHash}' source_hash,
 (select count(*) from public.rm_form_reviewer_assignments) actual_assignment_count,
 (select count(*) from public.rm_form_reviewer_assignments a join reviewer_bootstrap_expected e on e.id=a.id) imported_contexts,
 (select coalesce(sum(cardinality(a.legacy_source_ids)),0) from public.rm_form_reviewer_assignments a join reviewer_bootstrap_expected e on e.id=a.id) preserved_source_ids,
 (select count(*) from reviewer_bootstrap_expected e where not exists(select 1 from reviewer_assignments_before b where b.id=e.id)) inserted_contexts,
 (select count(*) from reviewer_assignments_before) preserved_existing_assignments,
 (select count(*) from reviewer_bootstrap_before)+case when (select count(*) from reviewer_bootstrap_expected e where not exists(select 1 from reviewer_assignments_before b where b.id=e.id))=0 then 1 else 0 end preserved_table_snapshots;
${apply ? 'commit;' : 'rollback;'}
`;
}
