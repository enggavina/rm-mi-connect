"""Generate the preservation-checked 053 envelope. No network or credentials.

The new-object manifest is captured in a disposable local PostgreSQL database.
Both source and manifest hashes must match the independently exercised release.
Rollback is the default. Existing migration sources are never edited.
"""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'migrations/053_rm_workshop_ownership_foundation.sql'
MANIFEST=ROOT/'workshops/ownership-053-manifest.json'
NAMES=['workshop_references','workshop_legacy_adoption','workshop_project_ownership','workshop_cell_ownership']
FUNCTIONS=['workshop_adoption_immutable_v1','workshop_adopt_bma_roots_v1','workshop_ownership_readiness_v1','project_delete_scope_v1']

MANIFEST_QUERY=r"""select jsonb_build_object(
 'tables',(select jsonb_agg(jsonb_build_object('name',c.relname,'rls',c.relrowsecurity,'forced',c.relforcerowsecurity,
  'columns',(select jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
    from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
  -- PG18 adds named NOT NULL pg_constraint rows; attnotnull above verifies the
  -- same invariant on PG17/Supabase without version-specific duplicate entries.
  'constraints',(select jsonb_agg(jsonb_build_array(k.conname,pg_get_constraintdef(k.oid)) order by k.conname) from pg_constraint k where k.conrelid=c.oid and k.contype<>'n'),
  'indexes',(select jsonb_agg(pg_get_indexdef(i.indexrelid) order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid=c.oid),
  'triggers',(select coalesce(jsonb_agg(pg_get_triggerdef(t.oid) order by t.tgname),'[]'::jsonb) from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal)
 ) order by c.relname) from pg_class c where c.relnamespace='rm_private'::regnamespace and c.relname=any(array['workshop_references','workshop_legacy_adoption','workshop_project_ownership','workshop_cell_ownership'])),
 'functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'signature',pg_get_function_identity_arguments(p.oid),
 'body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'security_definer',p.prosecdef,'volatility',p.provolatile,
 'config',p.proconfig,'result',pg_get_function_result(p.oid),'language',l.lanname) order by p.proname)
 from pg_proc p join pg_language l on l.oid=p.prolang where p.pronamespace='rm_private'::regnamespace
 and p.proname=any(array['workshop_adoption_immutable_v1','workshop_adopt_bma_roots_v1','workshop_ownership_readiness_v1','project_delete_scope_v1']))) as manifest"""

BEFORE=r"""
create temporary table ow_old_tables on commit drop as
select c.oid,n.nspname,c.relname,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,
 (select jsonb_agg(to_jsonb(a) order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped) columns,
 null::bigint row_count,null::text data_hash from pg_class c join pg_namespace n on n.oid=c.relnamespace
where c.relkind='r' and(n.nspname in('rm_private','storage') or n.nspname='public' and c.relname like 'rm\_%' escape '\'
 or n.nspname='auth' and c.relname in('users','identities','sessions','mfa_factors'));
do $baseline$ declare r record;cnt bigint;digest text;begin
 for r in select * from ow_old_tables loop
  execute format('select count(*),encode(sha256(convert_to(coalesce(string_agg(h,'''' order by h),''''),''UTF8'')),''hex'') from(select encode(sha256(convert_to(to_jsonb(x)::text,''UTF8'')),''hex'') h from %I.%I x)s',r.nspname,r.relname) into cnt,digest;
  update ow_old_tables set row_count=cnt,data_hash=digest where oid=r.oid;
 end loop;
end;$baseline$;
create temporary table ow_old_functions on commit drop as select p.oid,to_jsonb(p) shape,pg_get_functiondef(p.oid) definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or n.nspname='public' and p.proname like 'rm\_%' escape '\';
create temporary table ow_old_catalog(kind text,oid oid,shape jsonb) on commit drop;
insert into ow_old_catalog select 'constraint',x.oid,to_jsonb(x) from pg_constraint x where x.conrelid in(select oid from ow_old_tables);
insert into ow_old_catalog select 'trigger',x.oid,to_jsonb(x) from pg_trigger x where x.tgrelid in(select oid from ow_old_tables);
insert into ow_old_catalog select 'policy',x.oid,to_jsonb(x) from pg_policy x where x.polrelid in(select oid from ow_old_tables);
insert into ow_old_catalog select 'index',x.indexrelid,to_jsonb(x) from pg_index x where x.indrelid in(select oid from ow_old_tables);
insert into ow_old_catalog select 'default',x.oid,to_jsonb(x) from pg_attrdef x where x.adrelid in(select oid from ow_old_tables);
insert into ow_old_catalog select 'namespace',x.oid,to_jsonb(x) from pg_namespace x where x.nspname in('public','rm_private','storage','auth');
create temporary table ow_old_roles on commit drop as select jsonb_build_object(
 'roles',(select jsonb_agg(to_jsonb(role_row) order by role_row.oid) from pg_roles role_row),
 'members',(select jsonb_agg(to_jsonb(m) order by m.roleid,m.member,m.grantor) from pg_auth_members m)) state;
create temporary table ow_old_history on commit drop as select to_jsonb(h) state from supabase_migrations.schema_migrations h;
"""

