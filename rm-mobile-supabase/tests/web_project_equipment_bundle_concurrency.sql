\set ON_ERROR_STOP on
-- This test commits synthetic fixtures solely into the disposable local DB so
-- two independent PostgreSQL connections can genuinely contend.
do $$ begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required'; end if; end $$;
create extension if not exists dblink with schema public;
create schema rm_test_bundle_concurrency;
begin;
insert into auth.users(id) values('1ed36000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2ed36000-0000-4000-8000-000000000001','1ed36000-0000-4000-8000-000000000001','Bundle race actor','administrador','ativo');
insert into auth.sessions(id,user_id) values('3ed36000-0000-4000-8000-000000000001','1ed36000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('8ed36000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9ed36000-0000-4000-8000-000000000001',
 '2ed36000-0000-4000-8000-000000000001','1ed36000-0000-4000-8000-000000000001',true,'2ed36000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('d6',32),'8ed36000-0000-4000-8000-000000000001','3ed36000-0000-4000-8000-000000000001','opaque-bundle-race-fixture',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,nome) values('5ed36000-0000-4000-8000-000000000001','Existing project without equipment');
insert into public.rm_projetos(id,nome) values('5ed36000-0000-4000-8000-000000000002','Project with equipment for external race');
insert into public.rm_equipamentos(id,projeto_id,descricao) values('6ed36000-0000-4000-8000-000000000003','5ed36000-0000-4000-8000-000000000002','Before external edit');
update public.rm_projetos set equipamento_id='6ed36000-0000-4000-8000-000000000003' where id='5ed36000-0000-4000-8000-000000000002';
insert into public.rm_projetos(id,nome) values('5ed36000-0000-4000-8000-000000000003','Project with web edit first');
insert into public.rm_equipamentos(id,projeto_id,descricao) values('6ed36000-0000-4000-8000-000000000004','5ed36000-0000-4000-8000-000000000003','Before web edit');
update public.rm_projetos set equipamento_id='6ed36000-0000-4000-8000-000000000004' where id='5ed36000-0000-4000-8000-000000000003';
create function rm_test_bundle_concurrency.run(rid uuid,p jsonb,hold_seconds numeric) returns jsonb language plpgsql as $$
declare r jsonb; state text; begin
 perform set_config('request.jwt.claim.sub','1ed36000-0000-4000-8000-000000000001',true);
 perform set_config('request.jwt.claims','{"session_id":"3ed36000-0000-4000-8000-000000000001","aal":"aal1"}',true);
 perform public.rm_sso_action_permit_v1(repeat('d6',32),rid,'save_project_with_equipment',p,'em.projects.manage');
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'save_project_with_equipment',p); reset role;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state); end $$;
create function rm_test_bundle_concurrency.external_edit(target uuid,value text,hold_seconds numeric) returns jsonb language plpgsql as $$
declare state text; begin
 update public.rm_equipamentos set descricao=value where id=target;
 perform pg_sleep(hold_seconds); return jsonb_build_object('sqlstate','00000');
