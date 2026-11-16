-- Exercise the exact migration in the same backend that warmed the old Gantt
-- snapshot, version, public dispatch and confirmed-deletion functions.
\set ON_ERROR_STOP on
\if :{?rm_migration_049_path}
\else
\echo 'Isolated runner must supply migration049 path.'
\quit 3
\endif
select set_config('rm.test.migration_049_path',:'rm_migration_049_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
insert into auth.users(id) values('1b490000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2b490000-0000-4000-8000-000000000001','1b490000-0000-4000-8000-000000000001','Calendar upgrade planner','administrador','ativo');
insert into public.rm_projetos(id,numero) values('5b490000-0000-4000-8000-000000000001','CALENDAR UPGRADE49');
insert into public.rm_celulas(id,nome) values('4b490000-0000-4000-8000-000000000001','Calendar upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite,observacao)
 values('6b490000-0000-4000-8000-000000000001','5b490000-0000-4000-8000-000000000001','4b490000-0000-4000-8000-000000000001','em_dia',true,'2026-11-01T05:12:34.123456Z','2026-11-10T15:00:00Z','Existing offline work');
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values('4b490000-0000-4000-8000-000000000001','2b490000-0000-4000-8000-000000000001','2b490000-0000-4000-8000-000000000001');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('calendar-upgrade-mobile','sha256'),'1b490000-0000-4000-8000-000000000001','2b490000-0000-4000-8000-000000000001','2b490000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1b490000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create temporary table calendar_upgrade_payload(payload jsonb);
grant select on calendar_upgrade_payload to authenticated;
insert into calendar_upgrade_payload select jsonb_build_object('reason','Existing Gantt receipt','projects',jsonb_build_array(jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id))),
 'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',jsonb_build_object('data_limite','2026-11-14')))) from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id where a.id='6b490000-0000-4000-8000-000000000001';
set local role authenticated;
select public.rm_web_mutate_v1('7b490000-0000-4000-8000-000000000001','save_gantt_plan',(select payload from calendar_upgrade_payload));
select public.rm_mobile_mutate_v1('7b490000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6b490000-0000-4000-8000-000000000001","p_status":"em_dia"}','calendar-upgrade-mobile');
select public.rm_web_gantt_snapshot_v1('{"project_id":"5b490000-0000-4000-8000-000000000001","cell_id":null,"include_closed":true}');
select public.rm_web_project_delete_snapshot_v1('5b490000-0000-4000-8000-000000000001');
reset role;
create temporary table calendar_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table calendar_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table calendar_upgrade_policies(id oid primary key,value jsonb);
create temporary table calendar_upgrade_versions(value text);
insert into calendar_upgrade_versions select rm_private.web_gantt_project_version_v1('5b490000-0000-4000-8000-000000000001');
do $$declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or ns.nspname='storage') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into calendar_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into calendar_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into calendar_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_049_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected049 source wrappers';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare t record;n bigint;h text;expected text;begin
 for t in select * from calendar_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: upgrade changed existing rows: %',t.name;end if;
 end loop;
 if exists(select 1 from calendar_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.value)) then raise exception 'FAIL: existing RLS policy changed';end if;
 for t in select * from calendar_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner) then raise exception 'FAIL: existing function ACL/owner changed: %',t.name;end if;
  expected:=t.definition;
  if t.name='web_mutate_core_v1' then expected:=replace(expected,'FUNCTION rm_private.web_mutate_core_v1(','FUNCTION rm_private.web_mutate_before_gantt_settings_v1(');
  elsif t.name='project_delete_scope_v1' then expected:=replace(expected,'FUNCTION rm_private.project_delete_scope_v1(','FUNCTION rm_private.project_delete_scope_before_gantt_settings_v1(');
  elsif t.name='web_gantt_project_version_v1' then expected:=replace(expected,'FUNCTION rm_private.web_gantt_project_version_v1(','FUNCTION rm_private.web_gantt_project_version_before_calendar_v1(');
  elsif t.name='rm_web_gantt_snapshot_v1' then expected:=replace(expected,'FUNCTION public.rm_web_gantt_snapshot_v1(','FUNCTION rm_private.web_gantt_snapshot_before_calendar_v1(');
  elsif t.name='web_mutate_before_route_config_v1' then expected:=replace(expected,'foreach label in array array[''rm_private.gantt_baselines''','foreach label in array array[''rm_private.gantt_project_settings'',''rm_private.gantt_baselines''');
  elsif t.name='rm_sso_action_permit_v1' then expected:=replace(expected,'when ''save_gantt_plan'' then ''em.planning.manage''','when ''save_gantt_plan'' then ''em.planning.manage'' when ''save_gantt_settings'' then ''em.planning.manage''');end if;
  if pg_get_functiondef(t.id)<>expected then raise exception 'FAIL: unrelated legacy function changed: %',t.name;end if;
 end loop;
 if exists(select 1 from rm_private.gantt_project_settings) then raise exception 'FAIL: migration generated project settings';end if;
 if rm_private.web_gantt_project_version_v1('5b490000-0000-4000-8000-000000000001')<>(select value from calendar_upgrade_versions) then raise exception 'FAIL: absent settings invalidated old drafts';end if;
