"""Preservation-checked 054 release; offline generator, rollback by default.

Reuse the immutable 053 baseline collector, not its migration or release envelope.
The new manifest pins the ledger and the only four permitted mapping triggers.
"""
import hashlib
import json
import re
from pathlib import Path
import prepare_workshop_ownership_release as previous

ROOT=previous.ROOT
SOURCE=ROOT/'migrations/054_rm_workshop_origin_retention.sql'
MANIFEST=ROOT/'workshops/origin-054-manifest.json'
NAMES=['workshop_object_origins','workshop_origin_retirements']
FUNCTIONS=['workshop_origin_immutable_v1','workshop_capture_origin_v1','workshop_assert_origin_v1','workshop_origin_readiness_v1']
MAPPING_TRIGGERS=['workshop_project_origin','workshop_cell_origin','workshop_project_origin_no_truncate','workshop_cell_origin_no_truncate']
literal=previous.literal

def sql_array(values):return 'array['+','.join(map(literal,values))+']'
MANIFEST_QUERY=previous.MANIFEST_QUERY.replace(sql_array(previous.NAMES),sql_array(NAMES)).replace(sql_array(previous.FUNCTIONS),sql_array(FUNCTIONS))
MANIFEST_QUERY=MANIFEST_QUERY.removesuffix(') as manifest')+", 'mapping_triggers',(select jsonb_agg(pg_get_triggerdef(t.oid) order by t.tgname) from pg_trigger t where t.tgrelid in('rm_private.workshop_project_ownership'::regclass,'rm_private.workshop_cell_ownership'::regclass) and t.tgname=any("+sql_array(MAPPING_TRIGGERS)+"))) as manifest"
BEFORE=previous.BEFORE
AFTER=previous.AFTER
start=AFTER.index("  case when b.oid=")
end=AFTER.index("\n then raise exception 'Old function",start)
AFTER=AFTER[:start]+"  to_jsonb(p) is distinct from b.shape or pg_get_functiondef(p.oid) is distinct from b.definition)"+AFTER[end:]
start=AFTER.index('   and not(t.tgisinternal')
end=AFTER.index("\n then raise exception 'Unexpected new legacy trigger'",start)
AFTER=AFTER[:start]+"""   and not(
    (not t.tgisinternal and t.tgrelid in('rm_private.workshop_project_ownership'::regclass,'rm_private.workshop_cell_ownership'::regclass)
     and t.tgname=any(__TRIGGERS__))
    or(t.tgisinternal and t.tgconstraint in(select oid from pg_constraint where conrelid='rm_private.workshop_object_origins'::regclass
     and contype='f' and confrelid='rm_private.workshop_references'::regclass))))""".replace('__TRIGGERS__',sql_array(MAPPING_TRIGGERS))+AFTER[end:]
AFTER=AFTER.replace(sql_array(previous.NAMES),sql_array(NAMES))
AFTER=AFTER.replace("  if cnt<>0 or not r.relrowsecurity", "  if not r.relrowsecurity")
AFTER=AFTER.replace('New tables must be empty/private','New tables must be private')
AFTER=AFTER.replace(sql_array(previous.FUNCTIONS[:-1]),sql_array(FUNCTIONS))
AFTER=AFTER.replace('count(*)+4 from ow_old_tables','count(*)+2 from ow_old_tables').replace('count(*)+3 from ow_old_functions','count(*)+4 from ow_old_functions')
AFTER=AFTER.replace(' __MANIFEST_CHECK__',"""
 if exists(select 1 from pg_constraint k where k.conrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='constraint' and b.oid=k.oid))
 or exists(select 1 from pg_index i where i.indrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='index' and b.oid=i.indexrelid))
 or exists(select 1 from pg_attrdef d where d.adrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='default' and b.oid=d.oid))
 then raise exception 'Unexpected legacy constraint/index/default';end if;
 if exists(select 1 from rm_private.workshop_origin_retirements)
 or exists(select 1 from rm_private.workshop_object_origins where captured_from<>'existing_ownership' or database_actor<>session_user)
 or exists(select 1 from rm_private.workshop_object_origins o where not exists(
  select 1 from rm_private.workshop_project_ownership m where o.object_kind='project' and o.object_id=m.id and o.workshop_id=m.workshop_id
  union all select 1 from rm_private.workshop_cell_ownership m where o.object_kind='cell' and o.object_id=m.cell_id and o.workshop_id=m.workshop_id))
 or(select count(*) from rm_private.workshop_object_origins)<>(select count(*) from rm_private.workshop_project_ownership)+(select count(*) from rm_private.workshop_cell_ownership)
 then raise exception 'Origin seed differs from existing ownership';end if;
 __MANIFEST_CHECK__""")

