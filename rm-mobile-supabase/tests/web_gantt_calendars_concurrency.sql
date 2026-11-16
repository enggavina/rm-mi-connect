\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_calendar;
create function rm_test_calendar.id(h text,n int) returns uuid language sql immutable as $$select(h||'c490000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
begin;
insert into auth.users(id) values(rm_test_calendar.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_calendar.id('2',1),rm_test_calendar.id('1',1),'Calendar race planner','administrador','ativo');
insert into public.rm_projetos(id,numero,status_pcp) select rm_test_calendar.id('5',n),'CALENDAR RACE '||n,'executando' from generate_series(1,5)n;
insert into public.rm_celulas(id,nome) values(rm_test_calendar.id('4',1),'Calendar race cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite)
 select rm_test_calendar.id('6',n),rm_test_calendar.id('5',n),rm_test_calendar.id('4',1),'em_dia',true,'2026-11-10T15:00:00Z','2026-11-11T15:00:00Z' from generate_series(1,5)n;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) values(rm_test_calendar.id('4',1),rm_test_calendar.id('2',1),rm_test_calendar.id('2',1));
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values(extensions.digest('calendar-race-mobile','sha256'),rm_test_calendar.id('1',1),rm_test_calendar.id('2',1),rm_test_calendar.id('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
create function rm_test_calendar.run(mode text,rid uuid,p jsonb,hold real) returns jsonb language plpgsql as $$declare result jsonb;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_calendar.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 set local role authenticated;
 if mode='mobile' then result:=public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',p,'calendar-race-mobile');
 else result:=public.rm_web_mutate_v1(rid,mode,p);end if;
 reset role;perform pg_sleep(hold);return jsonb_build_object('sqlstate','00000','result',result);
 exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end$$;
commit;
do $$declare scenario int;n int;pid_a int;pid_b int;a jsonb;b jsonb;settings jsonb;gantt jsonb;first_payload jsonb;second_payload jsonb;first_mode text;second_mode text;first_id uuid;second_id uuid;begin
 perform set_config('request.jwt.claim.sub',rm_test_calendar.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 perform dblink_connect('calendar_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('calendar_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('calendar_a','select pg_backend_pid()') as t(pid int);select pid into pid_b from dblink('calendar_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..5 loop
  select jsonb_build_object('projeto_id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id),'calendar','{"weekdays":[1,2,3,4,5],"exceptions":[]}'::jsonb,'milestones','[]'::jsonb,'reason','Calendar race') into settings from public.rm_projetos p where id=rm_test_calendar.id('5',scenario);
  select jsonb_build_object('reason','Gantt race','projects',jsonb_build_array(jsonb_build_object('id',p.id,'expected_updated_at',p.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(p.id))),
   'items',jsonb_build_array(jsonb_build_object('id',a.id,'expected_updated_at',a.updated_at,'changes',jsonb_build_object('data_limite','2026-11-12')))) into gantt from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id where a.id=rm_test_calendar.id('6',scenario);
  first_mode:=case when scenario=3 then 'save_gantt_plan' when scenario=5 then 'mobile' else 'save_gantt_settings' end;
  second_mode:=case when scenario=2 then 'save_gantt_plan' else 'save_gantt_settings' end;
  first_payload:=case when scenario=3 then gantt when scenario=5 then jsonb_build_object('p_celula_projeto_id',rm_test_calendar.id('6',scenario),'p_status','aguardando_coleta') else settings end;
  second_payload:=case when scenario=2 then gantt when scenario=1 then jsonb_set(settings,'{calendar,weekdays}','[1,2,3,4]') else settings end;
  first_id:=gen_random_uuid();second_id:=case when scenario=4 then first_id else gen_random_uuid() end;
  perform dblink_send_query('calendar_a',format('select rm_test_calendar.run(%L,%L,%L::jsonb,1)',first_mode,first_id,first_payload::text));
  n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then select r into a from dblink_get_result('calendar_a') as t(r jsonb);raise exception 'FAIL calendar writer did not hold: %',a;end if;perform pg_sleep(.01);end loop;
  perform dblink_send_query('calendar_b',format('select rm_test_calendar.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL calendar writer did not contend: %',scenario;end if;perform pg_sleep(.005);end loop;
  select r into a from dblink_get_result('calendar_a') as t(r jsonb);perform r from dblink_get_result('calendar_a') as t(r jsonb);
  select r into b from dblink_get_result('calendar_b') as t(r jsonb);perform r from dblink_get_result('calendar_b') as t(r jsonb);
  if a->>'sqlstate'<>'00000' or b->>'sqlstate'<>(case when scenario=4 then '00000' else 'PT409' end) then raise exception 'FAIL calendar race %: % / %',scenario,a,b;end if;
  if scenario<>4 and exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=second_id) then raise exception 'FAIL stale settings left a receipt';end if;
  if scenario=4 and(not(b->'result'->>'idempotent_replay')::boolean or(select count(*) from rm_private.web_mutation_receipts where client_submission_id=first_id)<>1) then raise exception 'FAIL concurrent settings replay duplicated operation';end if;
  if scenario in(1,2,4) and not exists(select 1 from rm_private.gantt_project_settings where projeto_id=rm_test_calendar.id('5',scenario) and calendar->'weekdays'='[1,2,3,4,5]') then raise exception 'FAIL settings winner lost';end if;
  if scenario in(3,5) and exists(select 1 from rm_private.gantt_project_settings where projeto_id=rm_test_calendar.id('5',scenario)) then raise exception 'FAIL stale configuration persisted';end if;
  if scenario=3 and(select data_limite from public.rm_celulas_projeto where id=rm_test_calendar.id('6',scenario))<>'2026-11-12T15:00:00Z' then raise exception 'FAIL Gantt winner lost';end if;
  if scenario=5 and(select status from public.rm_celulas_projeto where id=rm_test_calendar.id('6',scenario))<>'aguardando_coleta' then raise exception 'FAIL mobile status lost';end if;
 end loop;
 perform dblink_disconnect('calendar_a');perform dblink_disconnect('calendar_b');
 exception when others then if 'calendar_a'=any(dblink_get_connections()) then perform dblink_disconnect('calendar_a');end if;if 'calendar_b'=any(dblink_get_connections()) then perform dblink_disconnect('calendar_b');end if;raise;
end$$;
select 'PASS: five real calendar races protect settings, Gantt dates, exact retries and queued mobile changes' result;