AFTER=r"""
do $verify$ declare r record;actual jsonb;cnt bigint;digest text;begin
 for r in select * from ow_old_tables loop
  if not exists(select 1 from pg_class c where c.oid=r.oid and (c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity)
    is not distinct from(r.relowner,r.relacl,r.relrowsecurity,r.relforcerowsecurity)
    and (select jsonb_agg(to_jsonb(a) order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)=r.columns)
    then raise exception 'Old table definition/ACL changed';end if;
  execute format('select count(*),encode(sha256(convert_to(coalesce(string_agg(h,'''' order by h),''''),''UTF8'')),''hex'') from(select encode(sha256(convert_to(to_jsonb(x)::text,''UTF8'')),''hex'') h from %I.%I x)s',r.nspname,r.relname) into cnt,digest;
  if (cnt,digest) is distinct from(r.row_count,r.data_hash) then raise exception 'Old business/Auth/Storage rows changed';end if;
 end loop;
 if exists(select 1 from ow_old_functions b left join pg_proc p on p.oid=b.oid where p.oid is null or
  case when b.oid='rm_private.project_delete_scope_v1(uuid)'::regprocedure then
   (to_jsonb(p)-'prosrc') is distinct from (b.shape-'prosrc')
  else to_jsonb(p) is distinct from b.shape or pg_get_functiondef(p.oid) is distinct from b.definition end)
 then raise exception 'Old function identity/ACL/body changed';end if;
 for r in select * from ow_old_catalog loop
  case r.kind
   when 'constraint' then select to_jsonb(x) into actual from pg_constraint x where x.oid=r.oid;
   when 'trigger' then select to_jsonb(x) into actual from pg_trigger x where x.oid=r.oid;
   when 'policy' then select to_jsonb(x) into actual from pg_policy x where x.oid=r.oid;
   when 'index' then select to_jsonb(x) into actual from pg_index x where x.indexrelid=r.oid;
   when 'default' then select to_jsonb(x) into actual from pg_attrdef x where x.oid=r.oid;
   when 'namespace' then select to_jsonb(x) into actual from pg_namespace x where x.oid=r.oid;
  end case;
  if actual is distinct from r.shape then raise exception 'Old constraint/trigger/policy/index/default/namespace changed';end if;
 end loop;
 if exists(select 1 from pg_trigger t where t.tgrelid in(select oid from ow_old_tables)
   and not exists(select 1 from ow_old_catalog x where x.kind='trigger' and x.oid=t.oid)
   and not(t.tgisinternal and t.tgconstraint in(select oid from pg_constraint
    where conrelid in('rm_private.workshop_project_ownership'::regclass,'rm_private.workshop_cell_ownership'::regclass)
    and contype='f' and confrelid in('public.rm_projetos'::regclass,'public.rm_celulas'::regclass))))
 then raise exception 'Unexpected new legacy trigger';end if;
 if exists(select 1 from pg_policy p where p.polrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='policy' and b.oid=p.oid))
 then raise exception 'Unexpected legacy policy';end if;
 select jsonb_build_object('roles',(select jsonb_agg(to_jsonb(role_row) order by role_row.oid) from pg_roles role_row),
  'members',(select jsonb_agg(to_jsonb(m) order by m.roleid,m.member,m.grantor) from pg_auth_members m)) into actual;
 if actual is distinct from(select state from ow_old_roles) then raise exception 'Roles changed';end if;
 if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
  or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*) from ow_old_history)
 then raise exception 'Old migration history changed';end if;
 __MANIFEST_CHECK__
 for r in select c.* from pg_class c where c.relnamespace='rm_private'::regnamespace and c.relname=any(array['workshop_references','workshop_legacy_adoption','workshop_project_ownership','workshop_cell_ownership']) loop
  execute format('select count(*) from rm_private.%I',r.relname) into cnt;
  if cnt<>0 or not r.relrowsecurity or r.relowner<>current_user::regrole
   or exists(select 1 from aclexplode(coalesce(r.relacl,acldefault('r',r.relowner))) a where a.grantee<>r.relowner)
   or exists(select 1 from pg_policy where polrelid=r.oid)
  then raise exception 'New tables must be empty/private';end if;
 end loop;
 if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.pronamespace='rm_private'::regnamespace and p.proname=any(array['workshop_adoption_immutable_v1','workshop_adopt_bma_roots_v1','workshop_ownership_readiness_v1'])
   and (a.grantee<>p.proowner or p.proowner<>current_user::regrole)) then raise exception 'New function grants changed';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and(n.nspname in('rm_private','storage') or n.nspname='public' and c.relname like 'rm\_%' escape '\'
 or n.nspname='auth' and c.relname in('users','identities','sessions','mfa_factors')))<>(select count(*)+4 from ow_old_tables)
 then raise exception 'Unexpected new table set';end if;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or n.nspname='public' and p.proname like 'rm\_%' escape '\')<>(select count(*)+3 from ow_old_functions)
 then raise exception 'Unexpected new function set';end if;
end;$verify$;
"""

