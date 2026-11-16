\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_form_delete;
create function rm_test_form_delete.id(n int) returns uuid language sql immutable as $$ select ('c4600000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
begin;
insert into auth.users(id) values(rm_test_form_delete.id(1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_form_delete.id(2),rm_test_form_delete.id(1),'Delete form race admin','administrador','ativo');
insert into public.rm_forms(id,titulo,bubble_id) select rm_test_form_delete.id(n),'Form deletion race '||n,'form-delete-race-'||n from generate_series(10,20)n;
insert into public.rm_projetos(id,nome) values(rm_test_form_delete.id(30),'Form delete race project');
insert into public.rm_celulas(id,nome) select rm_test_form_delete.id(n),'Form delete race cell '||n from generate_series(41,48)n;
insert into public.rm_questoes(id,form_id,enunciado,tipo) select rm_test_form_delete.id(n+100),rm_test_form_delete.id(n),'Race question '||n,'escolha__nica' from generate_series(12,13)n;
insert into public.rm_itens_questoes(id,form_id,questao_id,descricao) select rm_test_form_delete.id(n+200),rm_test_form_delete.id(n),rm_test_form_delete.id(n+100),'Race item '||n from generate_series(12,13)n;
insert into public.rm_questoes(id,form_id,enunciado,tipo) values(rm_test_form_delete.id(120),rm_test_form_delete.id(20),'Independent carrier question','escolha__nica');
insert into public.rm_registros_formulario(id,projeto_id,form_id,codigo) select rm_test_form_delete.id(n+300),rm_test_form_delete.id(30),rm_test_form_delete.id(20),n from generate_series(12,13)n;
update rm_private.sso_settings set require_sso=false;
create function rm_test_form_delete.run(mode text,rid uuid,p jsonb,hold real) returns jsonb language plpgsql as $$
declare result jsonb;state text;begin
 perform set_config('request.jwt.claim.sub',rm_test_form_delete.id(1)::text,true);perform set_config('request.jwt.claims','{"aal":"aal1"}',true);
 if mode='delete' then
  set local role authenticated;result:=public.rm_web_mutate_v1(rid,'delete_form_template',p);reset role;
 elsif mode='insert_identity' then
  insert into public.rm_forms(id,titulo,bubble_id) values((p->>'id')::uuid,'Attempted identity reuse',p->>'bubble_id');
 elsif mode='update_identity' then
  update public.rm_forms set bubble_id=p->>'bubble_id' where id=rm_test_form_delete.id(20);
 elsif mode='allocation' then
  insert into public.rm_celulas_projeto(projeto_id,celula_id,forms_ids) values(rm_test_form_delete.id(30),(p->>'celula_id')::uuid,array[(p->>'form_id')::uuid]);
 elsif mode='answer' then
  insert into public.rm_respostas(registro_formulario_id,questao_id,itens_questoes_ids) values((p->>'record_id')::uuid,rm_test_form_delete.id(120),array[(p->>'item_id')::uuid]);
 else raise exception 'Unknown test mode';end if;
 perform pg_sleep(hold);return jsonb_build_object('sqlstate','00000','result',result);
 exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end $$;
commit;
do $$
declare scenario int;n int;pid_a int;pid_b int;fid int;first_mode text;second_mode text;first_payload jsonb;second_payload jsonb;deletion jsonb;
 first_id uuid;second_id uuid;a jsonb;b jsonb;wanted text;
begin
 perform dblink_connect('form_delete_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('form_delete_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('form_delete_a','select pg_backend_pid()') as t(pid int);select pid into pid_b from dblink('form_delete_b','select pg_backend_pid()') as t(pid int);
 for scenario in 1..8 loop
  fid:=scenario+9;
  deletion:=jsonb_build_object('id',rm_test_form_delete.id(fid),'kind','form','confirmed',true,'expected_updated_at',(select updated_at from public.rm_forms where id=rm_test_form_delete.id(fid)));
  first_id:=gen_random_uuid();second_id:=gen_random_uuid();first_mode:='delete';first_payload:=deletion;second_mode:='delete';second_payload:=deletion;wanted:='23503';
  if scenario=1 then second_mode:='insert_identity';second_payload:=jsonb_build_object('id',rm_test_form_delete.id(1010),'bubble_id','form-delete-race-10');wanted:='PT410';
  elsif scenario=2 then first_mode:='allocation';first_payload:=jsonb_build_object('celula_id',rm_test_form_delete.id(42),'form_id',rm_test_form_delete.id(fid));
  elsif scenario=3 then first_mode:='answer';first_payload:=jsonb_build_object('record_id',rm_test_form_delete.id(312),'item_id',rm_test_form_delete.id(212));
  elsif scenario=4 then second_mode:='answer';second_payload:=jsonb_build_object('record_id',rm_test_form_delete.id(313),'item_id',rm_test_form_delete.id(213));
  elsif scenario=5 then second_id:=first_id;wanted:='00000';
  elsif scenario=6 then second_mode:='update_identity';second_payload:=jsonb_build_object('bubble_id','form-delete-race-15');wanted:='PT409';
  elsif scenario=7 then second_mode:='insert_identity';second_payload:=jsonb_build_object('id',rm_test_form_delete.id(fid),'bubble_id','different-bubble-identity');wanted:='PT410';
  elsif scenario=8 then second_mode:='allocation';second_payload:=jsonb_build_object('celula_id',rm_test_form_delete.id(48),'form_id',rm_test_form_delete.id(fid));end if;
  perform dblink_send_query('form_delete_a',format('select rm_test_form_delete.run(%L,%L,%L::jsonb,1)',first_mode,first_id,first_payload::text));
  n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');n:=n+1;if n>500 then select r into a from dblink_get_result('form_delete_a') as t(r jsonb);raise exception 'FAIL: writer % did not hold: %',scenario,a;end if;perform pg_sleep(.01);end loop;
  perform dblink_send_query('form_delete_b',format('select rm_test_form_delete.run(%L,%L,%L::jsonb,0)',second_mode,second_id,second_payload::text));
  if scenario<>6 then
   n:=0;loop perform pg_stat_clear_snapshot();exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');n:=n+1;if n>300 then raise exception 'FAIL: second writer % did not contend',scenario;end if;perform pg_sleep(.002);end loop;
  end if;
  select r into a from dblink_get_result('form_delete_a') as t(r jsonb);perform r from dblink_get_result('form_delete_a') as t(r jsonb);
  select r into b from dblink_get_result('form_delete_b') as t(r jsonb);perform r from dblink_get_result('form_delete_b') as t(r jsonb);
  if a->>'sqlstate'<>'00000' or b->>'sqlstate'<>wanted then raise exception 'FAIL: form deletion race %: % / %; expected %',scenario,a,b,wanted;end if;
  if scenario in(2,3) and not exists(select 1 from public.rm_forms where id=rm_test_form_delete.id(fid)) then raise exception 'FAIL: referenced form lost';end if;
  if scenario not in(2,3) and exists(select 1 from public.rm_forms where id=rm_test_form_delete.id(fid)) then raise exception 'FAIL: deleted identity resurrected';end if;
  if scenario=3 and not exists(select 1 from public.rm_respostas where registro_formulario_id=rm_test_form_delete.id(312) and itens_questoes_ids=array[rm_test_form_delete.id(212)]) then raise exception 'FAIL: historical item reference lost';end if;
  if scenario=4 and exists(select 1 from public.rm_respostas where registro_formulario_id=rm_test_form_delete.id(313)) then raise exception 'FAIL: deleted item acquired a reference';end if;
  if scenario=5 and(not(b->'result'->>'idempotent_replay')::boolean or(select count(*) from rm_private.web_mutation_receipts where client_submission_id=first_id)<>1) then raise exception 'FAIL: duplicate deletion receipt';end if;
  if scenario=6 then
   select r into b from dblink('form_delete_b',format('select rm_test_form_delete.run(%L,%L,%L::jsonb,0)',second_mode,gen_random_uuid(),second_payload::text)) as t(r jsonb);
   if b->>'sqlstate'<>'PT410' then raise exception 'FAIL: committed Bubble tombstone update accepted: %',b;end if;
  end if;
 end loop;
 perform dblink_disconnect('form_delete_a');perform dblink_disconnect('form_delete_b');
 exception when others then if 'form_delete_a'=any(dblink_get_connections()) then perform dblink_disconnect('form_delete_a');end if;if 'form_delete_b'=any(dblink_get_connections()) then perform dblink_disconnect('form_delete_b');end if;raise;
end $$;
select 'PASS: eight real template deletion races protect identity tombstones, legacy arrays, historical items and exact idempotent retry' result;
