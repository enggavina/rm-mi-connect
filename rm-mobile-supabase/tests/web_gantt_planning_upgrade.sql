-- Apply the exact migration over warmed 046 dispatch and existing web/mobile
-- work. Nothing in this proof can run against a production database.
\set ON_ERROR_STOP on
\if :{?rm_migration_047_path}
\else
\echo 'Isolated runner must supply migration047 path.'
\quit 3
\endif
select set_config('rm.test.migration_047_path',:'rm_migration_047_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
insert into auth.users(id) values('1b470000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2b470000-0000-4000-8000-000000000001','1b470000-0000-4000-8000-000000000001','Gantt upgrade planner','administrador','ativo');
insert into public.rm_projetos(id,numero) values('5b470000-0000-4000-8000-000000000001','GANTT UPGRADE47');
insert into public.rm_celulas(id,nome) values('4b470000-0000-4000-8000-000000000001','Gantt upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,observacao)
 values('6b470000-0000-4000-8000-000000000001','5b470000-0000-4000-8000-000000000001','4b470000-0000-4000-8000-000000000001','em_dia',true,'2026-11-01T05:12:34.123456Z','Existing offline work');
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values('4b470000-0000-4000-8000-000000000001','2b470000-0000-4000-8000-000000000001','2b470000-0000-4000-8000-000000000001');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('gantt-upgrade-mobile','sha256'),'1b470000-0000-4000-8000-000000000001','2b470000-0000-4000-8000-000000000001','2b470000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1b470000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create temporary table gantt_upgrade_payload(payload jsonb);
grant select on gantt_upgrade_payload to authenticated;
insert into gantt_upgrade_payload select jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('data_limite','2026-11-10T15:00:00Z')) from public.rm_celulas_projeto where id='6b470000-0000-4000-8000-000000000001';
set local role authenticated;
select public.rm_web_mutate_v1('7b470000-0000-4000-8000-000000000001','plan_cell',(select payload from gantt_upgrade_payload));
select public.rm_mobile_mutate_v1('7b470000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6b470000-0000-4000-8000-000000000001","p_status":"em_dia"}','gantt-upgrade-mobile');
select public.rm_web_project_delete_snapshot_v1('5b470000-0000-4000-8000-000000000001');
reset role;
create temporary table gantt_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table gantt_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table gantt_upgrade_policies(id oid primary key,value jsonb);
do $$declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into gantt_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into gantt_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into gantt_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_047_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected047 source wrappers';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare t record;n bigint;h text;expected text;begin
 for t in select * from gantt_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: upgrade changed existing rows: %',t.name;end if;
 end loop;
 if exists(select 1 from gantt_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.value)) then raise exception 'FAIL: existing RLS policy changed';end if;
 for t in select * from gantt_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner) then raise exception 'FAIL: existing function ACL/owner changed: %',t.name;end if;
  expected:=t.definition;
  if t.name='web_mutate_core_v1' then expected:=replace(expected,'FUNCTION rm_private.web_mutate_core_v1(','FUNCTION rm_private.web_mutate_before_gantt_v1(');
  elsif t.name='project_delete_scope_v1' then expected:=replace(expected,'FUNCTION rm_private.project_delete_scope_v1(','FUNCTION rm_private.project_delete_scope_before_gantt_v1(');
  elsif t.name in('web_mutate_before_route_config_v1','rm_sso_action_permit_v1') then continue;end if;
  if pg_get_functiondef(t.id)<>expected then raise exception 'FAIL: unrelated legacy function changed: %',t.name;end if;
 end loop;
 if exists(select 1 from rm_private.gantt_project_plans) or exists(select 1 from rm_private.gantt_baselines) then raise exception 'FAIL: migration generated planning data';end if;
end$$;
set local role authenticated;
do $$declare r jsonb;s jsonb;p jsonb;begin
 r:=public.rm_web_mutate_v1('7b470000-0000-4000-8000-000000000001','plan_cell',(select payload from gantt_upgrade_payload));
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre047 web receipt replay';end if;
 r:=public.rm_mobile_mutate_v1('7b470000-0000-4000-8000-000000000002','rm_update_cell_status_v1','{"p_celula_projeto_id":"6b470000-0000-4000-8000-000000000001","p_status":"em_dia"}','gantt-upgrade-mobile');
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre047 mobile receipt replay';end if;
 s:=public.rm_web_gantt_snapshot_v1('{"project_id":"5b470000-0000-4000-8000-000000000001","cell_id":null,"include_closed":true}');
 p:=jsonb_build_object('reason','Create first Gantt reference','projects',jsonb_build_array(jsonb_build_object('id',s->'projects'->0->>'id','expected_updated_at',s->'projects'->0->>'updated_at','expected_plan_version',s->'projects'->0->>'plan_version')),'items','[]'::jsonb,'baseline',jsonb_build_object('projeto_id','5b470000-0000-4000-8000-000000000001','label','Upgrade reference'));
 r:=public.rm_web_mutate_v1('7b470000-0000-4000-8000-000000000003','save_gantt_plan',p);
 if r->'record'->>'baseline_id' is null then raise exception 'FAIL: warmed public wrapper did not reach new core';end if;
 r:=public.rm_mobile_mutate_v1('7b470000-0000-4000-8000-000000000004','rm_update_cell_status_v1','{"p_celula_projeto_id":"6b470000-0000-4000-8000-000000000001","p_status":"aguardando_coleta"}','gantt-upgrade-mobile');
 if r is null then raise exception 'FAIL: queued mobile operation unavailable';end if;
end$$;
reset role;
rollback;
\i :rm_migration_047_path
select 'PASS: 047 preserves all existing rows, RLS policies, legacy function bodies/ACLs, old web/mobile receipts and new dispatch' result;
