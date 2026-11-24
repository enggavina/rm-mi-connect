"""Build the 060 preservation envelope. No network; roll back by default."""

import hashlib
import json
import re

import prepare_workshop_ownership_release as baseline


ROOT = baseline.ROOT
SOURCE = ROOT / 'migrations/060_rm_web_workshop_operations.sql'
MANIFEST = ROOT / 'workshops/operations-060-manifest.json'
VERSION = '060'
CONSTRAINT = 'workshop_read_permits_resource_check'
PERMITS = 'rm_private.workshop_read_permits'
CONSTRAINT_QUERY = f"""
select pg_get_constraintdef(oid)
from pg_constraint
where conrelid = '{PERMITS}'::regclass and conname = '{CONSTRAINT}'
"""
LITERAL = baseline.literal

ISSUER = 'public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'
READER = 'public.rm_web_workshop_read_v1(uuid,text,jsonb)'
REPLACED = {
    ISSUER: '827586e31a6c710e15f1ca26f4419dc8c030ce79faabc3c5ba43e27ed60373bf',
    READER: '714b27ab6e6031c4a2059f0f800514106cae65c3dd07bb2182dbec557bfe1359',
}
ADDED = (
    'rm_private.workshop_project_owned_v1(uuid,uuid)',
    'rm_private.workshop_cell_owned_v1(uuid,uuid)',
    'rm_private.workshop_project_read_data_v1(text,jsonb,uuid)',
    'rm_private.workshop_gantt_snapshot_v1(jsonb,uuid)',
    'rm_private.workshop_gantt_projects_v1(jsonb,uuid)',
    'rm_private.workshop_gantt_cells_v1(jsonb,uuid)',
)
ORIGINAL_RESOURCES = (
    'catalog_list', 'catalog_entry', 'template_list',
    'template_draft', 'template_form', 'template_choices',
)
NEW_RESOURCES = (
    'project_list', 'project_entry', 'planning_list',
    'gantt_snapshot', 'gantt_projects', 'gantt_cells',
)


def constraint_definition(resources):
    quoted = ', '.join(f"{LITERAL(resource)}::text" for resource in resources)
    return f'CHECK ((resource = ANY (ARRAY[{quoted}])))'


EXPECTED_CONSTRAINT = constraint_definition(ORIGINAL_RESOURCES + NEW_RESOURCES)
FUNCTIONS = tuple(REPLACED) + ADDED
FUNCTION_LOOKUP = ','.join(f'{LITERAL(fn)}::regprocedure' for fn in FUNCTIONS)
FUNCTION_KEYS = sorted(fn.split('(')[0] for fn in FUNCTIONS)

MANIFEST_QUERY = f"""
select jsonb_build_object(
 'resource_constraint',({CONSTRAINT_QUERY}),
 'functions',(
  select jsonb_agg(jsonb_build_object(
   'name', n.nspname || '.' || p.proname,
   'signature', pg_get_function_identity_arguments(p.oid),
   'body_sha256', encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),
   'security_definer', p.prosecdef, 'volatility', p.provolatile,
   'config', p.proconfig, 'result', pg_get_function_result(p.oid), 'language', l.lanname,
   'strict', p.proisstrict, 'parallel', p.proparallel, 'leakproof', p.proleakproof,
   'cost', p.procost, 'rows', p.prorows) order by n.nspname,p.proname)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join pg_language l on l.oid=p.prolang where p.oid in({FUNCTION_LOOKUP})
 )) as manifest
""".strip()

FUNCTION_GRANTS = f"""
select jsonb_build_object(
 'issuer_exact', not exists(
  select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.oid='{ISSUER}'::regprocedure
    and (a.grantee not in(p.proowner,'service_role'::regrole) or p.proowner<>current_user::regrole))
  and has_function_privilege('service_role','{ISSUER}','execute'),
 'reader_exact', not exists(
  select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.oid='{READER}'::regprocedure
    and (a.grantee not in(p.proowner,'authenticated'::regrole) or p.proowner<>current_user::regrole))
  and has_function_privilege('authenticated','{READER}','execute'),
 'helpers_private', not exists(
  select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.oid in({','.join(f'{LITERAL(fn)}::regprocedure' for fn in ADDED)})
    and (a.grantee<>p.proowner or p.proowner<>current_user::regrole or p.prosecdef)),
 'permits_private', not exists(
  select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
  where c.oid='{PERMITS}'::regclass
    and (a.grantee<>c.relowner or c.relowner<>current_user::regrole or not c.relrowsecurity))
  and not exists(select 1 from pg_policy where polrelid='{PERMITS}'::regclass)
 ) as grants
""".strip()