def literal(value):return "'"+value.replace("'","''")+"'"

def release_sql(source_sha256,manifest_sha256,*,apply=False):
    raw=SOURCE.read_bytes();manifest_bytes=MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=source_sha256 or hashlib.sha256(manifest_bytes).hexdigest()!=manifest_sha256:
        raise ValueError('Source/manifest changed after local rehearsal')
    text=raw.decode('utf-8')
    if '\r' in text or len(re.findall(r'^begin;$',text,re.M))!=1 or len(re.findall(r'^commit;$',text,re.M))!=1:raise ValueError('Unexpected SQL boundaries')
    body=re.sub(r'^begin;\n|^commit;\s*$', '',text,flags=re.M)
    manifest=json.loads(manifest_bytes)
    if sorted(t['name'] for t in manifest['tables'])!=sorted(NAMES) or sorted(f['name'] for f in manifest['functions'])!=sorted(FUNCTIONS):raise ValueError('Invalid manifest')
    query=MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')
    after=AFTER.replace('__MANIFEST_CHECK__',f"select {query} into actual;\n if actual is distinct from {literal(json.dumps(manifest))}::jsonb then raise exception 'New object manifest differs';end if;")
    old=sorted(p for p in (ROOT/'migrations').glob('*.sql') if p.name[:3]<'053')
    history_values=','.join('('+literal(p.name[:3])+','+literal(hashlib.sha256(p.read_bytes()).hexdigest())+')' for p in old)
    guard=f"""create temporary table ow_expected_history(version text,sha text) on commit drop;
insert into ow_expected_history values {history_values};
do $history$ begin
if(select array_agg(version order by version) from supabase_migrations.schema_migrations) is distinct from(select array_agg(version order by version) from ow_expected_history)
 or exists(select 1 from ow_expected_history e join supabase_migrations.schema_migrations h using(version) where
 (e.version<='017' and h.statements is distinct from '{{}}'::text[]) or(e.version>'017' and(cardinality(h.statements) is distinct from 1 or encode(sha256(convert_to(h.statements[1],'UTF8')),'hex') is distinct from e.sha)))
then raise exception 'Old migration sources differ';end if;
end;$history$;\n"""
    history="insert into supabase_migrations.schema_migrations(version,name,statements) values('053','rm_workshop_ownership_foundation',array["+literal(text)+"]);\n"
    history+=f"""do $final_history$ begin
if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or(select encode(sha256(convert_to(statements[1],'UTF8')),'hex') from supabase_migrations.schema_migrations where version='053') is distinct from '{source_sha256}'
then raise exception 'Final migration history differs';end if;
end;$final_history$;\n"""
    proof="select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,'expected_delete_scope_extension_only',true,'roles_preserved',true,'new_tables_empty',true,'old_tables_checked',(select count(*) from ow_old_tables),'old_functions_checked',(select count(*) from ow_old_functions),'isolation_active',false) proof;\n"
    return "begin isolation level repeatable read;set local timezone='UTC';set local search_path='';set local lock_timeout='5s';set local statement_timeout='120s';\n"+guard+BEFORE+body+after+history+proof+('commit;\n' if apply else 'rollback;\n')
