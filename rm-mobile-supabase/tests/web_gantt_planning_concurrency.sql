\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_gantt;
create function rm_test_gantt.id(h text,n int) returns uuid language sql immutable as $$select(h||'c470000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
begin;
insert into auth.users(id) values(rm_test_gantt.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_gantt.id('2',1),rm_test_gantt.id('1',1),'Gantt race planner','administrador','ativo');
insert into public.rm_projetos(id,numero,status_pcp) select rm_test_gantt.id('5',n),'GANTT RACE '||n,'executando' from generate_series(1,7)n;
insert into public.rm_celulas(id,nome) select rm_test_gantt.id('4',n),'Gantt race cell '||n from generate_series(1,3)n;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,data_inicio,data_limite)
 select rm_test_gantt.id('6',n*10+c),rm_test_gantt.id('5',n),rm_test_gantt.id('4',c),case when n=6 and c=2 then 'pendente'::public.rm_status_cel_proj_enum else 'em_dia' end,true,'2026-11-10T15:00:00Z','2026-11-11T15:00:00Z' from generate_series(1,7)n cross join generate_series(1,2)c;
insert into public.rm_tablet_celula_users(celula_id,usuario_id,identidade_id) select rm_test_gantt.id('4',n),rm_test_gantt.id('2',1),rm_test_gantt.id('2',1) from generate_series(1,2)n;
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values(extensions.digest('gantt-races-mobile','sha256'),rm_test_gantt.id('1',1),rm_test_gantt.id('2',1),rm_test_gantt.id('2',1),clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=false;
create function rm_test_gantt.run(mode text,rid uuid,p jsonb,hold real) returns jsonb language plpgsql as $$declare result jsonb;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_gantt.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 set local role authenticated;
 if mode='gantt' then result:=public.rm_web_mutate_v1(rid,'save_gantt_plan',p);
 elsif mode='plan' then result:=public.rm_web_mutate_v1(rid,'plan_cell',p);
 elsif mode='availability' then result:=public.rm_web_mutate_v1(rid,'manage_cell_availability',p);
 else result:=public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',p,'gantt-races-mobile');end if;
 reset role;perform pg_sleep(hold);return jsonb_build_object('sqlstate','00000','result',result);
 exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end$$;
commit;
do $$declare scenario int;n int;pid_a int;pid_b int;a jsonb;b jsonb;p jsonb;s jsonb;first_payload jsonb;second_payload jsonb;first_mode text;second_mode text;first_id uuid;second_id uuid;begin
 perform set_config('request.jwt.claim.sub',rm_test_gantt.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 perform dblink_connect('gantt_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('gantt_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('gantt_a','select pg_backend_pid()') as t(pid int);select pid into pid_b from dblink('gantt_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..7 loop
  select jsonb_build_object('reason','Gantt race test','projects',jsonb_build_array(jsonb_build_object('id',project.id,'expected_updated_at',project.updated_at,'expected_plan_version',rm_private.web_gantt_project_version_v1(project.id))),
   'items',jsonb_build_array(jsonb_build_object('id',allocation.id,'expected_updated_at',allocation.updated_at,'changes',jsonb_build_object('data_limite','2026-11-12')))) into p
   from public.rm_projetos project join public.rm_celulas_projeto allocation on allocation.projeto_id=project.id where allocation.id=rm_test_gantt.id('6',scenario*10+1);
  first_mode:=case when scenario=3 then 'mobile' else 'gantt' end;second_mode:=case when scenario=4 then 'mobile' else 'gantt' end;
  first_payload:=case when scenario=3 then jsonb_build_object('p_celula_projeto_id',rm_test_gantt.id('6',scenario*10+2),'p_status','aguardando_coleta') else p end;
  if scenario=5 then
   first_mode:='plan';select jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('data_limite','2026-11-13T15:00:00Z')) into first_payload from public.rm_celulas_projeto where id=rm_test_gantt.id('6',scenario*10+2);
  elsif scenario=6 then
   first_mode:='availability';s:=public.rm_web_cell_availability_snapshot_v1(rm_test_gantt.id('5',scenario),rm_test_gantt.id('6',scenario*10+2));
   first_payload:=jsonb_build_object('action','retire','projeto_id',rm_test_gantt.id('5',scenario),'celula_projeto_id',rm_test_gantt.id('6',scenario*10+2),'expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true);
  elsif scenario=7 then
   first_mode:='plan';first_payload:=jsonb_build_object('projeto_id',rm_test_gantt.id('5',scenario),'celula_id',rm_test_gantt.id('4',3),'expected_updated_at',null,'changes',jsonb_build_object('data_limite','2026-11-13T15:00:00Z'));
  end if;
  second_payload:=case when scenario=4 then jsonb_build_object('p_celula_projeto_id',rm_test_gantt.id('6',scenario*10+2),'p_status','aguardando_coleta') when scenario=1 then jsonb_set(p,'{items,0,changes,data_limite}','"2026-11-13"') else p end;
  first_id:=gen_random_uuid();second_id:=case when scenario=2 then first_id else gen_random_uuid() end;
  perform dblink_send_query('gantt_a',format('select rm_test_gantt.run(%L,%L,%L::jsonb,1)',first_mode,first_id,first_payload::text));
  n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then select r into a from dblink_get_result('gantt_a') as t(r jsonb);raise exception 'FAIL: Gantt writer % did not hold: %',scenario,a;end if;perform pg_sleep(.01);end loop;
  perform dblink_send_query('gantt_b',format('select rm_test_gantt.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL: second Gantt writer % did not contend',scenario;end if;perform pg_sleep(.005);end loop;
  select r into a from dblink_get_result('gantt_a') as t(r jsonb);perform r from dblink_get_result('gantt_a') as t(r jsonb);
  select r into b from dblink_get_result('gantt_b') as t(r jsonb);perform r from dblink_get_result('gantt_b') as t(r jsonb);
  if a->>'sqlstate'<>'00000' or b->>'sqlstate'<>(case when scenario in(1,3,5,6,7) then 'PT409' else '00000' end) then raise exception 'FAIL: Gantt race %: % / %',scenario,a,b;end if;
  if (select data_limite from public.rm_celulas_projeto where id=rm_test_gantt.id('6',scenario*10+1)) is distinct from(case when scenario in(3,5,6,7) then '2026-11-11T15:00:00Z'::timestamptz else '2026-11-12T15:00:00Z'::timestamptz end) then raise exception 'FAIL: stale Gantt overwrote winner';end if;
  if scenario in(3,4) and(select status from public.rm_celulas_projeto where id=rm_test_gantt.id('6',scenario*10+2))<>'aguardando_coleta' then raise exception 'FAIL: offline status was lost';end if;
  if scenario=2 and(not(b->'result'->>'idempotent_replay')::boolean or(select count(*) from rm_private.web_mutation_receipts where client_submission_id=first_id)<>1) then raise exception 'FAIL: concurrent parent retry duplicated operation';end if;
  if scenario in(1,3,5,6,7) and exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=second_id) then raise exception 'FAIL: stale parent left a receipt';end if;
  if scenario=6 and not(select retirada from public.rm_celulas_projeto where id=rm_test_gantt.id('6',62)) then raise exception 'FAIL: retirement was lost';end if;
  if scenario=7 and(select count(*) from public.rm_celulas_projeto where projeto_id=rm_test_gantt.id('5',7))<>3 then raise exception 'FAIL: new route allocation was lost';end if;
 end loop;
 perform dblink_disconnect('gantt_a');perform dblink_disconnect('gantt_b');
 exception when others then if 'gantt_a'=any(dblink_get_connections()) then perform dblink_disconnect('gantt_a');end if;if 'gantt_b'=any(dblink_get_connections()) then perform dblink_disconnect('gantt_b');end if;raise;
end$$;
select 'PASS: seven real Gantt races preserve stale detection, idempotent retry, mobile work, legacy planning, retirement and new route allocations' result;
