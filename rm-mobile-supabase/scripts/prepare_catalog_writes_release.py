"""057 preservation envelope. Offline generator; rollback by default."""
import hashlib
import json
import re
import prepare_workshop_ownership_release as baseline
from prepare_workshop_reference_release import array

ROOT=baseline.ROOT
SOURCE=ROOT/'migrations/057_rm_web_catalog_workshop_writes.sql'
MANIFEST=ROOT/'workshops/catalog-writes-057-manifest.json'
NAMES=['catalog_workshop_write_settings','catalog_workshop_write_permits']
FUNCTIONS=['rm_sso_catalog_workshop_permit_v1','web_mutate_scoped_catalog_v1','activate_catalog_workshop_writes_v1','rm_web_mutate_v1']
literal=baseline.literal
OLD='return rm_private.web_mutate_core_v1(p_client_submission_id,p_operation,p_payload);'
NEW='return rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id,p_operation,p_payload);'
MANIFEST_QUERY=baseline.MANIFEST_QUERY.replace(array(baseline.NAMES),array(NAMES)).replace(array(baseline.FUNCTIONS),array(FUNCTIONS))
MANIFEST_QUERY=MANIFEST_QUERY.replace("p.pronamespace='rm_private'::regnamespace", "p.pronamespace in('rm_private'::regnamespace,'public'::regnamespace)")
BEFORE=baseline.BEFORE
AFTER=baseline.AFTER.split(' __MANIFEST_CHECK__')[0]
start=AFTER.index('  case when b.oid=');end=AFTER.index("\n then raise exception 'Old function",start)
AFTER=AFTER[:start]+"""  case when b.oid='public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure then
   (to_jsonb(p)-'prosrc') is distinct from(b.shape-'prosrc') or p.prosrc is distinct from replace(b.shape->>'prosrc',__OLD__,__NEW__)
  else to_jsonb(p) is distinct from b.shape or pg_get_functiondef(p.oid) is distinct from b.definition end)""".replace('__OLD__',literal(OLD)).replace('__NEW__',literal(NEW))+AFTER[end:]
start=AFTER.index('   and not(t.tgisinternal');end=AFTER.index("\n then raise exception 'Unexpected new legacy trigger'",start)
AFTER=AFTER[:start]+"""   and not(t.tgisinternal and t.tgconstraint in(select oid from pg_constraint where contype='f'
    and conrelid='rm_private.catalog_workshop_write_permits'::regclass
    and confrelid in('rm_private.sso_sessions'::regclass,'rm_private.workshop_references'::regclass))))"""+AFTER[end:]
AFTER+=r"""
 if exists(select 1 from pg_constraint k where k.conrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='constraint' and b.oid=k.oid))
 or exists(select 1 from pg_index i where i.indrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='index' and b.oid=i.indexrelid))
 or exists(select 1 from pg_attrdef d where d.adrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='default' and b.oid=d.oid))
 then raise exception 'Unexpected legacy constraint/index/default';end if;
 __MANIFEST_CHECK__
 if exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
  where c.relnamespace='rm_private'::regnamespace and c.relname=any(__NAMES__) and
  (a.grantee<>c.relowner or c.relowner<>current_user::regrole or not c.relrowsecurity))
 or exists(select 1 from pg_policy where polrelid in('rm_private.catalog_workshop_write_permits'::regclass,'rm_private.catalog_workshop_write_settings'::regclass))
 then raise exception 'New scope metadata exposed';end if;
 if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.pronamespace='rm_private'::regnamespace and p.proname in('web_mutate_scoped_catalog_v1','activate_catalog_workshop_writes_v1')
  and(a.grantee<>p.proowner or p.proowner<>current_user::regrole))
 or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.oid='public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure
  and(a.grantee not in(p.proowner,'service_role'::regrole) or p.proowner<>current_user::regrole))
 or not has_function_privilege('service_role','public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)','execute')
 then raise exception 'New scope function grants differ';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and(n.nspname in('rm_private','storage') or n.nspname='public' and c.relname like 'rm_%' escape ''
 or n.nspname='auth' and c.relname in('users','identities','sessions','mfa_factors')))<>(select count(*)+2 from ow_old_tables)
 then raise exception 'Unexpected table set';end if;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or n.nspname='public' and p.proname like 'rm_%' escape '')<>(select count(*)+3 from ow_old_functions)
 then raise exception 'Unexpected function set';end if;
 if(select count(*) from rm_private.catalog_workshop_write_settings)<>1 or exists(select 1 from rm_private.catalog_workshop_write_settings
  where enforced or runtime_sha is not null or deployment_id is not null or activated_at is not null or database_actor is not null)
 or exists(select 1 from rm_private.catalog_workshop_write_permits) then raise exception 'Scope must be staged disabled and empty';end if;
end;$verify$;
""".replace('__NAMES__',array(NAMES))

