\set ON_ERROR_STOP on
do $$ begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required'; end if;end $$;
create extension if not exists dblink with schema public;
create schema rm_test_route_concurrency;
begin;
insert into auth.users(id) values('12370000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('22370000-0000-4000-8000-000000000001','12370000-0000-4000-8000-000000000001','Route race actor','administrador','ativo');
insert into public.rm_celulas(id,nome,ordem) values('42370000-0000-4000-8000-000000000001','Route race cell',1);
insert into public.rm_tipos_equipamento(id,nome) values('52370000-0000-4000-8000-000000000001','Route race type');
insert into public.rm_celula_tipos_equipamento(id,celula_id,tipo_equipamento_id,visibilidade) values('62370000-0000-4000-8000-000000000001','42370000-0000-4000-8000-000000000001','52370000-0000-4000-8000-000000000001',true);
insert into public.rm_projetos(id,nome) values('b2370000-0000-4000-8000-000000000006','Before external project edit');
insert into public.rm_equipamentos(id,projeto_id) values('c2370000-0000-4000-8000-000000000006','b2370000-0000-4000-8000-000000000006');
update public.rm_projetos set equipamento_id='c2370000-0000-4000-8000-000000000006' where id='b2370000-0000-4000-8000-000000000006';
update rm_private.sso_settings set require_sso=false;
create function rm_test_route_concurrency.run(rid uuid,p jsonb,hold_seconds numeric) returns jsonb language plpgsql as $$
declare r jsonb;state text;begin
 perform set_config('request.jwt.claim.sub','12370000-0000-4000-8000-000000000001',true);
 perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 set local role authenticated;r:=public.rm_web_mutate_v1(rid,'save_project_with_equipment',p);reset role;
 perform pg_sleep(hold_seconds);return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);end $$;
create function rm_test_route_concurrency.edit_model() returns jsonb language plpgsql as $$
begin update public.rm_celula_tipos_equipamento set visibilidade=false where id='62370000-0000-4000-8000-000000000001';return '{"sqlstate":"00000"}'::jsonb;end $$;
create function rm_test_route_concurrency.share_equipment() returns jsonb language plpgsql as $$
declare state text;begin
 insert into public.rm_projetos(id,nome,equipamento_id) values('b2370000-0000-4000-8000-000000000005','Must not share equipment','c2370000-0000-4000-8000-000000000004');
 return '{"sqlstate":"00000"}'::jsonb;
exception when others then get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state);end $$;
create function rm_test_route_concurrency.edit_project() returns jsonb language plpgsql as $$
declare state text;begin
 perform 1 from public.rm_projetos where id='b2370000-0000-4000-8000-000000000006' for update;
 perform pg_sleep(2);
 update public.rm_projetos set nome='External project winner' where id='b2370000-0000-4000-8000-000000000006';
 return '{"sqlstate":"00000"}'::jsonb;
