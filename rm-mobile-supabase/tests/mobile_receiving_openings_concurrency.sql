\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_receiving;
create function rm_test_receiving.id(h text,n int) returns uuid language sql immutable as $$select(h||'cf05200-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function rm_test_receiving.params(n int) returns jsonb language sql as $$select jsonb_build_object('p_cliente_id',rm_test_receiving.id('4',1),'p_fotos_recebimento',jsonb_build_array(jsonb_build_object('foto_url','https://fixture.invalid/race'||n||'.jpg','titulo','Frontal','tipo_recebimento','frente')),
 'p_receiving_draft_id',rm_test_receiving.id('7',n),'p_receiving_draft_revision',0,'p_receiving_draft_snapshot',jsonb_build_object('id',rm_test_receiving.id('7',n),'version',2,'submitted',false));$$;
begin;
insert into auth.users(id) values(rm_test_receiving.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_receiving.id('2',1),rm_test_receiving.id('1',1),'Receiving race planner','administrador','ativo');
insert into public.rm_users(id,nome,perfil,status) values(rm_test_receiving.id('2',2),'Other receiving operator','mobile','ativo');
insert into public.rm_clientes(id,nome) values(rm_test_receiving.id('4',1),'Receiving race client');
insert into public.rm_projetos(id,numero) values(rm_test_receiving.id('5',1),'Receiving protocol reservation race');
insert into public.rm_celulas(id,nome) values(rm_test_receiving.id('6',1),'Receiving reservation cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade) values(rm_test_receiving.id('6',2),rm_test_receiving.id('5',1),rm_test_receiving.id('6',1),'pendente',true);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 select extensions.digest('receiving-race-'||n,'sha256'),rm_test_receiving.id('1',1),rm_test_receiving.id('2',1),rm_test_receiving.id('2',n),clock_timestamp()+interval '1 day' from generate_series(1,2)n;
update rm_private.sso_settings set require_sso=false;
create function rm_test_receiving.run(operation text,rid uuid,payload jsonb,op int,hold real) returns jsonb language plpgsql as $$declare result jsonb;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_receiving.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 set local role authenticated;
 if operation='open' then result:=public.rm_mobile_open_receiving_v1(rid,payload,'receiving-race-'||op);
 elsif operation='final' then result:=public.rm_mobile_mutate_v1(rid,'rm_submit_recebimento_v1',payload,'receiving-race-'||op);
 elsif operation='status' then result:=public.rm_mobile_mutate_v1(rid,'rm_update_cell_status_v1',payload,'receiving-race-'||op);
 elsif operation='exec' then result:=public.rm_mobile_mutate_v1(rid,'rm_record_execution_event_v1',payload,'receiving-race-'||op);
 else result:=public.rm_web_mutate_v1(rid,operation,payload);end if;
 reset role;perform pg_sleep(hold);return jsonb_build_object('sqlstate','00000','result',result);
 exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end$$;
select rm_test_receiving.run('open',rm_test_receiving.id('7',4),rm_test_receiving.params(4),1,0);
select rm_test_receiving.run('open',rm_test_receiving.id('7',5),rm_test_receiving.params(5),1,0);
commit;
do $$declare scenario int;attempt int;pid_a int;first_result jsonb;second_result jsonb;first_payload jsonb;second_payload jsonb;first_operation text;second_operation text;first_id uuid;second_id uuid;second_op int;context jsonb;pid uuid;begin
 perform set_config('request.jwt.claim.sub',rm_test_receiving.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 perform dblink_connect('receiving_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('receiving_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select backend into pid_a from dblink('receiving_a','select pg_backend_pid()') as t(backend int);
 for scenario in 1..11 loop
  first_operation:='open';second_operation:='open';second_op:=1;first_id:=rm_test_receiving.id('7',scenario);second_id:=first_id;
  first_payload:=rm_test_receiving.params(scenario);second_payload:=first_payload;
  if scenario in(4,5) then
   select project_id into pid from rm_private.receiving_openings where client_submission_id=first_id;
   context:=public.rm_web_project_delete_snapshot_v1(pid);
  end if;
  case scenario
   when 1 then null;
   when 2 then second_operation:='final';
   when 3 then first_operation:='final';
   when 4 then first_operation:='final';second_operation:='delete_project';second_id:=rm_test_receiving.id('8',scenario);
    second_payload:=jsonb_build_object('id',pid,'expected_updated_at',context->'project'->>'updated_at','expected_context_version',context->>'context_version','confirm_delete',true,'justificativa','Receiving stale deletion race');
   when 5 then first_operation:='delete_project';first_id:=rm_test_receiving.id('8',scenario);second_operation:='final';
    first_payload:=jsonb_build_object('id',pid,'expected_updated_at',context->'project'->>'updated_at','expected_context_version',context->>'context_version','confirm_delete',true,'justificativa','Receiving pending deletion race');
   when 6 then second_op:=2;
   when 7 then second_id:=rm_test_receiving.id('7',107);second_payload:=rm_test_receiving.params(107);
   when 8 then second_operation:='status';second_payload:=jsonb_build_object('p_celula_projeto_id',rm_test_receiving.id('6',2),'p_status','em_dia');
   when 9 then first_operation:='status';first_payload:=jsonb_build_object('p_celula_projeto_id',rm_test_receiving.id('6',2),'p_status','em_dia');
   when 10 then second_operation:='exec';second_payload:=jsonb_build_object('p_session_id',rm_test_receiving.id('9',scenario),'p_allocation_id',rm_test_receiving.id('6',2),'p_previous_event_id',null,'p_kind','start','p_occurred_at',clock_timestamp(),'p_pause_reason',null,'p_note',null,'p_effort_minutes',null,'p_operador_id',rm_test_receiving.id('2',1));
   when 11 then first_operation:='exec';first_payload:=jsonb_build_object('p_session_id',rm_test_receiving.id('9',scenario),'p_allocation_id',rm_test_receiving.id('6',2),'p_previous_event_id',null,'p_kind','start','p_occurred_at',clock_timestamp(),'p_pause_reason',null,'p_note',null,'p_effort_minutes',null,'p_operador_id',rm_test_receiving.id('2',1));
  end case;
  perform dblink_send_query('receiving_a',format('select rm_test_receiving.run(%L,%L::uuid,%L::jsonb,1,0.4)',first_operation,first_id,first_payload));
  for attempt in 1..200 loop
   exit when exists(select 1 from pg_stat_activity a where a.pid=pid_a and a.wait_event='PgSleep');perform pg_sleep(0.01);
  end loop;
  if attempt=200 then raise exception 'FAIL: first receiving race did not reach hold';end if;
  perform dblink_send_query('receiving_b',format('select rm_test_receiving.run(%L,%L::uuid,%L::jsonb,%s,0)',second_operation,second_id,second_payload,second_op));
  select result into first_result from dblink_get_result('receiving_a') as t(result jsonb);perform * from dblink_get_result('receiving_a') as t(result jsonb);
  select result into second_result from dblink_get_result('receiving_b') as t(result jsonb);perform * from dblink_get_result('receiving_b') as t(result jsonb);
  if first_result->>'sqlstate'<>'00000' then raise exception 'FAIL: receiving race % first %',scenario,first_result;end if;
  if scenario=4 then if second_result->>'sqlstate'<>'PT409' then raise exception 'FAIL: receiving stale delete %',second_result;end if;
  elsif scenario=5 then if second_result->>'sqlstate'<>'PT410' then raise exception 'FAIL: pending deleted receiving recreated %',second_result;end if;
  elsif scenario in(6,8,9,10,11) then if second_result->>'sqlstate'<>'22023' then raise exception 'FAIL: reserved protocol race %: %',scenario,second_result;end if;
  else
   if second_result->>'sqlstate'<>'00000' then raise exception 'FAIL: receiving race % second %',scenario,second_result;end if;
   if scenario in(1,2,3) and first_result->'result'->>'projeto_id'<>second_result->'result'->>'projeto_id' then raise exception 'FAIL: receiving race duplicated project';end if;
   if scenario=1 and second_result->'result'->>'idempotent_replay'<>'true' then raise exception 'FAIL: opening retry not recognized';end if;
   if scenario=3 and second_result->'result'->>'attachments_pending'<>'false' then raise exception 'FAIL: legacy final not recognized';end if;
  end if;
 end loop;
 if not exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=rm_test_receiving.id('7',9) and rpc_name='rm_update_cell_status_v1')
  or not exists(select 1 from rm_private.execution_events where id=rm_test_receiving.id('7',11) and disposition='accepted')
  or exists(select 1 from rm_private.receiving_openings where client_submission_id in(rm_test_receiving.id('7',9),rm_test_receiving.id('7',11))) then raise exception 'FAIL: winning prior evidence changed by opening collision';end if;
 perform dblink_disconnect('receiving_a');perform dblink_disconnect('receiving_b');
 exception when others then if 'receiving_a'=any(dblink_get_connections()) then perform dblink_disconnect('receiving_a');end if;if 'receiving_b'=any(dblink_get_connections()) then perform dblink_disconnect('receiving_b');end if;raise;
end$$;
select 'PASS: eleven receiving races preserve one project, opening/finalization ordering, UUID reservations, original actor, deletion and independent submissions' result;