def release_sql(source_sha256,manifest_sha256,*,apply=False):
    raw=SOURCE.read_bytes();manifest_bytes=MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=source_sha256 or hashlib.sha256(manifest_bytes).hexdigest()!=manifest_sha256:raise ValueError('Tested source or manifest changed')
    source=raw.decode('utf-8');manifest=json.loads(manifest_bytes)
    if '\r' in source or len(re.findall(r'^begin;$',source,re.M))!=1 or len(re.findall(r'^commit;$',source,re.M))!=1:raise ValueError('Unexpected boundaries')
    if sorted(t['name'] for t in manifest['tables'])!=sorted(NAMES) or sorted(f['name'] for f in manifest['functions'])!=sorted(FUNCTIONS):raise ValueError('Incomplete manifest')
    body=re.sub(r'^begin;\n|^commit;\s*$','',source,flags=re.M)
    query=MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')
    after=AFTER.replace('__MANIFEST_CHECK__',f"select {query} into actual;if actual is distinct from {literal(json.dumps(manifest))}::jsonb then raise exception 'New object manifest differs';end if;")
    old=sorted(p for p in (ROOT/'migrations').glob('*.sql') if p.name[:3]<'057')
    values=','.join('('+literal(p.name[:3])+','+literal(hashlib.sha256(p.read_bytes()).hexdigest())+')' for p in old)
    history=f"""create temporary table ow_expected_history(version text,sha text) on commit drop;insert into ow_expected_history values {values};
do $history$ begin
if(select array_agg(version order by version) from supabase_migrations.schema_migrations) is distinct from(select array_agg(version order by version) from ow_expected_history)
 or exists(select 1 from ow_expected_history e join supabase_migrations.schema_migrations h using(version) where
 (e.version<='017' and h.statements is distinct from '{{}}'::text[]) or(e.version>'017' and(cardinality(h.statements) is distinct from 1 or encode(sha256(convert_to(h.statements[1],'UTF8')),'hex') is distinct from e.sha)))
then raise exception 'Old migration sources differ';end if;end;$history$;
"""
    final="insert into supabase_migrations.schema_migrations(version,name,statements) values('057','rm_web_catalog_workshop_writes',array["+literal(source)+"]);\n"
    final+=f"""do $final_history$ begin
if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or(select encode(sha256(convert_to(statements[1],'UTF8')),'hex') from supabase_migrations.schema_migrations where version='057') is distinct from '{source_sha256}'
then raise exception 'Final migration history differs';end if;end;$final_history$;
"""
    proof="select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,'exact_dispatch_only',true,'roles_preserved',true,'staged_disabled',true,'old_tables_checked',(select count(*) from ow_old_tables),'old_functions_checked',(select count(*) from ow_old_functions),'full_isolation_active',false) proof;\n"
    return "begin isolation level repeatable read;set local search_path='';set local timezone='UTC';set local lock_timeout='5s';set local statement_timeout='180s';\n"+history+BEFORE+body+after+final+proof+('commit;\n' if apply else 'rollback;\n')