exception when others then get stacked diagnostics state=returned_sqlstate; return jsonb_build_object('sqlstate',state); end $$;
commit;
do $$ declare s jsonb; first_p jsonb; second_p jsonb; first_result jsonb; second_result jsonb; pid_a int; pid_b int; waited int; begin
 perform set_config('request.jwt.claim.sub','1ed36000-0000-4000-8000-000000000001',true);
 s:=public.rm_web_project_equipment_snapshot_v1('5ed36000-0000-4000-8000-000000000001');
 if s->>'binding_state'<>'missing' then raise exception 'FAIL: fixture must have no equipment'; end if;
 first_p:=jsonb_build_object('id','5ed36000-0000-4000-8000-000000000001','expected_updated_at',s->'project'->>'updated_at','changes','{}'::jsonb,
  'equipment',jsonb_build_object('id','6ed36000-0000-4000-8000-000000000001','expected_updated_at',null,'expected_context_version',s->>'context_version','changes',jsonb_build_object('fabricante','First')));
 second_p:=jsonb_set(first_p,'{equipment,id}','"6ed36000-0000-4000-8000-000000000002"'::jsonb);
 perform dblink_connect('bundle_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('bundle_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('bundle_a','select pg_backend_pid()') as t(pid int);
 select pid into pid_b from dblink('bundle_b','select pg_backend_pid()') as t(pid int);
 perform dblink_send_query('bundle_a',format('select rm_test_bundle_concurrency.run(%L,%L::jsonb,2)','aed36000-0000-4000-8000-000000000001',first_p::text));
 waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
  waited:=waited+1; if waited>500 then raise exception 'FAIL: first bundle operation did not hold'; end if; perform pg_sleep(0.01); end loop;
 perform dblink_send_query('bundle_b',format('select rm_test_bundle_concurrency.run(%L,%L::jsonb,0)','aed36000-0000-4000-8000-000000000002',second_p::text));
 waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
  waited:=waited+1; if waited>200 then raise exception 'FAIL: second bundle operation did not contend'; end if; perform pg_sleep(0.005); end loop;
 select r into first_result from dblink_get_result('bundle_a') as t(r jsonb); perform r from dblink_get_result('bundle_a') as t(r jsonb);
 select r into second_result from dblink_get_result('bundle_b') as t(r jsonb); perform r from dblink_get_result('bundle_b') as t(r jsonb);
 if first_result->>'sqlstate'<>'00000' or second_result->>'sqlstate'<>'PT409' then raise exception 'FAIL: race results: % / %',first_result,second_result; end if;
 if (select count(*) from public.rm_equipamentos where projeto_id='5ed36000-0000-4000-8000-000000000001')<>1
  or (select equipamento_id from public.rm_projetos where id='5ed36000-0000-4000-8000-000000000001')<>'6ed36000-0000-4000-8000-000000000001'::uuid
  or exists(select 1 from rm_private.web_mutation_receipts where client_submission_id='aed36000-0000-4000-8000-000000000002')
 then raise exception 'FAIL: race created duplicate equipment or consumed losing receipt'; end if;
 -- External/ETL writer locks only the equipment row. The bundle must wait,
 -- re-read its snapshot, and reject both project and equipment changes.
 s:=public.rm_web_project_equipment_snapshot_v1('5ed36000-0000-4000-8000-000000000002');
 if s->>'binding_state'<>'linked' then raise exception 'FAIL: external race fixture must be linked'; end if;
 second_p:=jsonb_build_object('id','5ed36000-0000-4000-8000-000000000002','expected_updated_at',s->'project'->>'updated_at',
  'changes',jsonb_build_object('nome','Must not commit'),
  'equipment',jsonb_build_object('id','6ed36000-0000-4000-8000-000000000003','expected_updated_at',s->'equipment'->>'updated_at',
   'expected_context_version',s->>'context_version','changes',jsonb_build_object('descricao','Must not overwrite')));
 perform dblink_send_query('bundle_a',$q$select rm_test_bundle_concurrency.external_edit('6ed36000-0000-4000-8000-000000000003','External committed edit',2)$q$);
 waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
  waited:=waited+1; if waited>500 then raise exception 'FAIL: external operation did not hold'; end if; perform pg_sleep(0.01); end loop;
 perform dblink_send_query('bundle_b',format('select rm_test_bundle_concurrency.run(%L,%L::jsonb,0)','aed36000-0000-4000-8000-000000000003',second_p::text));
 waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
  waited:=waited+1; if waited>200 then raise exception 'FAIL: bundle did not wait on equipment lock'; end if; perform pg_sleep(0.005); end loop;
 select r into first_result from dblink_get_result('bundle_a') as t(r jsonb); perform r from dblink_get_result('bundle_a') as t(r jsonb);
 select r into second_result from dblink_get_result('bundle_b') as t(r jsonb); perform r from dblink_get_result('bundle_b') as t(r jsonb);
 if first_result->>'sqlstate'<>'00000' or second_result->>'sqlstate'<>'PT409'
  or (select descricao from public.rm_equipamentos where id='6ed36000-0000-4000-8000-000000000003')<>'External committed edit'
  or (select nome from public.rm_projetos where id='5ed36000-0000-4000-8000-000000000002')<>'Project with equipment for external race'
  or exists(select 1 from rm_private.web_mutation_receipts where client_submission_id='aed36000-0000-4000-8000-000000000003')
 then raise exception 'FAIL: external edit race did not preserve winner or rollback bundle'; end if;
 -- Reverse race: bundle writes first and holds the equipment row; an external
 -- stale write waits, then must be rejected by the existing 031 journal guard.
 s:=public.rm_web_project_equipment_snapshot_v1('5ed36000-0000-4000-8000-000000000003');
 first_p:=jsonb_build_object('id','5ed36000-0000-4000-8000-000000000003','expected_updated_at',s->'project'->>'updated_at',
  'changes',jsonb_build_object('nome','Web committed'),
  'equipment',jsonb_build_object('id','6ed36000-0000-4000-8000-000000000004','expected_updated_at',s->'equipment'->>'updated_at',
   'expected_context_version',s->>'context_version','changes',jsonb_build_object('descricao','Web protected edit')));
 perform dblink_send_query('bundle_a',format('select rm_test_bundle_concurrency.run(%L,%L::jsonb,2)','aed36000-0000-4000-8000-000000000004',first_p::text));
 waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
  waited:=waited+1; if waited>500 then raise exception 'FAIL: bundle winner did not hold'; end if; perform pg_sleep(0.01); end loop;
 perform dblink_send_query('bundle_b',$q$select rm_test_bundle_concurrency.external_edit('6ed36000-0000-4000-8000-000000000004','Stale external edit',0)$q$);
 waited:=0; loop perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
  waited:=waited+1; if waited>200 then raise exception 'FAIL: external writer did not wait for bundle'; end if; perform pg_sleep(0.005); end loop;
 select r into first_result from dblink_get_result('bundle_a') as t(r jsonb); perform r from dblink_get_result('bundle_a') as t(r jsonb);
 select r into second_result from dblink_get_result('bundle_b') as t(r jsonb); perform r from dblink_get_result('bundle_b') as t(r jsonb);
 if first_result->>'sqlstate'<>'00000' or second_result->>'sqlstate'<>'PT409'
  or (select descricao from public.rm_equipamentos where id='6ed36000-0000-4000-8000-000000000004')<>'Web protected edit'
  or (select nome from public.rm_projetos where id='5ed36000-0000-4000-8000-000000000003')<>'Web committed'
  or not exists(select 1 from rm_private.equipment_change_events where equipamento_id='6ed36000-0000-4000-8000-000000000004' and 'descricao'=any(changed_fields))
 then raise exception 'FAIL: 031 journal did not protect committed bundle fields'; end if;
 perform dblink_disconnect('bundle_a'); perform dblink_disconnect('bundle_b');
exception when others then
 if 'bundle_a'=any(dblink_get_connections()) then perform dblink_disconnect('bundle_a'); end if;
 if 'bundle_b'=any(dblink_get_connections()) then perform dblink_disconnect('bundle_b'); end if;
 raise;
end $$;
