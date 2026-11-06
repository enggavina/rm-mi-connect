\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_route_config;
create function rm_test_route_config.id(h text,n int) returns uuid language sql immutable as $$select(h||'d410000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
begin;
insert into auth.users(id) values(rm_test_route_config.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_route_config.id('2',1),rm_test_route_config.id('1',1),'Route config race planner','administrador','ativo');
insert into public.rm_forms(id,titulo) values(rm_test_route_config.id('7',1),'Route race form');
insert into public.rm_questoes(id,form_id,enunciado,tipo) values(rm_test_route_config.id('a',1),rm_test_route_config.id('7',1),'Route race question','texto_curto');
insert into public.rm_projetos(id,nome) select rm_test_route_config.id('5',n),'Route config race '||n from generate_series(1,7)n;
insert into public.rm_celulas(id,nome) select rm_test_route_config.id('4',n),'Route race cell '||n from generate_series(1,107)n where n<=7 or n>=101;
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids,indice,visibilidade)
 select rm_test_route_config.id('6',n),rm_test_route_config.id('5',case when n>100 then n-100 else n end),rm_test_route_config.id('4',n),case when n>100 then '{}'::uuid[] else array[rm_test_route_config.id('7',1)] end,case when n>100 then 2 else 1 end,true from generate_series(1,107)n where n<=7 or n>=101;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,titulo,categoria_foto)
 select rm_test_route_config.id('9',n),rm_test_route_config.id('5',n),rm_test_route_config.id('4',n),rm_test_route_config.id('6',n),'Route race photo','obrigat_ria' from generate_series(1,7)n;
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status,status_cel_proj)
 select rm_test_route_config.id('c',n),rm_test_route_config.id('5',n),rm_test_route_config.id('6',n),rm_test_route_config.id('4',n),rm_test_route_config.id('4',n+100),'nulo','em_dia' from generate_series(1,7)n;
update rm_private.sso_settings set require_sso=false;
create function rm_test_route_config.actor() returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',rm_test_route_config.id('1',1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);end$$;
create function rm_test_route_config.payload(n int,action text) returns jsonb language sql as $$
 with s as(select public.rm_web_project_route_cell_snapshot_v1(rm_test_route_config.id('5',n),rm_test_route_config.id('6',n),true)v)
 select jsonb_build_object('action',action,'projeto_id',v->'project'->>'id','celula_projeto_id',v->'allocation'->>'id','expected_project_updated_at',v->'project'->>'updated_at','expected_allocation_updated_at',v->'allocation'->>'updated_at','expected_context_version',v->>'context_version','confirm_change',true)||case when action='forms' then '{"forms_ids":[]}'::jsonb else '{}'::jsonb end from s;
$$;
create function rm_test_route_config.run(rid uuid,p jsonb,hold_seconds numeric) returns jsonb language plpgsql as $$declare r jsonb;state text;begin
 perform rm_test_route_config.actor();set local role authenticated;
 r:=public.rm_web_mutate_v1(rid,'manage_project_route_cell',p);reset role;
 perform pg_sleep(hold_seconds);return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);end$$;
create function rm_test_route_config.write(n int,kind text,hold_seconds numeric) returns jsonb language plpgsql as $$declare state text;begin
 perform rm_test_route_config.actor();
 if kind='draft' then
  insert into public.rm_respostas_temp(projeto_id,form_id,questao_id,operador_user_id,resposta) values(rm_test_route_config.id('5',n),rm_test_route_config.id('7',1),rm_test_route_config.id('a',1),rm_test_route_config.id('2',1),'Concurrent server draft');
 elsif kind='photo' then update public.rm_fotos set foto_url='https://invalid.example/concurrent-photo.jpg' where id=rm_test_route_config.id('9',n);
 elsif kind='record' then insert into public.rm_registros_formulario(projeto_id,celula_id,form_id,preenchido,status) values(rm_test_route_config.id('5',n),rm_test_route_config.id('4',n),rm_test_route_config.id('7',1),false,'em_an_lise');
 end if;
 perform pg_sleep(hold_seconds);return '{"sqlstate":"00000"}'::jsonb;
exception when others then get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);end$$;
create function rm_test_route_config.wait_for_sleep(pid int) returns void language plpgsql as $$begin
 for n in 1..500 loop
  perform pg_stat_clear_snapshot();if exists(select 1 from pg_stat_activity where pg_stat_activity.pid=$1 and wait_event='PgSleep') then return;end if;perform pg_sleep(.01);
 end loop;raise exception 'Fixture did not acquire its locks';end$$;