exception when others then get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state);end $$;
commit;
do $$ declare p jsonb;s jsonb;r1 jsonb;r2 jsonb;pid_a int;pid_b int;n int;begin
 p:='{"id":"b2370000-0000-4000-8000-000000000001","expected_updated_at":null,"changes":{"nome":"Route race project"},"equipment":{"id":"c2370000-0000-4000-8000-000000000001","tipo_equipamento_id":"52370000-0000-4000-8000-000000000001","expected_updated_at":null,"expected_context_version":null,"changes":{"descricao":"Route race equipment"}}}';
 perform dblink_connect('route_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('route_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('route_a','select pg_backend_pid()') as t(pid int);
 select pid into pid_b from dblink('route_b','select pg_backend_pid()') as t(pid int);
 -- Same submission waits on request14 and returns exactly the persisted route.
 perform dblink_send_query('route_a',format('select rm_test_route_concurrency.run(%L,%L::jsonb,2)','d2370000-0000-4000-8000-000000000001',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then raise exception 'FAIL: route create did not hold';end if;perform pg_sleep(.01);end loop;
 perform dblink_send_query('route_b',format('select rm_test_route_concurrency.run(%L,%L::jsonb,0)','d2370000-0000-4000-8000-000000000001',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL: duplicate route did not contend';end if;perform pg_sleep(.005);end loop;
 select r into r1 from dblink_get_result('route_a') as t(r jsonb);perform r from dblink_get_result('route_a') as t(r jsonb);
 select r into r2 from dblink_get_result('route_b') as t(r jsonb);perform r from dblink_get_result('route_b') as t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'00000' or not (r2->'result'->>'idempotent_replay')::boolean
  or(select count(*) from rm_private.project_route_instances where projeto_id='b2370000-0000-4000-8000-000000000001')<>1
  or(select count(*) from public.rm_celulas_projeto where projeto_id='b2370000-0000-4000-8000-000000000001')<>1 then raise exception 'FAIL: duplicate route results % / %',r1,r2;end if;
 -- Different submissions for the same new project serialize on project11.
 p:=jsonb_set(jsonb_set(p,'{id}','"b2370000-0000-4000-8000-000000000002"'),'{equipment,id}','"c2370000-0000-4000-8000-000000000002"');
 perform dblink_send_query('route_a',format('select rm_test_route_concurrency.run(%L,%L::jsonb,2)','d2370000-0000-4000-8000-000000000002',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then raise exception 'FAIL: winner route did not hold';end if;perform pg_sleep(.01);end loop;
 perform dblink_send_query('route_b',format('select rm_test_route_concurrency.run(%L,%L::jsonb,0)','d2370000-0000-4000-8000-000000000003',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL: competing route did not contend';end if;perform pg_sleep(.005);end loop;
 select r into r1 from dblink_get_result('route_a') as t(r jsonb);perform r from dblink_get_result('route_a') as t(r jsonb);
 select r into r2 from dblink_get_result('route_b') as t(r jsonb);perform r from dblink_get_result('route_b') as t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'PT409' or exists(select 1 from rm_private.web_mutation_receipts where client_submission_id='d2370000-0000-4000-8000-000000000003')
  or(select count(*) from public.rm_celulas_projeto where projeto_id='b2370000-0000-4000-8000-000000000002')<>1 then raise exception 'FAIL: competing create results % / %',r1,r2;end if;
 -- Engineering mutation waits for the source pair read by initialization.
 p:=jsonb_set(jsonb_set(p,'{id}','"b2370000-0000-4000-8000-000000000003"'),'{equipment,id}','"c2370000-0000-4000-8000-000000000003"');
 perform dblink_send_query('route_a',format('select rm_test_route_concurrency.run(%L,%L::jsonb,2)','d2370000-0000-4000-8000-000000000004',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then raise exception 'FAIL: snapshot route did not hold';end if;perform pg_sleep(.01);end loop;
 perform dblink_send_query('route_b','select rm_test_route_concurrency.edit_model()');
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL: template edit did not contend';end if;perform pg_sleep(.005);end loop;
 select r into r1 from dblink_get_result('route_a') as t(r jsonb);perform r from dblink_get_result('route_a') as t(r jsonb);
 select r into r2 from dblink_get_result('route_b') as t(r jsonb);perform r from dblink_get_result('route_b') as t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'00000'
  or not(select visibilidade from public.rm_celulas_projeto where projeto_id='b2370000-0000-4000-8000-000000000003')
  or(select visibilidade from public.rm_celula_tipos_equipamento where id='62370000-0000-4000-8000-000000000001') then raise exception 'FAIL: later template mutation changed frozen route';end if;
 -- An unrelated INSERT must wait on the canonical equipment row BEFORE it
 -- checks route ownership, including when the route marker is uncommitted.
 p:=jsonb_set(jsonb_set(p,'{id}','"b2370000-0000-4000-8000-000000000004"'),'{equipment,id}','"c2370000-0000-4000-8000-000000000004"');
 perform dblink_send_query('route_a',format('select rm_test_route_concurrency.run(%L,%L::jsonb,2)','d2370000-0000-4000-8000-000000000005',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then raise exception 'FAIL: protected binding route did not hold';end if;perform pg_sleep(.01);end loop;
 perform dblink_send_query('route_b','select rm_test_route_concurrency.share_equipment()');
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL: unrelated project insert did not contend';end if;perform pg_sleep(.005);end loop;
 select r into r1 from dblink_get_result('route_a') as t(r jsonb);perform r from dblink_get_result('route_a') as t(r jsonb);
 select r into r2 from dblink_get_result('route_b') as t(r jsonb);perform r from dblink_get_result('route_b') as t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'PT409'
  or exists(select 1 from public.rm_projetos where id='b2370000-0000-4000-8000-000000000005')
  or (select count(*) from public.rm_projetos where equipamento_id='c2370000-0000-4000-8000-000000000004')<>1 then raise exception 'FAIL: concurrent inverse reference bypassed route binding % / %',r1,r2;end if;
 -- A raw/ETL project writer may already hold the parent row before its UPDATE
 -- trigger executes. It must not deadlock against the typed equipment lock.
 perform set_config('request.jwt.claim.sub','12370000-0000-4000-8000-000000000001',true);
 s:=public.rm_web_project_equipment_snapshot_v1('b2370000-0000-4000-8000-000000000006');
 p:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','changes','{}'::jsonb,'equipment',jsonb_build_object('id',s->'equipment'->>'id','tipo_equipamento_id','52370000-0000-4000-8000-000000000001','expected_updated_at',s->'equipment'->>'updated_at','expected_context_version',s->>'context_version','changes','{}'::jsonb));
 perform dblink_send_query('route_a','select rm_test_route_concurrency.edit_project()');
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then raise exception 'FAIL: raw project edit did not hold';end if;perform pg_sleep(.01);end loop;
 perform dblink_send_query('route_b',format('select rm_test_route_concurrency.run(%L,%L::jsonb,0)','d2370000-0000-4000-8000-000000000006',p::text));
 n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>200 then raise exception 'FAIL: typed edit did not wait for parent';end if;perform pg_sleep(.005);end loop;
 select r into r1 from dblink_get_result('route_a') as t(r jsonb);perform r from dblink_get_result('route_a') as t(r jsonb);
 select r into r2 from dblink_get_result('route_b') as t(r jsonb);perform r from dblink_get_result('route_b') as t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'PT409'
  or (select nome from public.rm_projetos where id='b2370000-0000-4000-8000-000000000006')<>'External project winner'
  or exists(select 1 from rm_private.project_route_instances where projeto_id='b2370000-0000-4000-8000-000000000006') then raise exception 'FAIL: raw project edit race deadlocked or lost winner % / %',r1,r2;end if;
 perform dblink_disconnect('route_a');perform dblink_disconnect('route_b');
exception when others then
 if 'route_a'=any(dblink_get_connections()) then perform dblink_disconnect('route_a');end if;
 if 'route_b'=any(dblink_get_connections()) then perform dblink_disconnect('route_b');end if;
 raise;
end $$;
select 'PASS: 037 concurrent replay, competing initialization, template mutation, inverse insertion and raw parent edits preserve one independent route' as result;
