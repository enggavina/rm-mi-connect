\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_capacity;
create function rm_test_capacity.id(h text,n int) returns uuid language sql immutable as $$select(h||'cf05000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
begin;
insert into auth.users(id) values(rm_test_capacity.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_capacity.id('2',1),rm_test_capacity.id('1',1),'Capacity race planner','administrador','ativo');
insert into public.rm_projetos(id,numero,status_pcp) select rm_test_capacity.id('5',n),'CAPACITY RACE '||n,'executando' from generate_series(1,20)n;
insert into public.rm_celulas(id,nome) values(rm_test_capacity.id('4',1),'Capacity race cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite)
 select rm_test_capacity.id('6',n),rm_test_capacity.id('5',n),rm_test_capacity.id('4',1),'em_dia',true,'2026-11-16T15:00:00Z','2026-11-30T15:00:00Z' from generate_series(1,20)n;
insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by)
 select rm_test_capacity.id('7',n),'Capacity race resource '||n,'pessoa',true,'[480,480,480,480,480,0,0]','[]',rm_test_capacity.id('2',1) from generate_series(1,10)n;
insert into rm_private.capacity_bookings(resource_id,allocation_id,day,minutes,updated_by)
 select rm_test_capacity.id('7',n),rm_test_capacity.id('6',n),'2026-11-17',240,rm_test_capacity.id('2',1) from generate_series(9,10)n;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values(rm_test_capacity.id('4',1),rm_test_capacity.id('2',1),rm_test_capacity.id('2',1));
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values(extensions.digest('capacity-race-mobile','sha256'),rm_test_capacity.id('1',1),rm_test_capacity.id('2',1),rm_test_capacity.id('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
create function rm_test_capacity.run(operation text,rid uuid,payload jsonb,hold real) returns jsonb language plpgsql as $$declare result jsonb;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_capacity.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 set local role authenticated;
 if operation='mobile' then result:=public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',payload,'capacity-race-mobile');
 else result:=public.rm_web_mutate_v1(rid,operation,payload);end if;
 reset role;perform pg_sleep(hold);return jsonb_build_object('sqlstate','00000','result',result);
 exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end$$;
commit;
do $$declare scenario int;attempt int;pid_a int;pid_b int;first_result jsonb;second_result jsonb;book_payload jsonb;resource_payload jsonb;delete_payload jsonb;gantt_payload jsonb;
 first_payload jsonb;second_payload jsonb;first_operation text;second_operation text;first_id uuid;second_id uuid;context jsonb;resource_ident uuid;begin
 perform set_config('request.jwt.claim.sub',rm_test_capacity.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 perform dblink_connect('capacity_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('capacity_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('capacity_a','select pg_backend_pid()') as t(pid int);select pid into pid_b from dblink('capacity_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..10 loop
  resource_ident:=rm_test_capacity.id('7',scenario);
  select jsonb_build_object('resource_id',resource_ident,'expected_resource_version',rm_private.capacity_resource_version_v1(resource_ident),'allocation_id',a.id,'expected_allocation_updated_at',a.updated_at,
   'expected_project_version',rm_private.web_gantt_project_version_v1(a.projeto_id),'days','[{"date":"2026-11-17","minutes":240}]'::jsonb,'acknowledge_overload',false,'reason','Capacity race booking') into book_payload from public.rm_celulas_projeto a where id=rm_test_capacity.id('6',scenario);
  select jsonb_build_object('id',r.id,'expected_version',rm_private.capacity_resource_version_v1(r.id),'name',r.name||' edited','kind',r.kind,'active',r.active,'weekly_minutes',r.weekly_minutes,'exceptions',r.exceptions,'acknowledge_overload',false,'reason','Capacity race resource edit') into resource_payload from rm_private.capacity_resources r where id=resource_ident;
  context:=public.rm_web_project_delete_snapshot_v1(rm_test_capacity.id('5',scenario));
  delete_payload:=jsonb_build_object('id',rm_test_capacity.id('5',scenario),'expected_updated_at',context->'project'->>'updated_at','expected_context_version',context->>'context_version','confirm_delete',true,'justificativa','Capacity isolated race deletion');
  select jsonb_build_object('reason','Capacity Gantt race','projects',jsonb_build_array(jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id))),
   'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',jsonb_build_object('data_limite','2026-11-29')))) into gantt_payload from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id where a.id=rm_test_capacity.id('6',scenario);
  first_operation:=case when scenario in(3,9) then 'save_capacity_resource' when scenario=5 then 'mobile' when scenario=6 then 'save_gantt_plan' when scenario in(7,10) then 'delete_project' else 'save_capacity_bookings' end;
  second_operation:=case when scenario in(4,10) then 'save_capacity_resource' when scenario in(8,9) then 'delete_project' else 'save_capacity_bookings' end;
  first_payload:=case when scenario in(3,9) then resource_payload when scenario=5 then jsonb_build_object('p_celula_projeto_id',rm_test_capacity.id('6',scenario),'p_status','aguardando_coleta') when scenario=6 then gantt_payload when scenario in(7,10) then delete_payload else book_payload end;
  second_payload:=case when scenario in(4,10) then resource_payload when scenario in(8,9) then delete_payload else book_payload end;
  if scenario=1 then
   select jsonb_build_object('resource_id',resource_ident,'expected_resource_version',rm_private.capacity_resource_version_v1(resource_ident),'allocation_id',a.id,'expected_allocation_updated_at',a.updated_at,
    'expected_project_version',rm_private.web_gantt_project_version_v1(a.projeto_id),'days','[{"date":"2026-11-17","minutes":300}]'::jsonb,'acknowledge_overload',false,'reason','Competing other project demand') into second_payload from public.rm_celulas_projeto a where id=rm_test_capacity.id('6',scenario+10);
  end if;
  first_id:=gen_random_uuid();second_id:=case when scenario=2 then first_id else gen_random_uuid() end;
  perform dblink_send_query('capacity_a',format('select rm_test_capacity.run(%L,%L,%L::jsonb,1)',first_operation,first_id,first_payload::text));
  attempt:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');attempt:=attempt+1;if attempt>500 then select result into first_result from dblink_get_result('capacity_a') as t(result jsonb);raise exception 'FAIL first capacity writer % did not hold: %',scenario,first_result;end if;perform pg_sleep(.01);end loop;
  perform dblink_send_query('capacity_b',format('select rm_test_capacity.run(%L,%L,%L::jsonb,0)',second_operation,second_id,second_payload::text));
  attempt:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');attempt:=attempt+1;if attempt>200 then raise exception 'FAIL second capacity writer % did not contend',scenario;end if;perform pg_sleep(.005);end loop;
  select result into first_result from dblink_get_result('capacity_a') as t(result jsonb);perform result from dblink_get_result('capacity_a') as t(result jsonb);
  select result into second_result from dblink_get_result('capacity_b') as t(result jsonb);perform result from dblink_get_result('capacity_b') as t(result jsonb);
  if first_result->>'sqlstate'<>'00000' or second_result->>'sqlstate'<>(case when scenario in(2,9) then '00000' when scenario=7 then 'P0002' else 'PT409' end) then raise exception 'FAIL capacity race %: % / %',scenario,first_result,second_result;end if;
  if scenario not in(2,9) and exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=second_id) then raise exception 'FAIL stale capacity command left a receipt';end if;
  if scenario=2 and(not(second_result->'result'->>'idempotent_replay')::boolean or(select count(*) from rm_private.web_mutation_receipts where client_submission_id=first_id)<>1) then raise exception 'FAIL capacity retry duplicated operation';end if;
  if scenario in(1,2,4,8) and(select count(*) from rm_private.capacity_bookings where resource_id=resource_ident)<>1 then raise exception 'FAIL winning reservation lost or duplicated';end if;
  if scenario=5 and(select status from public.rm_celulas_projeto where id=rm_test_capacity.id('6',scenario))<>'aguardando_coleta' then raise exception 'FAIL queued mobile status lost';end if;
  if scenario in(7,9,10) and(exists(select 1 from public.rm_projetos where id=rm_test_capacity.id('5',scenario)) or exists(select 1 from rm_private.capacity_bookings where resource_id=resource_ident) or not exists(select 1 from rm_private.capacity_resources where id=resource_ident)) then raise exception 'FAIL confirmed deletion did not preserve shared resource';end if;
 end loop;
 perform dblink_disconnect('capacity_a');perform dblink_disconnect('capacity_b');
 exception when others then if 'capacity_a'=any(dblink_get_connections()) then perform dblink_disconnect('capacity_a');end if;if 'capacity_b'=any(dblink_get_connections()) then perform dblink_disconnect('capacity_b');end if;raise;
end$$;
select 'PASS: ten real capacity races serialize cross-project reservations, resource edits, retries, queued mobile work, Gantt dates and confirmed deletion' result;
