\set ON_ERROR_STOP on
begin;
create function pg_temp.origin_check(v boolean,msg text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.origin_deny(statement text,expected_state text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlstate=expected_state then return;end if;raise;
 end;raise exception 'FAIL: accepted: %',statement;end$$;
insert into public.rm_projetos(id,nome) values('05400000-0000-4000-8000-000000000011','LOCAL retained origin');
insert into public.rm_celulas(id,nome) values('05400000-0000-4000-8000-000000000012','LOCAL retained cell');
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"05400000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05400000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05400000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
select rm_private.workshop_assert_origin_v1('project','05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000001');
select rm_private.workshop_assert_origin_v1('cell','05400000-0000-4000-8000-000000000012','05400000-0000-4000-8000-000000000001');
select pg_temp.origin_deny($q$select rm_private.workshop_assert_origin_v1('project','05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000002')$q$,'42501');
select pg_temp.origin_deny($q$select rm_private.workshop_assert_origin_v1(null,null,null)$q$,'42501');
-- Both trigger record shapes and no-op updates are exercised.
update rm_private.workshop_project_ownership set workshop_id=workshop_id;
update rm_private.workshop_cell_ownership set workshop_id=workshop_id;
select pg_temp.origin_deny($q$update rm_private.workshop_project_ownership set workshop_id='05400000-0000-4000-8000-000000000002'$q$,'PT409');
select pg_temp.origin_deny($q$update rm_private.workshop_cell_ownership set workshop_id='05400000-0000-4000-8000-000000000002'$q$,'PT409');
select pg_temp.origin_deny($q$update rm_private.workshop_project_ownership set id='05400000-0000-4000-8000-000000000099'$q$,'PT409');
select pg_temp.origin_deny($q$update rm_private.workshop_cell_ownership set cell_id='05400000-0000-4000-8000-000000000099'$q$,'PT409');
insert into public.rm_projetos(id,nome) values('05400000-0000-4000-8000-000000000021','LOCAL unknown late project');
select pg_temp.origin_check(not exists(select 1 from rm_private.workshop_object_origins where object_id='05400000-0000-4000-8000-000000000021'),'unknown project not silently assigned');
select pg_temp.origin_deny($q$select rm_private.workshop_assert_origin_v1('project','05400000-0000-4000-8000-000000000021','05400000-0000-4000-8000-000000000001')$q$,'42501');
-- A missing business FK rolls back the origin created by BEFORE INSERT.
select pg_temp.origin_deny($q$insert into rm_private.workshop_project_ownership(id,workshop_id) values('05400000-0000-4000-8000-000000000099','05400000-0000-4000-8000-000000000001')$q$,'23503');
select pg_temp.origin_check(not exists(select 1 from rm_private.workshop_object_origins where object_id='05400000-0000-4000-8000-000000000099'),'failed assignment has no orphan origin');

-- Existing authenticated application deletion must keep working.
insert into auth.users(id) values('05400000-0000-4000-8000-000000000031');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('05400000-0000-4000-8000-000000000032','05400000-0000-4000-8000-000000000031','LOCAL origin administrator','administrador','ativo');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','05400000-0000-4000-8000-000000000031',true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
set local role authenticated;
do $$declare snapshot jsonb;result jsonb;begin
 snapshot:=public.rm_web_project_delete_snapshot_v1('05400000-0000-4000-8000-000000000011');
 if snapshot->>'can_delete'<>'true' then raise exception 'FAIL: origin ledger blocks normal deletion';end if;
 result:=public.rm_web_mutate_v1('05400000-0000-4000-8000-000000000041','delete_project',jsonb_build_object(
  'id','05400000-0000-4000-8000-000000000011','expected_updated_at',snapshot->'project'->>'updated_at',
  'expected_context_version',snapshot->>'context_version','confirm_delete',true,'justificativa','LOCAL retained history test'));
 if result->'record'->>'deleted'<>'true' then raise exception 'FAIL: real deletion failed';end if;
end$$;
reset role;
delete from public.rm_celulas where id='05400000-0000-4000-8000-000000000012';
select pg_temp.origin_check((select count(*) from rm_private.workshop_object_origins where object_id in('05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000012') and workshop_id='05400000-0000-4000-8000-000000000001')=2,'original BMA identity survives both root deletions');
select pg_temp.origin_check((select count(*) from rm_private.workshop_origin_retirements where object_id in('05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000012'))=2,'both removals recorded');
select pg_temp.origin_deny($q$select rm_private.workshop_assert_origin_v1('project','05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000001')$q$,'42501');
-- Simulate a delayed offline root using the same UUID; neither office can
-- reclaim its retired namespace. The existing project tombstone also keeps
-- refusing recreation through the original business path.
select pg_temp.origin_deny($q$insert into public.rm_projetos(id,nome) values('05400000-0000-4000-8000-000000000011','LOCAL delayed root')$q$,'PT410');
select pg_temp.origin_deny($q$insert into rm_private.workshop_project_ownership(id,workshop_id) values('05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000001')$q$,'PT410');
select pg_temp.origin_deny($q$insert into rm_private.workshop_project_ownership(id,workshop_id) values('05400000-0000-4000-8000-000000000011','05400000-0000-4000-8000-000000000002')$q$,'PT410');
-- Removing only the map records exactly that event, not a fabricated deletion.
insert into rm_private.workshop_project_ownership(id,workshop_id) values('05400000-0000-4000-8000-000000000021','05400000-0000-4000-8000-000000000001');
savepoint before_remove;
delete from public.rm_projetos where id='05400000-0000-4000-8000-000000000021';
rollback to before_remove;
select pg_temp.origin_check(not exists(select 1 from rm_private.workshop_origin_retirements where object_id='05400000-0000-4000-8000-000000000021'),'rolled back deletion restores active map and history');
delete from rm_private.workshop_project_ownership where id='05400000-0000-4000-8000-000000000021';
select pg_temp.origin_check(exists(select 1 from public.rm_projetos where id='05400000-0000-4000-8000-000000000021') and exists(select 1 from rm_private.workshop_origin_retirements where object_id='05400000-0000-4000-8000-000000000021' and reason='ownership_removed'),'metadata removal does not claim physical root deletion');
do $$declare tbl text;role_name text;fn regprocedure;begin
 foreach tbl in array array['workshop_object_origins','workshop_origin_retirements'] loop
  perform pg_temp.origin_deny('update rm_private.'||tbl||' set object_id=object_id','42501');
  perform pg_temp.origin_deny('delete from rm_private.'||tbl,'42501');
  perform pg_temp.origin_deny('truncate rm_private.'||tbl||' cascade','42501');
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_table_privilege(role_name,'rm_private.'||tbl,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then raise exception 'FAIL: ledger exposed';end if;
  end loop;
 end loop;
 perform pg_temp.origin_deny('truncate rm_private.workshop_project_ownership','42501');
 perform pg_temp.origin_deny('truncate rm_private.workshop_cell_ownership','42501');
 foreach fn in array array['rm_private.workshop_origin_immutable_v1()'::regprocedure,'rm_private.workshop_capture_origin_v1()'::regprocedure,'rm_private.workshop_assert_origin_v1(text,uuid,uuid)'::regprocedure,'rm_private.workshop_origin_readiness_v1()'::regprocedure] loop
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_function_privilege(role_name,fn,'EXECUTE') then raise exception 'FAIL: function exposed';end if;
  end loop;
 end loop;
end$$;
select pg_temp.origin_check((rm_private.workshop_origin_readiness_v1()->>'mappings_without_matching_origin')::bigint=0,'all remaining mappings match history');
select pg_temp.origin_check((rm_private.workshop_origin_readiness_v1()->>'mappings_with_retirement')::bigint=0,'no active retired namespace');
select pg_temp.origin_check((rm_private.workshop_origin_readiness_v1()->>'origins_without_mapping_or_retirement')::bigint=0,'no lost retirement');
select pg_temp.origin_check(not (rm_private.workshop_origin_readiness_v1()->>'isolation_active')::boolean,'history is not full isolation');
rollback;
\echo PASS: workshop origin retention, real deletion, delayed offline IDs, immutable history, rollback and private boundaries.