RELATIONS_QUERY = """
select c.oid, c.relname, c.relnamespace, c.relowner, to_jsonb(c.relacl) acl, c.relkind,
 c.reloptions, c.relrowsecurity, c.relforcerowsecurity, c.relreplident
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public','rm_private','storage','auth')
""".strip()

BEFORE = f"""
do $before$ begin
 if ({CONSTRAINT_QUERY}) is distinct from {LITERAL(constraint_definition(ORIGINAL_RESOURCES))}
 then raise exception 'Old resource check differs'; end if;
 if exists(
  select 1 from (values
   {','.join(f'({LITERAL(fn)}::regprocedure,{LITERAL(digest)})' for fn,digest in REPLACED.items())}
  ) expected(oid,digest)
  left join pg_proc p on p.oid=expected.oid
  where encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') is distinct from expected.digest)
 then raise exception 'Old workshop dispatcher sources differ'; end if;
end;$before$;
{baseline.BEFORE}
create temporary table wo_old_relations on commit drop as {RELATIONS_QUERY};
create temporary table wo_old_defaults on commit drop as select to_jsonb(d) shape from pg_default_acl d;
"""

_old_objects = baseline.AFTER.split(' __MANIFEST_CHECK__')[0]
_replace_start = _old_objects.index("  case when b.oid=")
_replace_end = _old_objects.index("\n then raise exception 'Old function identity", _replace_start)
_public_functions = ','.join(f'{LITERAL(fn)}::regprocedure' for fn in REPLACED)
_old_objects = _old_objects[:_replace_start] + f"""
  case when b.oid in({_public_functions}) then
   (to_jsonb(p)-'prosrc') is distinct from (b.shape-'prosrc')
  else to_jsonb(p) is distinct from b.shape or pg_get_functiondef(p.oid) is distinct from b.definition end)""" + _old_objects[_replace_end:]
_old_objects = _old_objects.replace(
    "when 'constraint' then select to_jsonb(x) into actual from pg_constraint x where x.oid=r.oid;",
    f"""when 'constraint' then
    if r.shape->>'conname'='{CONSTRAINT}' and (r.shape->>'conrelid')::oid='{PERMITS}'::regclass then
     select to_jsonb(x) into actual from pg_constraint x where x.conrelid='{PERMITS}'::regclass and x.conname='{CONSTRAINT}';
     if (actual-array['oid','conbin']) is distinct from (r.shape-array['oid','conbin'])
     then raise exception 'Resource check attributes changed';end if;
     continue;
    end if;
    select to_jsonb(x) into actual from pg_constraint x where x.oid=r.oid;""",
)
_trigger_start = _old_objects.index('   and not(t.tgisinternal')
_trigger_end = _old_objects.index("\n then raise exception 'Unexpected new legacy trigger'", _trigger_start)
_old_objects = _old_objects[:_trigger_start].rstrip() + ')' + _old_objects[_trigger_end:]
AFTER = _old_objects + f"""
 if exists(
  select 1 from pg_constraint k where k.conrelid in(select oid from ow_old_tables)
   and not (k.conrelid='{PERMITS}'::regclass and k.conname='{CONSTRAINT}')
   and not exists(select 1 from ow_old_catalog b where b.kind='constraint' and b.oid=k.oid))
 or exists(select 1 from pg_index i where i.indrelid in(select oid from ow_old_tables)
   and not exists(select 1 from ow_old_catalog b where b.kind='index' and b.oid=i.indexrelid))
 or exists(select 1 from pg_attrdef d where d.adrelid in(select oid from ow_old_tables)
   and not exists(select 1 from ow_old_catalog b where b.kind='default' and b.oid=d.oid))
 then raise exception 'Unexpected legacy constraint/index/default';end if;
 if exists(({RELATIONS_QUERY}) except select * from wo_old_relations)
 or exists(select * from wo_old_relations except ({RELATIONS_QUERY}))
 or exists(select to_jsonb(d) from pg_default_acl d except select * from wo_old_defaults)
 or exists(select * from wo_old_defaults except select to_jsonb(d) from pg_default_acl d)
 then raise exception 'Relation identities/ACLs or default grants changed';end if;
 __MANIFEST_CHECK__
 select ({FUNCTION_GRANTS.removeprefix('select ').removesuffix(' as grants')}) into actual;
 if exists(select 1 from jsonb_each(actual) where value is distinct from 'true'::jsonb)
 then raise exception 'Workshop operation grants differ';end if;
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='rm_private' or n.nspname='public' and left(p.proname,3)='rm_')
  <> (select count(*)+{len(ADDED)} from ow_old_functions)
 then raise exception 'Unexpected function set';end if;
end;$verify$;
"""