commit;
do $$declare p jsonb;r1 jsonb;r2 jsonb;pid_a int;n int;action text;kind text;first_write boolean;begin
 perform rm_test_route_config.actor();
 perform dblink_connect('rc_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('rc_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('rc_a','select pg_backend_pid()') t(pid int);
 for n in 1..6 loop
  action:=case when n in(3,4) then 'remove' else 'forms' end;
  kind:=case when n in(1,2) then 'draft' when n in(3,4) then 'photo' else 'record' end;
  first_write:=n in(1,3,5);p:=rm_test_route_config.payload(n,action);
  if first_write then
   perform dblink_send_query('rc_a',format('select rm_test_route_config.write(%s,%L,1.2)',n,kind));
   perform rm_test_route_config.wait_for_sleep(pid_a);
   perform dblink_send_query('rc_b',format('select rm_test_route_config.run(%L::uuid,%L::jsonb,0)',rm_test_route_config.id('e',n),p));
  else
   perform dblink_send_query('rc_a',format('select rm_test_route_config.run(%L::uuid,%L::jsonb,1.2)',rm_test_route_config.id('e',n),p));
   perform rm_test_route_config.wait_for_sleep(pid_a);
   perform dblink_send_query('rc_b',format('select rm_test_route_config.write(%s,%L,0)',n,kind));
  end if;
  select r into r1 from dblink_get_result('rc_a')t(r jsonb);perform r from dblink_get_result('rc_a')t(r jsonb);
  select r into r2 from dblink_get_result('rc_b')t(r jsonb);perform r from dblink_get_result('rc_b')t(r jsonb);
  if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'PT409' then raise exception 'FAIL: race % winner/loser wrong: % / %',n,r1,r2;end if;
  if first_write then
   if not(select not retirada and forms_ids=array[rm_test_route_config.id('7',1)] from public.rm_celulas_projeto where id=rm_test_route_config.id('6',n)) then raise exception 'FAIL: operational winner lost configuration';end if;
   if exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=rm_test_route_config.id('e',n)) then raise exception 'FAIL: rejected config command left receipt';end if;
  else
   if kind='draft' and exists(select 1 from public.rm_respostas_temp where projeto_id=rm_test_route_config.id('5',n))
    or kind='record' and exists(select 1 from public.rm_registros_formulario where projeto_id=rm_test_route_config.id('5',n))
    or kind='photo' and exists(select 1 from public.rm_fotos where id=rm_test_route_config.id('9',n) and foto_url is not null) then raise exception 'FAIL: losing operational write persisted partial data';end if;
  end if;
 end loop;
 -- Identical concurrent removal consumes exactly one protocol and one lifecycle event.
 p:=rm_test_route_config.payload(7,'remove');
 perform dblink_send_query('rc_a',format('select rm_test_route_config.run(%L::uuid,%L::jsonb,1.2)',rm_test_route_config.id('e',7),p));
 perform rm_test_route_config.wait_for_sleep(pid_a);
 perform dblink_send_query('rc_b',format('select rm_test_route_config.run(%L::uuid,%L::jsonb,0)',rm_test_route_config.id('e',7),p));
 select r into r1 from dblink_get_result('rc_a')t(r jsonb);perform r from dblink_get_result('rc_a')t(r jsonb);
 select r into r2 from dblink_get_result('rc_b')t(r jsonb);perform r from dblink_get_result('rc_b')t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'00000' or not(r2->'result'->>'idempotent_replay')::boolean
  or(select count(*) from rm_private.cell_availability_events where client_submission_id=rm_test_route_config.id('e',7))<>1 then raise exception 'FAIL: same-protocol removal race duplicated work % / %',r1,r2;end if;
 perform dblink_disconnect('rc_a');perform dblink_disconnect('rc_b');
exception when others then
 if 'rc_a'=any(dblink_get_connections()) then perform dblink_disconnect('rc_a');end if;
 if 'rc_b'=any(dblink_get_connections()) then perform dblink_disconnect('rc_b');end if;
 raise;
end$$;
select 'PASS: 040 seven real races preserve draft/record/photo winners, reject conflicting removal/unlinks and replay one protocol' result;
