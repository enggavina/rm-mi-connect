\set ON_ERROR_STOP on
begin;
create function pg_temp.ow_check(v boolean,msg text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.ow_manifest() returns jsonb language sql immutable as $$select
 '[{"id":"05300000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05300000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05300000-0000-4000-8000-000000000003","code":"BBH"}]'::jsonb$$;
create function pg_temp.ow_source() returns text language sql immutable as $$select 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2'::text$$;
create function pg_temp.ow_deny(m jsonb,h text,np bigint,nc bigint) returns void language plpgsql as $$begin
 begin perform rm_private.workshop_adopt_bma_roots_v1(m,h,np,nc);
 exception when sqlstate '22023' or sqlstate 'PT409' then return;end;
 raise exception 'FAIL: invalid adoption accepted';end$$;

select pg_temp.ow_check(not (rm_private.workshop_ownership_readiness_v1()->>'adoption_recorded')::boolean,'foundation starts empty');
select pg_temp.ow_check(not exists(select 1 from rm_private.workshop_references),'no invented central identities');
insert into public.rm_projetos(id,nome) values('05300000-0000-4000-8000-000000000011','Ownership project BMA local test');
insert into public.rm_celulas(id,nome) values('05300000-0000-4000-8000-000000000012','Ownership cell BMA local test');
create temporary table ow_roots on commit drop as select
 (select count(*) from public.rm_projetos) np,(select count(*) from public.rm_celulas) nc,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by id)::text,'')) from public.rm_projetos p) project_hash,
 (select md5(coalesce(jsonb_agg(to_jsonb(c) order by id)::text,'')) from public.rm_celulas c) cell_hash;

do $$declare m jsonb;bad jsonb;begin
 for bad in select v from (values ('{}'::jsonb),('null'::jsonb),('[]'::jsonb),
   (pg_temp.ow_manifest()||'[ {"id":"05300000-0000-4000-8000-000000000004","code":"EXTRA"}]'::jsonb),
   (jsonb_set(pg_temp.ow_manifest(),'{0,default}','true')),
   (jsonb_set(pg_temp.ow_manifest(),'{0,id}','"BMA"')),
   (jsonb_set(pg_temp.ow_manifest(),'{0,code}','"BRJ"')),
   (jsonb_set(pg_temp.ow_manifest(),'{0,id}','"05300000-0000-4000-8000-000000000002"'))) s(v)
 loop perform pg_temp.ow_deny(bad,pg_temp.ow_source(),(select np from ow_roots),(select nc from ow_roots));end loop;
 perform pg_temp.ow_deny(pg_temp.ow_manifest(),'wrong-user-confirmation',(select np from ow_roots),(select nc from ow_roots));
 perform pg_temp.ow_deny(pg_temp.ow_manifest(),pg_temp.ow_source(),(select np+1 from ow_roots),(select nc from ow_roots));
 perform pg_temp.ow_check(not exists(select 1 from rm_private.workshop_legacy_adoption),'invalid batch leaves no receipt');
 perform pg_temp.ow_check(not exists(select 1 from rm_private.workshop_references),'invalid batch leaves no identities');
end$$;

select pg_temp.ow_check((rm_private.workshop_adopt_bma_roots_v1(pg_temp.ow_manifest(),pg_temp.ow_source(),np,nc)->>'replayed')='false','first classification applies') from ow_roots;
select pg_temp.ow_check((select count(*) from rm_private.workshop_references)=3,'exactly three authority references');
select pg_temp.ow_check((select count(*) from rm_private.workshop_project_ownership)=(select np from ow_roots),'all original projects mapped');
select pg_temp.ow_check((select count(*) from rm_private.workshop_cell_ownership)=(select nc from ow_roots),'all original cells mapped');
select pg_temp.ow_check(not exists(select 1 from rm_private.workshop_project_ownership where workshop_id<>'05300000-0000-4000-8000-000000000001'),'no project assigned to BRJ/BBH');
select pg_temp.ow_check(not exists(select 1 from rm_private.workshop_cell_ownership where workshop_id<>'05300000-0000-4000-8000-000000000001'),'no cell assigned to BRJ/BBH');
select pg_temp.ow_check((select project_hash from ow_roots)=(select md5(coalesce(jsonb_agg(to_jsonb(p) order by id)::text,'')) from public.rm_projetos p),'project contents IDs and timestamps preserved');
select pg_temp.ow_check((select cell_hash from ow_roots)=(select md5(coalesce(jsonb_agg(to_jsonb(c) order by id)::text,'')) from public.rm_celulas c),'cell contents IDs and timestamps preserved');
select pg_temp.ow_check((select database_actor=session_user and phase='foundation_only' from rm_private.workshop_legacy_adoption),'technical role recorded without simulated user');
select pg_temp.ow_check(not (rm_private.workshop_ownership_readiness_v1()->>'isolation_active')::boolean,'classification is not activation');