def history_checks(source, source_sha256):
    legacy = sorted(p for p in (ROOT / 'migrations').glob('*.sql') if p.name[:3] < VERSION)
    values = ','.join(f"({LITERAL(p.name[:3])},{LITERAL(hashlib.sha256(p.read_bytes()).hexdigest())})" for p in legacy)
    before = f"""create temporary table ow_expected_history(version text,sha text) on commit drop;
insert into ow_expected_history values {values};
do $history$ begin
 if (select array_agg(version order by version) from supabase_migrations.schema_migrations)
  is distinct from (select array_agg(version order by version) from ow_expected_history)
 or exists(select 1 from ow_expected_history e join supabase_migrations.schema_migrations h using(version)
  where (e.version<='017' and h.statements is distinct from '{{}}'::text[])
  or (e.version>'017' and (cardinality(h.statements) is distinct from 1
   or encode(sha256(convert_to(h.statements[1],'UTF8')),'hex') is distinct from e.sha)))
 then raise exception 'Old migration sources differ'; end if;
end;$history$;
"""
    after = f"""insert into supabase_migrations.schema_migrations(version,name,statements)
values('{VERSION}',{LITERAL(SOURCE.stem[4:])},array[{LITERAL(source)}]);
do $final_history$ begin
 if exists(select 1 from ow_old_history b where not exists(
  select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or (select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or (select encode(sha256(convert_to(statements[1],'UTF8')),'hex')
  from supabase_migrations.schema_migrations where version='{VERSION}') is distinct from {LITERAL(source_sha256)}
 then raise exception 'Final migration history differs'; end if;
end;$final_history$;
"""
    return before, after


def release_sql(source_sha256, manifest_sha256, *, apply=False):
    raw = SOURCE.read_bytes()
    manifest_bytes = MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest() != source_sha256 or hashlib.sha256(manifest_bytes).hexdigest() != manifest_sha256:
        raise ValueError('Tested operations SQL or manifest changed')
    source = raw.decode('utf-8')
    if '\r' in source or not re.search(r'^begin;\n', source, re.M) or not source.rstrip().endswith('\ncommit;'):
        raise ValueError('Unexpected operations transaction boundaries')
    if len(re.findall(r'^begin;$|^commit;$', source, re.M)) != 2:
        raise ValueError('Expected one operations transaction')
    manifest = json.loads(manifest_bytes)
    if manifest['resource_constraint'] != EXPECTED_CONSTRAINT or sorted(fn['name'] for fn in manifest['functions']) != FUNCTION_KEYS:
        raise ValueError('Invalid operations manifest')
    migration = re.sub(r'^begin;\n|^commit;\s*$', '', source, flags=re.M)
    history_before, history_after = history_checks(source, source_sha256)
    query = MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')
    expected = LITERAL(json.dumps(manifest, ensure_ascii=False))
    after = AFTER.replace('__MANIFEST_CHECK__', f"""select {query} into actual;
 if actual is distinct from {expected}::jsonb then raise exception 'Operations object manifest differs'; end if;""")
    proof = """select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,
 'only_expected_dispatchers_replaced',true,'only_expected_constraint_replaced',true,
 'private_helpers_and_grants_verified',true,'roles_preserved',true,
 'old_tables_checked',(select count(*) from ow_old_tables),
 'old_functions_checked',(select count(*) from ow_old_functions),'full_isolation_active',false) proof;
"""
    return (
        "begin isolation level repeatable read;set local search_path='';set local timezone='UTC';"
        "set local lock_timeout='5s';set local statement_timeout='180s';\n"
        f'lock table {PERMITS} in access exclusive mode;\n'
        + history_before + BEFORE + migration + after + history_after + proof
        + ('commit;\n' if apply else 'rollback;\n')
    )
