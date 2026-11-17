-- Exercise the exact migration in the same backend that warmed the old Gantt
-- snapshot, version, public dispatch and confirmed-deletion functions.
\set ON_ERROR_STOP on
\if :{?rm_migration_050_path}
\else
\echo 'Isolated runner must supply migration050 path.'
\quit 3
\endif
select set_config('rm.test.migration_050_path',:'rm_migration_050_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
insert into auth.users(id) values('1bf05000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2bf05000-0000-4000-8000-000000000001','1bf05000-0000-4000-8000-000000000001','Capacity upgrade planner','administrador','ativo');
insert into public.rm_projetos(id,numero) values('5bf05000-0000-4000-8000-000000000001','CAPACITY UPGRADE50');
insert into public.rm_celulas(id,nome) values('4bf05000-0000-4000-8000-000000000001','Capacity upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite,observacao)
 values('6bf05000-0000-4000-8000-000000000001','5bf05000-0000-4000-8000-000000000001','4bf05000-0000-4000-8000-000000000001','em_dia',true,'2026-11-01T05:12:34.123456Z','2026-11-10T15:00:00Z','Existing offline work');
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values('4bf05000-0000-4000-8000-000000000001','2bf05000-0000-4000-8000-000000000001','2bf05000-0000-4000-8000-000000000001');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('capacity-upgrade-mobile','sha256'),'1bf05000-0000-4000-8000-000000000001','2bf05000-0000-4000-8000-000000000001','2bf05000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1bf05000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create temporary table capacity_upgrade_payload(payload jsonb);
grant select on capacity_upgrade_payload to authenticated;
insert into capacity_upgrade_payload select jsonb_build_object('reason','Existing Gantt receipt','projects',jsonb_build_array(jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id))),
 'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',jsonb_build_object('data_limite','2026-11-14')))) from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id where a.id='6bf05000-0000-4000-8000-000000000001';
set local role authenticated;
select public.rm_web_mutate_v1('7bf05000-0000-4000-8000-000000000001','save_gantt_plan',(select payload from capacity_upgrade_payload));
select public.rm_mobile_mutate_v1('7bf05000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6bf05000-0000-4000-8000-000000000001","p_status":"em_dia"}','capacity-upgrade-mobile');
select public.rm_web_gantt_snapshot_v1('{"project_id":"5bf05000-0000-4000-8000-000000000001","cell_id":null,"include_closed":true}');
select public.rm_web_project_delete_snapshot_v1('5bf05000-0000-4000-8000-000000000001');
reset role;
create temporary table capacity_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table capacity_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table capacity_upgrade_policies(id oid primary key,value jsonb);
create temporary table capacity_upgrade_versions(value text);
insert into capacity_upgrade_versions select rm_private.web_gantt_project_version_v1('5bf05000-0000-4000-8000-000000000001');
do $$declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or ns.nspname='storage') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into capacity_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into capacity_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into capacity_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_050_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected050 source wrappers';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare item record;actual_count bigint;actual_hash text;expected text;begin
 for item in select * from capacity_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',item.name) into actual_count,actual_hash;
  if actual_count<>item.rows or actual_hash<>item.hash then raise exception 'FAIL: upgrade changed existing rows: %',item.name;end if;
 end loop;
 if exists(select 1 from capacity_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.value)) then raise exception 'FAIL: existing RLS policy changed';end if;
 for item in select * from capacity_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=item.id and coalesce(p.proacl::text,'')=item.acl and p.proowner=item.owner) then raise exception 'FAIL: existing function ACL/owner changed: %',item.name;end if;
  expected:=item.definition;
  if item.name='web_mutate_core_v1' then expected:=replace(expected,'FUNCTION rm_private.web_mutate_core_v1(','FUNCTION rm_private.web_mutate_before_capacity_v1(');
  elsif item.name='project_delete_scope_v1' then expected:=replace(expected,'FUNCTION rm_private.project_delete_scope_v1(','FUNCTION rm_private.project_delete_scope_before_capacity_v1(');
  elsif item.name in('web_mutate_before_route_config_v1','rm_sso_action_permit_v1') then continue;end if;
  if pg_get_functiondef(item.id)<>expected then raise exception 'FAIL: unrelated legacy function changed: %',item.name;end if;
 end loop;
 if exists(select 1 from rm_private.capacity_resources) or exists(select 1 from rm_private.capacity_bookings) then raise exception 'FAIL: migration generated capacity data';end if;
 if rm_private.web_gantt_project_version_v1('5bf05000-0000-4000-8000-000000000001')<>(select value from capacity_upgrade_versions) then raise exception 'FAIL: capacity installation invalidated Gantt drafts';end if;
