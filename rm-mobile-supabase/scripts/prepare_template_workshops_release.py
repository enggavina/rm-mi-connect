"""058 preservation envelope and offline generator; rollback by default."""
import hashlib,json,re
import prepare_workshop_ownership_release as baseline
import prepare_catalog_writes_release as previous
from prepare_workshop_reference_release import array
ROOT=baseline.ROOT
SOURCE=ROOT/'migrations/058_rm_web_template_workshops.sql'
MANIFEST=ROOT/'workshops/template-workshops-058-manifest.json'
NAMES=['workshop_template_adoption','workshop_template_ownership','workshop_template_retirements','template_workshop_write_settings','template_workshop_write_permits']
FUNCTIONS=['workshop_template_scope_v1','workshop_template_pair_v1','workshop_template_edges_v1','workshop_template_check_v1','workshop_template_guard_v1',
 'adopt_workshop_templates_bma_v1','workshop_template_require_v1','web_mutate_scoped_templates_v1','activate_template_workshop_writes_v1','rm_sso_template_workshop_permit_v1','rm_web_mutate_v1']
TRIGGERS=['workshop_template_immutable','workshop_template_no_truncate','workshop_template_assign','workshop_template_references','workshop_template_lifecycle']
literal=baseline.literal
MANIFEST_QUERY=baseline.MANIFEST_QUERY.replace(array(baseline.NAMES),array(NAMES)).replace(array(baseline.FUNCTIONS),array(FUNCTIONS)).replace("p.pronamespace='rm_private'::regnamespace","p.pronamespace in('rm_private'::regnamespace,'public'::regnamespace)")
MANIFEST_QUERY=MANIFEST_QUERY.removesuffix(') as manifest')+r""",'triggers',(
 select jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) order by n.nspname,c.relname,t.tgname)
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('public','rm_private') and not t.tgisinternal and t.tgname=any(__TRIGGERS__))) as manifest""".replace('__TRIGGERS__',array(TRIGGERS))
BEFORE=baseline.BEFORE
AFTER=previous.AFTER.split(' __MANIFEST_CHECK__')[0]
NEW='return rm_private.web_mutate_scoped_templates_v1(p_client_submission_id,p_operation,p_payload);'
AFTER=AFTER.replace(literal(previous.NEW),literal(NEW)).replace(literal(previous.OLD),literal(previous.NEW))
start=AFTER.index('   and not(t.tgisinternal');end=AFTER.index("\n then raise exception 'Unexpected new legacy trigger'",start)
AFTER=AFTER[:start]+r"""   and not(not t.tgisinternal and t.tgname in('workshop_template_references','workshop_template_lifecycle','workshop_template_no_truncate')
    and t.tgrelid in('rm_private.workshop_catalog_ownership'::regclass,'public.rm_form_template_drafts'::regclass,'public.rm_form_template_families'::regclass,'public.rm_form_template_versions'::regclass))
   and not(t.tgisinternal and t.tgconstraint in(select oid from pg_constraint where contype='f'
    and conrelid in('rm_private.template_workshop_write_permits'::regclass,'rm_private.workshop_template_ownership'::regclass,'rm_private.workshop_template_adoption'::regclass)
    and confrelid in('rm_private.sso_sessions'::regclass,'rm_private.workshop_references'::regclass))))"""+AFTER[end:]
AFTER+=r"""
 __MANIFEST_CHECK__
 if exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a where
  c.relnamespace='rm_private'::regnamespace and c.relname=any(__NAMES__) and(a.grantee<>c.relowner or c.relowner<>current_user::regrole or not c.relrowsecurity))
 or exists(select 1 from pg_policy where polrelid in(select oid from pg_class where relnamespace='rm_private'::regnamespace and relname=any(__NAMES__))) then raise exception 'New template metadata exposed';end if;
 if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.pronamespace='rm_private'::regnamespace and p.proname=any(__FUNCTIONS__) and(a.grantee<>p.proowner or p.proowner<>current_user::regrole))
 or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  where p.oid='public.rm_sso_template_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure and(a.grantee not in(p.proowner,'service_role'::regrole) or p.proowner<>current_user::regrole))
 or not has_function_privilege('service_role','public.rm_sso_template_workshop_permit_v1(text,uuid,text,jsonb,jsonb)','execute') then raise exception 'New template function grants differ';end if;
 if(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and(n.nspname in('rm_private','storage') or n.nspname='public' and left(c.relname,3)='rm_'
 or n.nspname='auth' and c.relname in('users','identities','sessions','mfa_factors')))<>(select count(*)+5 from ow_old_tables) then raise exception 'Unexpected table set';end if;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or n.nspname='public' and left(p.proname,3)='rm_')<>(select count(*)+10 from ow_old_functions) then raise exception 'Unexpected function set';end if;
 if(select count(*) from rm_private.template_workshop_write_settings)<>1 or exists(select 1 from rm_private.template_workshop_write_settings
  where enforced or runtime_sha is not null or deployment_id is not null or activated_at is not null or database_actor is not null)
 or exists(select 1 from rm_private.template_workshop_write_permits) or exists(select 1 from rm_private.workshop_template_retirements) then raise exception 'Template guard must be staged disabled';end if;
 if(select count(*) from rm_private.workshop_template_adoption)<>1 or exists(select 1 from rm_private.workshop_template_adoption a where
  a.families<>(select families from tw_expected) or a.drafts<>(select drafts from tw_expected) or a.database_actor<>session_user
  or a.workshop_id<>(select legacy_workshop_id from rm_private.workshop_legacy_adoption))
 or(select count(*) from rm_private.workshop_template_ownership)<>(select families+drafts from tw_expected)
 or exists(select 1 from rm_private.workshop_template_ownership o where o.workshop_id<>(select workshop_id from rm_private.workshop_template_adoption) or o.database_actor<>session_user)
 or exists(select 1 from rm_private.workshop_template_ownership o where not exists(select 1 from public.rm_form_template_families f where o.object_kind='family' and f.id=o.object_id
  union all select 1 from public.rm_form_template_drafts d where o.object_kind='draft' and d.id=o.object_id)) then raise exception 'Template seed differs';end if;
end;$verify$;
""".replace('__NAMES__',array(NAMES)).replace('__FUNCTIONS__',array(FUNCTIONS))