-- New online or later offline roots NEVER silently inherit BMA on a retry.
insert into public.rm_projetos(id,nome) values('05300000-0000-4000-8000-000000000021','Later unclassified project local test');
insert into public.rm_celulas(id,nome) values('05300000-0000-4000-8000-000000000022','Later unclassified cell local test');
select pg_temp.ow_check((rm_private.workshop_adopt_bma_roots_v1(pg_temp.ow_manifest(),pg_temp.ow_source(),np,nc)->>'replayed')='true','exact retry acknowledges original batch') from ow_roots;
select pg_temp.ow_check((rm_private.workshop_ownership_readiness_v1()->>'projects_pending')::bigint=1,'later project remains pending');
select pg_temp.ow_check((rm_private.workshop_ownership_readiness_v1()->>'cells_pending')::bigint=1,'later cell remains pending');
select pg_temp.ow_check((select count(*) from rm_private.workshop_legacy_adoption)=1,'retry has one immutable receipt');
select pg_temp.ow_deny(jsonb_set(pg_temp.ow_manifest(),'{0,id}','"05300000-0000-4000-8000-000000000099"'),pg_temp.ow_source(),np,nc) from ow_roots;
select pg_temp.ow_deny(pg_temp.ow_manifest(),pg_temp.ow_source(),np+1,nc+1) from ow_roots;
do $$begin
 begin update rm_private.workshop_legacy_adoption set phase='foundation_only';raise exception 'FAIL: receipt mutable';exception when insufficient_privilege then null;end;
 begin delete from rm_private.workshop_legacy_adoption;raise exception 'FAIL: receipt deletable';exception when insufficient_privilege then null;end;
end$$;

-- Exercise the real deletion gateway after classification, not just raw SQL.
insert into auth.users(id) values('05300000-0000-4000-8000-000000000031');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('05300000-0000-4000-8000-000000000032','05300000-0000-4000-8000-000000000031','Ownership local test administrator','administrador','ativo');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','05300000-0000-4000-8000-000000000031',true);
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
set local role authenticated;
do $$declare snapshot jsonb;payload jsonb;result jsonb;begin
 snapshot:=public.rm_web_project_delete_snapshot_v1('05300000-0000-4000-8000-000000000011');
 if snapshot->>'can_delete'<>'true' then raise exception 'FAIL: classified project incorrectly seen as shared';end if;
 payload:=jsonb_build_object('id','05300000-0000-4000-8000-000000000011','expected_updated_at',snapshot->'project'->>'updated_at',
  'expected_context_version',snapshot->>'context_version','confirm_delete',true,'justificativa','Remove classified local fixture');
 result:=public.rm_web_mutate_v1('05300000-0000-4000-8000-000000000041','delete_project',payload);
 if result->'record'->>'deleted'<>'true' then raise exception 'FAIL: existing delete gateway blocked';end if;
end$$;
reset role;
delete from public.rm_celulas where id='05300000-0000-4000-8000-000000000012';
select pg_temp.ow_check(not exists(select 1 from rm_private.workshop_project_ownership where id='05300000-0000-4000-8000-000000000011'),'project removal keeps mapping consistent');
select pg_temp.ow_check(not exists(select 1 from rm_private.workshop_cell_ownership where cell_id='05300000-0000-4000-8000-000000000012'),'cell removal keeps mapping consistent');

do $$declare role_name text;tbl text;fn regprocedure;begin
 foreach role_name in array array['anon','authenticated','service_role'] loop
  foreach tbl in array array['workshop_references','workshop_legacy_adoption','workshop_project_ownership','workshop_cell_ownership'] loop
   if has_table_privilege(role_name,'rm_private.'||tbl,'SELECT,INSERT,UPDATE,DELETE') then raise exception 'FAIL: client table privilege: % %',role_name,tbl;end if;
  end loop;
  foreach fn in array array['rm_private.workshop_adopt_bma_roots_v1(jsonb,text,bigint,bigint)'::regprocedure,'rm_private.workshop_ownership_readiness_v1()'::regprocedure] loop
   if has_function_privilege(role_name,fn,'EXECUTE') then raise exception 'FAIL: client can operate ownership: %',role_name;end if;
  end loop;
 end loop;
end$$;
rollback;
\echo PASS: workshop ownership foundation, BMA declaration, exact replay, no default grants, preserved roots and private ACLs.
