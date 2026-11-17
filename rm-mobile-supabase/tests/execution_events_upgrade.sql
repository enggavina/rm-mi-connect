-- Install 051 in the same backend that warmed public/mobile/web/delete callers.
\set ON_ERROR_STOP on
\if :{?rm_migration_051_path}
\else
\echo 'Isolated runner must supply migration051 path.'
\quit 3
\endif
select set_config('rm.test.migration_051_path',:'rm_migration_051_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
insert into auth.users(id) values('1bf05100-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2bf05100-0000-4000-8000-000000000001','1bf05100-0000-4000-8000-000000000001','Execution upgrade planner','administrador','ativo');
insert into public.rm_projetos(id,numero) values('5bf05100-0000-4000-8000-000000000001','EXECUTION UPGRADE51');
insert into public.rm_celulas(id,nome) values('4bf05100-0000-4000-8000-000000000001','Execution upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite,observacao)
 values('6bf05100-0000-4000-8000-000000000001','5bf05100-0000-4000-8000-000000000001','4bf05100-0000-4000-8000-000000000001','em_dia',true,'2026-11-01T05:12:34.123456Z','2026-11-30T15:00:00Z','Existing offline work');
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values('4bf05100-0000-4000-8000-000000000001','2bf05100-0000-4000-8000-000000000001','2bf05100-0000-4000-8000-000000000001');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('execution-upgrade-mobile','sha256'),'1bf05100-0000-4000-8000-000000000001','2bf05100-0000-4000-8000-000000000001','2bf05100-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by) values('9bf05100-0000-4000-8000-000000000001','Execution upgrade preserved machine','maquina',true,'[480,480,480,480,480,0,0]','[]','2bf05100-0000-4000-8000-000000000001');
insert into rm_private.capacity_bookings(resource_id,allocation_id,day,minutes,updated_by) values('9bf05100-0000-4000-8000-000000000001','6bf05100-0000-4000-8000-000000000001','2026-11-17',120,'2bf05100-0000-4000-8000-000000000001');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1bf05100-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create function pg_temp.execution_warmed_mobile(rid uuid,rpc text,p jsonb) returns jsonb language plpgsql as $$begin return public.rm_mobile_mutate_v1(rid,rpc,p,'execution-upgrade-mobile');end$$;
set local role authenticated;
select pg_temp.execution_warmed_mobile('7bf05100-0000-4000-8000-000000000001','rm_update_cell_status_v1','{"p_celula_projeto_id":"6bf05100-0000-4000-8000-000000000001","p_status":"em_dia"}');
select public.rm_web_gantt_snapshot_v1('{"project_id":"5bf05100-0000-4000-8000-000000000001","cell_id":null,"include_closed":true}');
select public.rm_web_capacity_snapshot_v1('{"start":"2026-11-17","days":7,"project_id":null}');
select public.rm_web_project_delete_snapshot_v1('5bf05100-0000-4000-8000-000000000001');
reset role;
create temporary table execution_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table execution_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table execution_upgrade_policies(id oid primary key,value jsonb);
create temporary table execution_upgrade_versions(value text);
insert into execution_upgrade_versions select rm_private.web_gantt_project_version_v1('5bf05100-0000-4000-8000-000000000001');
do $$declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or ns.nspname='storage') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into execution_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into execution_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into execution_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_051_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected051 source wrappers';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare item record;actual_count bigint;actual_hash text;expected text;begin
 for item in select * from execution_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',item.name) into actual_count,actual_hash;
  if actual_count<>item.rows or actual_hash<>item.hash then raise exception 'FAIL: upgrade changed old rows: %',item.name;end if;
 end loop;
 if exists(select 1 from execution_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.value)) then raise exception 'FAIL: existing RLS policy changed';end if;
 for item in select * from execution_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=item.id and coalesce(p.proacl::text,'')=item.acl and p.proowner=item.owner) then raise exception 'FAIL: existing function OID/ACL/owner changed: %',item.name;end if;
  expected:=item.definition;
  if item.name='web_mutate_core_v1' then expected:=replace(expected,'FUNCTION rm_private.web_mutate_core_v1(','FUNCTION rm_private.web_mutate_before_execution_v1(');
  elsif item.name='project_delete_scope_v1' then expected:=replace(expected,'FUNCTION rm_private.project_delete_scope_v1(','FUNCTION rm_private.project_delete_scope_before_execution_v1(');
  elsif item.name in('web_mutate_before_route_config_v1','rm_sso_action_permit_v1','rm_mobile_mutate_v1') then continue;end if;
  if pg_get_functiondef(item.id)<>expected then raise exception 'FAIL: unrelated legacy function changed: %',item.name;end if;
 end loop;
 if exists(select 1 from rm_private.execution_sessions) or exists(select 1 from rm_private.execution_events) or exists(select 1 from rm_private.execution_reviews) then raise exception 'FAIL: installation generated execution evidence';end if;
 if rm_private.web_gantt_project_version_v1('5bf05100-0000-4000-8000-000000000001')<>(select value from execution_upgrade_versions) then raise exception 'FAIL: execution installation invalidated Gantt drafts';end if;
