"""056 preservation envelope, offline generator and rollback by default."""
import hashlib
import json
import re
import prepare_workshop_ownership_release as baseline
import prepare_workshop_reference_release as previous

ROOT=baseline.ROOT
SOURCE=ROOT/'migrations/056_rm_workshop_catalog_ownership.sql'
POLICY=ROOT/'workshops/catalog-scope.json'
POLICY_SHA='f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff'
MANIFEST=ROOT/'workshops/catalogs-056-manifest.json'
NAMES=['workshop_catalog_adoption','workshop_catalog_ownership','workshop_catalog_retirements']
FUNCTIONS=['workshop_catalog_relations_v1','workshop_catalog_scope_v1','workshop_catalog_pair_v1',
 'workshop_catalog_guard_reference_v1','workshop_catalog_guard_assignment_v1','workshop_catalog_guard_lifecycle_v1',
 'workshop_catalog_adopt_bma_v1','workshop_catalog_readiness_v1']
TABLES=['public.rm_projetos','public.rm_equipamentos','public.rm_registros_formulario','public.rm_aprovacoes_registro',
 'public.rm_respostas_temp','public.rm_propostas_controle','public.rm_propostas_budgetarias','public.rm_ordens_servico',
 'public.rm_celula_tipos_equipamento','public.rm_form_reviewer_assignments','rm_private.project_route_instances',
 'public.rm_form_template_drafts','public.rm_forms']
TRIGGERS=['workshop_catalog_immutable','workshop_catalog_no_truncate','workshop_catalog_assign','workshop_catalog_references',
 'workshop_catalog_reference_guard','workshop_catalog_lifecycle']
literal=baseline.literal
array=previous.array

# Normalize NOT NULL via attributes, as in the PG17/18 manifests for 053–055.
MANIFEST_QUERY=baseline.MANIFEST_QUERY.replace(array(baseline.NAMES),array(NAMES)).replace(array(baseline.FUNCTIONS),array(FUNCTIONS))
MANIFEST_QUERY=MANIFEST_QUERY.removesuffix(') as manifest')+r""", 'triggers',(
 select jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) order by n.nspname,c.relname,t.tgname)
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('public','rm_private') and not t.tgisinternal and t.tgname=any(__TRIGGERS__)),
 'rules',(select jsonb_agg(to_jsonb(rule_row) order by schema_name,table_name,left_column,right_column) from rm_private.workshop_catalog_relations_v1() rule_row)) as manifest""".replace('__TRIGGERS__',array(TRIGGERS))
BEFORE=baseline.BEFORE
AFTER=previous.AFTER.split(' __MANIFEST_CHECK__')[0]
# Replace the 055-only trigger allowlist; all previous triggers remain pinned.
start=AFTER.index(' if exists(select 1 from pg_trigger t')
end=AFTER.index("\n then raise exception 'Unexpected new legacy trigger'",start)
AFTER=AFTER[:start]+r""" if exists(select 1 from pg_trigger t where t.tgrelid in(select oid from ow_old_tables)
 and not exists(select 1 from ow_old_catalog b where b.kind='trigger' and b.oid=t.oid)
 and not(not t.tgisinternal and t.tgname in('workshop_catalog_references','workshop_catalog_reference_guard','workshop_catalog_lifecycle','workshop_catalog_no_truncate'))
 and not(t.tgisinternal and t.tgconstraint in(select oid from pg_constraint where contype='f'
  and conrelid in('rm_private.workshop_catalog_adoption'::regclass,'rm_private.workshop_catalog_ownership'::regclass)
  and confrelid='rm_private.workshop_references'::regclass)))"""+AFTER[end:]
AFTER+=r"""
 __MANIFEST_CHECK__
 if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.pronamespace='rm_private'::regnamespace and p.proname=any(__FUNCTIONS__) and(a.grantee<>p.proowner or p.proowner<>current_user::regrole))
 then raise exception 'New function exposed';end if;
 if exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
  where c.relnamespace='rm_private'::regnamespace and c.relname=any(__NAMES__) and
  (a.grantee<>c.relowner or c.relowner<>current_user::regrole or not c.relrowsecurity))
 or exists(select 1 from pg_policy where polrelid in('rm_private.workshop_catalog_adoption'::regclass,'rm_private.workshop_catalog_ownership'::regclass,'rm_private.workshop_catalog_retirements'::regclass))
 then raise exception 'New catalog metadata exposed';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and(n.nspname in('rm_private','storage') or n.nspname='public' and c.relname like 'rm\_%' escape '\'
 or n.nspname='auth' and c.relname in('users','identities','sessions','mfa_factors')))<>(select count(*)+3 from ow_old_tables)
 then raise exception 'Unexpected table set';end if;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or n.nspname='public' and p.proname like 'rm\_%' escape '\')<>(select count(*)+8 from ow_old_functions)
 then raise exception 'Unexpected function set';end if;
 if(select count(*) from rm_private.workshop_catalog_adoption)<>1 or exists(select 1 from rm_private.workshop_catalog_retirements)
 or exists(select 1 from rm_private.workshop_catalog_adoption a where a.database_actor<>session_user or a.policy_sha256<>__POLICY__ or
  a.counts<>jsonb_build_object('clients',(select clients from wc_expected),'equipment_types',(select equipment_types from wc_expected),'form_models',(select form_models from wc_expected)))
 or(select count(*) from rm_private.workshop_catalog_ownership)<>(select clients+equipment_types+form_models from wc_expected)
 or exists(select 1 from rm_private.workshop_catalog_ownership o join rm_private.workshop_catalog_adoption a on true where
  o.workshop_id<>a.workshop_id or o.adoption is distinct from true or o.database_actor<>session_user)
 or exists(select 1 from rm_private.workshop_catalog_ownership o where not exists(
  select 1 from public.rm_clientes x where o.object_kind='client' and x.id=o.object_id
  union all select 1 from public.rm_tipos_equipamento x where o.object_kind='equipment_type' and x.id=o.object_id
  union all select 1 from public.rm_forms x where o.object_kind='form_model' and x.id=o.object_id))
 then raise exception 'Catalog seed or receipt differs';end if;
 if(rm_private.workshop_catalog_readiness_v1()->>'conflicts')::bigint<>0 then raise exception 'Cross-workshop catalog references require review';end if;
end;$verify$;
""".replace('__FUNCTIONS__',array(FUNCTIONS)).replace('__NAMES__',array(NAMES)).replace('__POLICY__',literal(POLICY_SHA))

