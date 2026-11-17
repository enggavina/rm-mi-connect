\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_execution;
create function rm_test_execution.id(h text,n int) returns uuid language sql immutable as $$select(h||'cf05100-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function rm_test_execution.event(s int,a int,k text,prev uuid,op int) returns jsonb language sql as $$
 select jsonb_build_object('p_session_id',rm_test_execution.id('7',s),'p_allocation_id',rm_test_execution.id('6',a),'p_previous_event_id',prev,
 'p_kind',k,'p_occurred_at',clock_timestamp(),'p_pause_reason',case when k='pause' then 'material' else null end,'p_note',null,'p_effort_minutes',null,'p_operador_id',rm_test_execution.id('2',op+1));
$$;
begin;
insert into auth.users(id) values(rm_test_execution.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_execution.id('2',1),rm_test_execution.id('1',1),'Execution race supervisor','administrador','ativo');
insert into public.rm_users(id,nome,perfil,status) select rm_test_execution.id('2',n+1),'Execution race operator '||n,'mobile','ativo' from generate_series(1,20)n;
insert into public.rm_celulas(id,nome) values(rm_test_execution.id('4',1),'Execution race cell');
insert into public.rm_projetos(id,numero) select rm_test_execution.id('5',n),'EXECUTION RACE '||n from generate_series(1,30)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
 select rm_test_execution.id('6',n),rm_test_execution.id('5',n),rm_test_execution.id('4',1),'em_dia',true from generate_series(1,30)n;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) select rm_test_execution.id('4',1),rm_test_execution.id('2',1),rm_test_execution.id('2',n+1) from generate_series(1,20)n;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 select extensions.digest('execution-race-'||n,'sha256'),rm_test_execution.id('1',1),rm_test_execution.id('2',1),rm_test_execution.id('2',n+1),clock_timestamp()+interval '1 day' from generate_series(1,20)n;
update rm_private.sso_settings set require_sso=false;
create function rm_test_execution.run(operation text,rid uuid,payload jsonb,op int,hold real) returns jsonb language plpgsql as $$declare result jsonb;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_execution.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 set local role authenticated;
 if operation='mobile' then result:=public.rm_mobile_mutate_v1(rid,'rm_record_execution_event_v1',payload,'execution-race-'||op);
 else result:=public.rm_web_mutate_v1(rid,operation,payload);end if;
 reset role;perform pg_sleep(hold);return jsonb_build_object('sqlstate','00000','result',result);
 exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end$$;