end$$;
set local role authenticated;
do $$declare r jsonb;snapshot jsonb;payload jsonb;before_delete text;begin
 r:=pg_temp.execution_warmed_mobile('7bf05100-0000-4000-8000-000000000001','rm_update_cell_status_v1','{"p_celula_projeto_id":"6bf05100-0000-4000-8000-000000000001","p_status":"em_dia"}');
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: old queued receipt changed';end if;
 before_delete:=public.rm_web_project_delete_snapshot_v1('5bf05100-0000-4000-8000-000000000001')->>'context_version';
 payload:='{"p_session_id":"8bf05100-0000-4000-8000-000000000001","p_allocation_id":"6bf05100-0000-4000-8000-000000000001","p_previous_event_id":null,"p_kind":"start","p_occurred_at":"2026-11-17T05:12:34.123456Z","p_pause_reason":null,"p_note":null,"p_effort_minutes":null,"p_operador_id":"2bf05100-0000-4000-8000-000000000001"}';
 r:=pg_temp.execution_warmed_mobile('7bf05100-0000-4000-8000-000000000002','rm_record_execution_event_v1',payload);
 if r->>'disposition'<>'accepted' then raise exception 'FAIL: warmed mobile gateway missed new RPC';end if;
 snapshot:=public.rm_mobile_execution_snapshot_v1('execution-upgrade-mobile','6bf05100-0000-4000-8000-000000000001');
 payload:=jsonb_build_object('session_id','8bf05100-0000-4000-8000-000000000001','expected_version',snapshot->'session'->>'version','action','confirm_finished','reported_finished_at',clock_timestamp(),'effort_minutes',45,'note','Explicit upgrade review','reason','Upgrade management reconciliation');
 r:=public.rm_web_mutate_v1('7bf05100-0000-4000-8000-000000000003','review_execution_session',payload);
 if r->'record'->>'review_id' is null then raise exception 'FAIL: warmed web dispatch missed review';end if;
 snapshot:=public.rm_web_project_delete_snapshot_v1('5bf05100-0000-4000-8000-000000000001');
 if snapshot->>'context_version'=before_delete then raise exception 'FAIL: warmed deletion missed execution closure';end if;
 payload:=jsonb_build_object('id','5bf05100-0000-4000-8000-000000000001','expected_updated_at',snapshot->'project'->>'updated_at','expected_context_version',snapshot->>'context_version','confirm_delete',true,'justificativa','Delete isolated execution upgrade');
 r:=public.rm_web_mutate_v1('7bf05100-0000-4000-8000-000000000004','delete_project',payload);
 if r->'record'->>'deleted'<>'true' or exists(select 1 from rm_private.execution_sessions where allocation_id='6bf05100-0000-4000-8000-000000000001') or not exists(select 1 from rm_private.capacity_resources where id='9bf05100-0000-4000-8000-000000000001') then raise exception 'FAIL: warmed deletion failed to preserve shared resource';end if;
end$$;
reset role;
rollback;
\i :rm_migration_051_path
select 'PASS: 051 preserves all old rows/OIDs/ACLs/owners/RLS/Gantt versions/queued receipts, warmed mobile/web dispatch and owned deletion' result;