end$$;
set local role authenticated;
do $$declare result jsonb;snapshot jsonb;payload jsonb;ident uuid;before_delete text;begin
 result:=public.rm_web_mutate_v1('7bf05000-0000-4000-8000-000000000001','save_gantt_plan',(select p.payload from capacity_upgrade_payload p));
 if result->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre050 Gantt receipt replay';end if;
 result:=public.rm_mobile_mutate_v1('7bf05000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6bf05000-0000-4000-8000-000000000001","p_status":"em_dia"}','capacity-upgrade-mobile');
 if result->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre050 mobile receipt replay';end if;
 before_delete:=public.rm_web_project_delete_snapshot_v1('5bf05000-0000-4000-8000-000000000001')->>'context_version';
 result:=public.rm_web_mutate_v1('7bf05000-0000-4000-8000-000000000003','save_capacity_resource','{"id":null,"expected_version":null,"name":"Upgrade resource","kind":"maquina","active":true,"weekly_minutes":[480,480,480,480,480,480,480],"exceptions":[],"acknowledge_overload":false,"reason":"Upgrade declared resource"}');
 ident:=(result->>'id')::uuid;
 snapshot:=public.rm_web_capacity_snapshot_v1('{"start":"2026-11-09","days":7,"project_id":"5bf05000-0000-4000-8000-000000000001"}');
 if jsonb_array_length(snapshot->'resources')<>1 or snapshot->>'complete'<>'true' then raise exception 'FAIL: new snapshot projection';end if;
 payload:=jsonb_build_object('resource_id',ident,'expected_resource_version',snapshot->'resources'->0->>'version','allocation_id','6bf05000-0000-4000-8000-000000000001',
  'expected_allocation_updated_at',snapshot->'project_plan'->'items'->0->>'updated_at','expected_project_version',snapshot->'project_plan'->'projects'->0->>'plan_version',
  'days','[{"date":"2026-11-10","minutes":240}]'::jsonb,'acknowledge_overload',false,'reason','Upgrade first reservation');
 result:=public.rm_web_mutate_v1('7bf05000-0000-4000-8000-000000000004','save_capacity_bookings',payload);
 if result->'record'->>'changed_days'<>'1' then raise exception 'FAIL: warmed dispatch missed booking core';end if;
 snapshot:=public.rm_web_project_delete_snapshot_v1('5bf05000-0000-4000-8000-000000000001');
 if snapshot->>'context_version'=before_delete then raise exception 'FAIL: warmed delete context missed capacity closure';end if;
 payload:=jsonb_build_object('id','5bf05000-0000-4000-8000-000000000001','expected_updated_at',snapshot->'project'->>'updated_at','expected_context_version',snapshot->>'context_version','confirm_delete',true,'justificativa','Delete isolated upgrade reservation');
 result:=public.rm_web_mutate_v1('7bf05000-0000-4000-8000-000000000005','delete_project',payload);
 if result->'record'->>'deleted'<>'true' or not exists(select 1 from rm_private.capacity_resources where id=ident) or exists(select 1 from rm_private.capacity_bookings where resource_id=ident) then raise exception 'FAIL: warmed deletion did not preserve shared resource and remove booking';end if;
end$$;
reset role;
rollback;
\i :rm_migration_050_path
select 'PASS: 050 preserves every old row/OID/ACL/owner/RLS/Gantt version and queued receipt, with warmed dispatch and confirmed deletion' result;
