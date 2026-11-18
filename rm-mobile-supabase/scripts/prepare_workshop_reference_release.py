"""Preservation-checked 055, no network; rollback is the default."""
import hashlib
import json
import re
import prepare_workshop_ownership_release as baseline

ROOT=baseline.ROOT
SOURCE=ROOT/'migrations/055_rm_workshop_direct_references.sql'
MANIFEST=ROOT/'workshops/references-055-manifest.json'
FUNCTIONS=['workshop_reference_relations_v1','workshop_reference_pair_v1','workshop_guard_reference_v1',
 'workshop_guard_root_references_v1','workshop_reference_readiness_v1']
TABLES=['rm_celulas_projeto','rm_aprovacoes_etapas','rm_aprovacoes_registro','rm_comentarios',
 'rm_form_reviewer_assignments','rm_fotos','rm_logs_aprovacao','rm_registros_formulario','rm_web_stage_decisions']
literal=baseline.literal
def array(items):return 'array['+','.join(map(literal,items))+']'

MANIFEST_QUERY=r"""select jsonb_build_object(
 'functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'signature',pg_get_function_identity_arguments(p.oid),
  'body_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'security_definer',p.prosecdef,'volatility',p.provolatile,
  'config',p.proconfig,'result',pg_get_function_result(p.oid),'language',l.lanname) order by p.proname)
 from pg_proc p join pg_language l on l.oid=p.prolang where p.pronamespace='rm_private'::regnamespace and p.proname=any(__FUNCTIONS__)),
 'triggers',(select jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) order by n.nspname,c.relname,t.tgname)
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal and(n.nspname='public' and c.relname=any(__TABLES__) and t.tgname='workshop_direct_reference_guard'
  or n.nspname='rm_private' and c.relname in('workshop_project_ownership','workshop_cell_ownership') and t.tgname in('workshop_project_reference_guard','workshop_cell_reference_guard'))),
 'rules',(select jsonb_agg(to_jsonb(rule_row) order by rule_row.table_name,rule_row.cell_column) from rm_private.workshop_reference_relations_v1() rule_row)) as manifest""".replace('__FUNCTIONS__',array(FUNCTIONS)).replace('__TABLES__',array(TABLES))
BEFORE=baseline.BEFORE
AFTER=baseline.AFTER.split(' __MANIFEST_CHECK__')[0]
start=AFTER.index('  case when b.oid=');end=AFTER.index("\n then raise exception 'Old function",start)
AFTER=AFTER[:start]+'  to_jsonb(p) is distinct from b.shape or pg_get_functiondef(p.oid) is distinct from b.definition)'+AFTER[end:]
start=AFTER.index('   and not(t.tgisinternal');end=AFTER.index("\n then raise exception 'Unexpected new legacy trigger'",start)
AFTER=AFTER[:start]+"""   and not(not t.tgisinternal and(
    t.tgname='workshop_direct_reference_guard' and t.tgrelid in(select c.oid from pg_class c where c.relnamespace='public'::regnamespace and c.relname=any(__TABLES__))
    or t.tgname='workshop_project_reference_guard' and t.tgrelid='rm_private.workshop_project_ownership'::regclass
    or t.tgname='workshop_cell_reference_guard' and t.tgrelid='rm_private.workshop_cell_ownership'::regclass)))""".replace('__TABLES__',array(TABLES))+AFTER[end:]