def release_sql(source_sha256,manifest_sha256,*,apply=False):
    raw=SOURCE.read_bytes();manifest_bytes=MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=source_sha256 or hashlib.sha256(manifest_bytes).hexdigest()!=manifest_sha256:
        raise ValueError('Source/manifest changed after local rehearsal')
    text=raw.decode('utf-8')
    if '\r' in text or len(re.findall(r'^begin;$',text,re.M))!=1 or len(re.findall(r'^commit;$',text,re.M))!=1:raise ValueError('Unexpected SQL boundaries')
    body=re.sub(r'^begin;\n|^commit;\s*$', '',text,flags=re.M)
    manifest=json.loads(manifest_bytes)
    if sorted(t['name'] for t in manifest['tables'])!=sorted(NAMES) or sorted(f['name'] for f in manifest['functions'])!=sorted(FUNCTIONS) or len(manifest['mapping_triggers'])!=4:raise ValueError('Invalid manifest')
    query=MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')
    after=AFTER.replace('__MANIFEST_CHECK__',f"select {query} into actual;\n if actual is distinct from {literal(json.dumps(manifest))}::jsonb then raise exception 'New object manifest differs';end if;")
    old=sorted(p for p in (ROOT/'migrations').glob('*.sql') if p.name[:3]<'054')
    history_values=','.join('('+literal(p.name[:3])+','+literal(hashlib.sha256(p.read_bytes()).hexdigest())+')' for p in old)
    guard=f"""create temporary table ow_expected_history(version text,sha text) on commit drop;
insert into ow_expected_history values {history_values};
do $history$ begin
if(select array_agg(version order by version) from supabase_migrations.schema_migrations) is distinct from(select array_agg(version order by version) from ow_expected_history)
 or exists(select 1 from ow_expected_history e join supabase_migrations.schema_migrations h using(version) where
 (e.version<='017' and h.statements is distinct from '{{}}'::text[]) or(e.version>'017' and(cardinality(h.statements) is distinct from 1 or encode(sha256(convert_to(h.statements[1],'UTF8')),'hex') is distinct from e.sha)))
then raise exception 'Old migration sources differ';end if;
end;$history$;\n"""
    history="insert into supabase_migrations.schema_migrations(version,name,statements) values('054','rm_workshop_origin_retention',array["+literal(text)+"]);\n"
    history+=f"""do $final_history$ begin
if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or(select encode(sha256(convert_to(statements[1],'UTF8')),'hex') from supabase_migrations.schema_migrations where version='054') is distinct from '{source_sha256}'
then raise exception 'Final migration history differs';end if;
end;$final_history$;\n"""
    proof="select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,'old_functions_preserved',true,'roles_preserved',true,'origin_seed_matches',true,'old_tables_checked',(select count(*) from ow_old_tables),'old_functions_checked',(select count(*) from ow_old_functions),'origin_readiness',rm_private.workshop_origin_readiness_v1(),'isolation_active',false) proof;\n"
    # Acquire DDL locks before the baseline and the transaction snapshot; no
    # adoption/deletion can slip between the original mapping and its seed.
    locks='lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership in share row exclusive mode;\n'
    return "begin isolation level repeatable read;set local timezone='UTC';set local search_path='';set local lock_timeout='5s';set local statement_timeout='120s';\n"+locks+guard+BEFORE+body+after+history+proof+('commit;\n' if apply else 'rollback;\n')