def release_sql(source_sha256,manifest_sha256,families,drafts,*,apply=False):
    raw=SOURCE.read_bytes();manifest_bytes=MANIFEST.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=source_sha256 or hashlib.sha256(manifest_bytes).hexdigest()!=manifest_sha256:raise ValueError('Tested source/manifest changed')
    if any(type(n) is not int or n<0 for n in [families,drafts]):raise ValueError('Reviewed template counts required')
    source=raw.decode('utf-8');manifest=json.loads(manifest_bytes)
    if '\r' in source or len(re.findall(r'^begin;$',source,re.M))!=1 or len(re.findall(r'^commit;$',source,re.M))!=1:raise ValueError('Unexpected boundaries')
    if sorted(t['name'] for t in manifest['tables'])!=sorted(NAMES) or sorted(f['name'] for f in manifest['functions'])!=sorted(FUNCTIONS) or len(manifest['triggers'])!=14:raise ValueError('Incomplete template manifest')
    body=re.sub(r'^begin;\n|^commit;\s*$','',source,flags=re.M)
    query=MANIFEST_QUERY.removeprefix('select ').removesuffix(' as manifest')
    after=AFTER.replace('__MANIFEST_CHECK__',f"select {query} into actual;if actual is distinct from {literal(json.dumps(manifest))}::jsonb then raise exception 'New object manifest differs';end if;")
    # Reuse only the reviewed history guards from 057, with new pinned version.
    prior=previous.release_sql(hashlib.sha256(previous.SOURCE.read_bytes()).hexdigest(),hashlib.sha256(previous.MANIFEST.read_bytes()).hexdigest())
    history=prior[prior.index('create temporary table ow_expected_history'):prior.index(BEFORE)]
    f=previous.SOURCE
    history=history.replace(';\ndo $history$',",('057',"+literal(hashlib.sha256(f.read_bytes()).hexdigest())+");\ndo $history$",1)
    final="insert into supabase_migrations.schema_migrations(version,name,statements) values('058','rm_web_template_workshops',array["+literal(source)+"]);\n"
    final+=f"""do $final_history$ begin
if exists(select 1 from ow_old_history b where not exists(select 1 from supabase_migrations.schema_migrations h where to_jsonb(h)=b.state))
 or(select count(*) from supabase_migrations.schema_migrations)<>(select count(*)+1 from ow_old_history)
 or(select encode(sha256(convert_to(statements[1],'UTF8')),'hex') from supabase_migrations.schema_migrations where version='058') is distinct from '{source_sha256}'
then raise exception 'Final migration history differs';end if;end;$final_history$;
"""
    locks='lock table public.rm_form_template_families,public.rm_form_template_drafts,public.rm_form_template_versions,public.rm_forms in share row exclusive mode;\n'
    expected=f'create temporary table tw_expected(families bigint,drafts bigint) on commit drop;insert into tw_expected values({families},{drafts});\n'
    adopt=f'select rm_private.adopt_workshop_templates_bma_v1({families},{drafts});\n'
    proof="select jsonb_build_object('old_rows_preserved',true,'old_identity_acl_preserved',true,'exact_dispatch_only',true,'roles_preserved',true,'staged_disabled',true,'template_seed_verified',true,'old_tables_checked',(select count(*) from ow_old_tables),'old_functions_checked',(select count(*) from ow_old_functions),'full_isolation_active',false) proof;\n"
    return "begin;set local search_path='';set local timezone='UTC';set local lock_timeout='5s';set local statement_timeout='180s';\n"+locks+expected+history+BEFORE+body+adopt+after+final+proof+('commit;\n' if apply else 'rollback;\n')