end$$;
set local role authenticated;
do $$declare r jsonb;s jsonb;p jsonb;before_version text;before_delete text;begin
 r:=public.rm_web_mutate_v1('7b490000-0000-4000-8000-000000000001','save_gantt_plan',(select payload from calendar_upgrade_payload));
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre049 Gantt receipt replay';end if;
 r:=public.rm_mobile_mutate_v1('7b490000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6b490000-0000-4000-8000-000000000001","p_status":"em_dia"}','calendar-upgrade-mobile');
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre049 mobile receipt replay';end if;
 s:=public.rm_web_gantt_snapshot_v1('{"project_id":"5b490000-0000-4000-8000-000000000001","cell_id":null,"include_closed":true}');before_version:=s->'projects'->0->>'plan_version';
 before_delete:=public.rm_web_project_delete_snapshot_v1('5b490000-0000-4000-8000-000000000001')->>'context_version';
 if s->'settings'<>'[]' then raise exception 'FAIL: warmed snapshot missed new projection';end if;
 p:=jsonb_build_object('projeto_id','5b490000-0000-4000-8000-000000000001','expected_updated_at',s->'projects'->0->>'updated_at','expected_plan_version',before_version,'calendar','{"weekdays":[1,2,3,4,5],"exceptions":[]}'::jsonb,'milestones','[]'::jsonb,'reason','Upgrade calendar');
 r:=public.rm_web_mutate_v1('7b490000-0000-4000-8000-000000000003','save_gantt_settings',p);
 if r->'record'->>'settings_changed'<>'true' then raise exception 'FAIL: warmed public wrapper did not reach new settings core';end if;
 s:=public.rm_web_gantt_snapshot_v1('{"project_id":"5b490000-0000-4000-8000-000000000001","cell_id":null,"include_closed":true}');
 if jsonb_array_length(s->'settings')<>1 or s->'projects'->0->>'plan_version'=before_version then raise exception 'FAIL: warmed snapshot/version retained old function OID';end if;
 r:=public.rm_web_project_delete_snapshot_v1('5b490000-0000-4000-8000-000000000001');
 if r is null or r->>'context_version'=before_delete then raise exception 'FAIL: warmed delete context omitted new settings';end if;
 r:=public.rm_web_mutate_v1('7b490000-0000-4000-8000-000000000001','save_gantt_plan',(select payload from calendar_upgrade_payload));
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: historical Gantt replay under stricter calendar';end if;
end$$;
reset role;
rollback;
\i :rm_migration_049_path
select 'PASS: 049 preserves every old row/function OID/ACL/owner/RLS, pending mobile and Gantt receipts and warmed dispatch/snapshot/version' result;