select rm_test_execution.run('mobile',rm_test_execution.id('a',30),rm_test_execution.event(3,3,'start',null,3),3,0);
select rm_test_execution.run('mobile',rm_test_execution.id('a',40),rm_test_execution.event(4,4,'start',null,4),4,0);
select rm_test_execution.run('mobile',rm_test_execution.id('a',50),rm_test_execution.event(5,5,'start',null,5),5,0);
select rm_test_execution.run('mobile',rm_test_execution.id('a',60),rm_test_execution.event(6,6,'start',null,6),6,0);
select rm_test_execution.run('mobile',rm_test_execution.id('a',70),rm_test_execution.event(7,7,'start',null,7),7,0);
select rm_test_execution.run('mobile',rm_test_execution.id('a',100),rm_test_execution.event(10,10,'start',null,10),10,0);
commit;
do $$declare scenario int;attempt int;pid_a int;first_result jsonb;second_result jsonb;first_payload jsonb;second_payload jsonb;first_operation text;second_operation text;first_id uuid;second_id uuid;first_op int;second_op int;review_payload jsonb;delete_payload jsonb;context jsonb;begin
 perform set_config('request.jwt.claim.sub',rm_test_execution.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 perform dblink_connect('execution_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('execution_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('execution_a','select pg_backend_pid()') as t(pid int);
 for scenario in 1..10 loop
  first_operation:='mobile';second_operation:='mobile';first_op:=scenario;second_op:=scenario;
  first_id:=rm_test_execution.id('b',scenario*10+1);second_id:=rm_test_execution.id('b',scenario*10+2);
  first_payload:=rm_test_execution.event(scenario,scenario,'start',null,scenario);second_payload:=first_payload;
  if scenario in(3,4,5) then
   review_payload:=jsonb_build_object('session_id',rm_test_execution.id('7',scenario),'expected_version',rm_private.execution_session_version_v1(rm_test_execution.id('7',scenario)),
    'action','confirm_finished','reported_finished_at',clock_timestamp(),'effort_minutes',30,'note','Concurrent supervisor reconciliation','reason','Execution race review');
  end if;
  if scenario in(6,7) then
   context:=public.rm_web_project_delete_snapshot_v1(rm_test_execution.id('5',scenario));
   delete_payload:=jsonb_build_object('id',rm_test_execution.id('5',scenario),'expected_updated_at',context->'project'->>'updated_at','expected_context_version',context->>'context_version','confirm_delete',true,'justificativa','Execution isolated race deletion');
  end if;
  case scenario
   when 1 then second_payload:=rm_test_execution.event(101,21,'start',null,1);
   when 2 then second_id:=first_id;
   when 3 then first_operation:='review_execution_session';first_payload:=review_payload;second_payload:=rm_test_execution.event(3,3,'pause',rm_test_execution.id('a',30),3);
   when 4 then first_payload:=rm_test_execution.event(4,4,'pause',rm_test_execution.id('a',40),4);second_operation:='review_execution_session';second_payload:=review_payload;
   when 5 then first_operation:='review_execution_session';second_operation:='review_execution_session';first_payload:=review_payload;second_payload:=review_payload;
   when 6 then first_operation:='delete_project';first_payload:=delete_payload;second_payload:=rm_test_execution.event(6,6,'pause',rm_test_execution.id('a',60),6);
   when 7 then first_payload:=rm_test_execution.event(7,7,'pause',rm_test_execution.id('a',70),7);second_operation:='delete_project';second_payload:=delete_payload;
   when 8 then second_payload:=rm_test_execution.event(108,8,'start',null,18);second_op:=18;
   when 9 then second_payload:=rm_test_execution.event(9,9,'start',null,19);second_op:=19;
   when 10 then first_payload:=rm_test_execution.event(10,10,'pause',rm_test_execution.id('a',100),10);second_payload:=first_payload;
  end case;
  perform dblink_send_query('execution_a',format('select rm_test_execution.run(%L,%L::uuid,%L::jsonb,%s,0.4)',first_operation,first_id,first_payload,first_op));
  for attempt in 1..200 loop
   exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');perform pg_sleep(0.01);
  end loop;
  if attempt=200 then raise exception 'FAIL first execution race did not reach lock hold';end if;
  perform dblink_send_query('execution_b',format('select rm_test_execution.run(%L,%L::uuid,%L::jsonb,%s,0)',second_operation,second_id,second_payload,second_op));
  select result into first_result from dblink_get_result('execution_a') as t(result jsonb);
  perform * from dblink_get_result('execution_a') as t(result jsonb);
  select result into second_result from dblink_get_result('execution_b') as t(result jsonb);
  perform * from dblink_get_result('execution_b') as t(result jsonb);
  if first_result->>'sqlstate'<>'00000' then raise exception 'FAIL execution race % first: %',scenario,first_result;end if;
  if scenario in(4,5,7) then
   if second_result->>'sqlstate'<>'PT409' then raise exception 'FAIL execution stale review/delete race %: %',scenario,second_result;end if;
  elsif scenario=6 then
   if second_result->>'sqlstate'<>'P0002' then raise exception 'FAIL execution deletion race: %',second_result;end if;
  elsif scenario=9 then
   if second_result->>'sqlstate'<>'42501' then raise exception 'FAIL execution ownership race: %',second_result;end if;
  else
   if second_result->>'sqlstate'<>'00000' then raise exception 'FAIL execution race % second: %',scenario,second_result;end if;
   if scenario in(1,3,10) and second_result->'result'->>'disposition'<>'review' then raise exception 'FAIL competing execution evidence not preserved: %',second_result;end if;
   if scenario=2 and second_result->'result'->>'idempotent_replay'<>'true' then raise exception 'FAIL concurrent execution retry duplicated';end if;
   if scenario=8 and second_result->'result'->>'disposition'<>'accepted' then raise exception 'FAIL independent operator blocked';end if;
  end if;
 end loop;
 perform dblink_disconnect('execution_a');perform dblink_disconnect('execution_b');
 exception when others then if 'execution_a'=any(dblink_get_connections()) then perform dblink_disconnect('execution_a');end if;if 'execution_b'=any(dblink_get_connections()) then perform dblink_disconnect('execution_b');end if;raise;
end$$;
select 'PASS: ten execution races preserve conflicts, canonical operator claims, exact retries, management versions and project deletion' result;