AFTER+=r"""
 if exists(select 1 from pg_constraint k where k.conrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='constraint' and b.oid=k.oid))
 or exists(select 1 from pg_index i where i.indrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='index' and b.oid=i.indexrelid))
 or exists(select 1 from pg_attrdef d where d.adrelid in(select oid from ow_old_tables) and not exists(select 1 from ow_old_catalog b where b.kind='default' and b.oid=d.oid))
 then raise exception 'Unexpected legacy constraint/index/default';end if;
 __MANIFEST_CHECK__
 if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.pronamespace='rm_private'::regnamespace and p.proname=any(__FUNCTIONS__) and(a.grantee<>p.proowner or p.proowner<>current_user::regrole))
 then raise exception 'New function exposed';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and(n.nspname in('rm_private','storage') or n.nspname='public' and c.relname like 'rm\_%' escape '\'
 or n.nspname='auth' and c.relname in('users','identities','sessions','mfa_factors')))<>(select count(*) from ow_old_tables)
 then raise exception 'Unexpected new table set';end if;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or n.nspname='public' and p.proname like 'rm\_%' escape '\')<>(select count(*)+5 from ow_old_functions)
 then raise exception 'Unexpected new function set';end if;
end;$verify$;
""".replace('__FUNCTIONS__',array(FUNCTIONS))

def release_sql(source_sha256,manifest_sha256,*,apply=False):
    raw=SOURCE.read_bytes();manifest_bytes=MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=source_sha256 or hashlib.sha256(manifest_bytes).hexdigest()!=manifest_sha256:raise ValueError('Source/manifest changed after tests')
    source=raw.decode('utf-8');manifest=json.loads(manifest_bytes)
    if '\r' in source or len(re.findall(r'^begin;$',source,re.M))!=1 or len(re.findall(r'^commit;$',source,re.M))!=1:raise ValueError('Unexpected SQL boundaries')
    if sorted(f['name'] for f in manifest['functions'])!=sorted(FUNCTIONS) or len(manifest['triggers'])!=11 or len(manifest['rules'])!=10:raise ValueError('Incomplete manifest')
    body=re.sub(r'^begin;\n|^commit;\s*$','',source,flags=re.M)
    query=MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')
    after=AFTER.replace('__MANIFEST_CHECK__',f"select {query} into actual;if actual is distinct from {literal(json.dumps(manifest))}::jsonb then raise exception 'New object manifest differs';end if;")
    old=sorted(p for p in (ROOT/'migrations').glob('*.sql') if p.name[:3]<'055')
    values=','.join('('+literal(p.name[:3])+','+literal(hashlib.sha256(p.read_bytes()).hexdigest())+')' for p in old)
    history=f"""create temporary table ow_expected_history(version text,sha text) on commit drop;
insert into ow_expected_history values {values};
do $history$ begin
if(select array_agg(version order by version) from supabase_migrations.schema_migrations) is distinct from(select array_agg(version order by version) from ow_expected_history)
 or exists(select 1 from ow_expected_history e join supabase_migrations.schema_migrations h using(version) where
 (e.version<='017' and h.statements is distinct from '{{}}'::text[]) or(e.version>'017' and(cardinality(h.statements) is distinct from 1 or encode(sha256(convert_to(h.statements[1],'UTF8')),'hex') is distinct from e.sha)))
then raise exception 'Old migration sources differ';end if;
end;$history$;
"""
    final="insert into supabase_migrations.schema_migrations(version,name,statements) values('055','rm_workshop_direct_references',array["+literal(source)+"]);\n"
    final+=f"""do $final_history$ begin
if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or(select encode(sha256(convert_to(statements[1],'UTF8')),'hex') from supabase_migrations.schema_migrations where version='055') is distinct from '{source_sha256}'
then raise exception 'Final migration history differs';end if;
end;$final_history$;
"""
    proof="select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,'old_functions_preserved',true,'roles_preserved',true,'old_tables_checked',(select count(*) from ow_old_tables),'old_functions_checked',(select count(*) from ow_old_functions),'readiness',rm_private.workshop_reference_readiness_v1(),'isolation_active',false) proof;\n"
    locks=re.search(r'^lock table .*? in share row exclusive mode;',source,re.M|re.S)
    if locks is None:raise ValueError('Expected installation locks')
    return "begin isolation level repeatable read;set local search_path='';set local timezone='UTC';set local lock_timeout='5s';set local statement_timeout='150s';\n"+locks.group(0)+'\n'+history+BEFORE+body+after+final+proof+('commit;\n' if apply else 'rollback;\n')