def release_sql(source_sha256,manifest_sha256,clients,equipment_types,form_models,*,apply=False):
    raw=SOURCE.read_bytes();manifest_bytes=MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=source_sha256 or hashlib.sha256(manifest_bytes).hexdigest()!=manifest_sha256 or hashlib.sha256(POLICY.read_bytes()).hexdigest()!=POLICY_SHA:raise ValueError('Approved/tested source changed')
    if any(type(v) is not int or v<0 for v in [clients,equipment_types,form_models]):raise ValueError('Reviewed counts required')
    source=raw.decode('utf-8');manifest=json.loads(manifest_bytes)
    if '\r' in source or len(re.findall(r'^begin;$',source,re.M))!=1 or len(re.findall(r'^commit;$',source,re.M))!=1:raise ValueError('Unexpected SQL boundaries')
    if sorted(t['name'] for t in manifest['tables'])!=sorted(NAMES) or sorted(f['name'] for f in manifest['functions'])!=sorted(FUNCTIONS) or len(manifest['triggers'])!=29 or len(manifest['rules'])!=23:raise ValueError('Incomplete manifest')
    body=re.sub(r'^begin;\n|^commit;\s*$','',source,flags=re.M)
    after=AFTER.replace('__MANIFEST_CHECK__',f"select {MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')} into actual;if actual is distinct from {literal(json.dumps(manifest))}::jsonb then raise exception 'New object manifest differs';end if;")
    old=sorted(p for p in (ROOT/'migrations').glob('*.sql') if p.name[:3]<'056')
    values=','.join('('+literal(p.name[:3])+','+literal(hashlib.sha256(p.read_bytes()).hexdigest())+')' for p in old)
    history=f"""create temporary table ow_expected_history(version text,sha text) on commit drop;insert into ow_expected_history values {values};
do $history$ begin
if(select array_agg(version order by version) from supabase_migrations.schema_migrations) is distinct from(select array_agg(version order by version) from ow_expected_history)
 or exists(select 1 from ow_expected_history e join supabase_migrations.schema_migrations h using(version) where
 (e.version<='017' and h.statements is distinct from '{{}}'::text[]) or(e.version>'017' and(cardinality(h.statements) is distinct from 1 or encode(sha256(convert_to(h.statements[1],'UTF8')),'hex') is distinct from e.sha)))
then raise exception 'Old migration sources differ';end if;end;$history$;
"""
    final="insert into supabase_migrations.schema_migrations(version,name,statements) values('056','rm_workshop_catalog_ownership',array["+literal(source)+"]);\n"
    final+=f"""do $final_history$ begin
if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or(select encode(sha256(convert_to(statements[1],'UTF8')),'hex') from supabase_migrations.schema_migrations where version='056') is distinct from '{source_sha256}'
then raise exception 'Final migration history differs';end if;end;$final_history$;
"""
    locks='lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership in share row exclusive mode;\n'
    for name in sorted(set(TABLES+['public.rm_clientes','public.rm_tipos_equipamento'])):locks+='lock table '+name+' in share row exclusive mode;\n'
    expected=f'create temporary table wc_expected(clients bigint,equipment_types bigint,form_models bigint) on commit drop;insert into wc_expected values({clients},{equipment_types},{form_models});\n'
    adopt=f'select rm_private.workshop_catalog_adopt_bma_v1({literal(POLICY_SHA)},{clients},{equipment_types},{form_models});\n'
    proof="select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,'old_functions_preserved',true,'roles_preserved',true,'catalog_seed_verified',true,'old_tables_checked',(select count(*) from ow_old_tables),'old_functions_checked',(select count(*) from ow_old_functions),'readiness',rm_private.workshop_catalog_readiness_v1(),'isolation_active',false) proof;\n"
    return "begin;set local search_path='';set local timezone='UTC';set local lock_timeout='5s';set local statement_timeout='180s';\n"+locks+expected+history+BEFORE+body+adopt+after+final+proof+('commit;\n' if apply else 'rollback;\n')
