\set ON_ERROR_STOP on
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create extension if not exists dblink with schema public;
create schema rm_test_project_delete;
create function rm_test_project_delete.id(h text,n int) returns uuid language sql immutable as $$select(h||'c390000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
begin;
insert into auth.users(id) values(rm_test_project_delete.id('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values(rm_test_project_delete.id('2',1),rm_test_project_delete.id('1',1),'Delete race administrator','administrador','ativo');
insert into public.rm_projetos(id,bubble_id,nome) select rm_test_project_delete.id('5',n),'delete-race-bubble-'||n,'Project delete race '||n from generate_series(1,13)n;
insert into public.rm_celulas(id,nome) values(rm_test_project_delete.id('4',1),'Delete race cell');
insert into public.rm_forms(id,titulo) values(rm_test_project_delete.id('7',1),'Delete race form');
insert into public.rm_questoes(id,form_id,enunciado,tipo) values(rm_test_project_delete.id('a',1),rm_test_project_delete.id('7',1),'Race question','texto_curto');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id) select rm_test_project_delete.id('6',n),rm_test_project_delete.id('5',n),rm_test_project_delete.id('4',1) from generate_series(1,6)n;
insert into public.rm_fotos(id,projeto_id,celula_id,celula_projeto_id,titulo) select rm_test_project_delete.id('9',n),rm_test_project_delete.id('5',n),rm_test_project_delete.id('4',1),rm_test_project_delete.id('6',n),'Race photo' from generate_series(3,4)n;
insert into public.rm_registros_formulario(id,projeto_id,form_id,celula_id) select rm_test_project_delete.id('8',n),rm_test_project_delete.id('5',n),rm_test_project_delete.id('7',1),rm_test_project_delete.id('4',1) from generate_series(5,6)n;
insert into public.rm_docs(id,projeto_id,nome,arquivo_url) select rm_test_project_delete.id('b',n),rm_test_project_delete.id('5',n),'Owned source',case when n>=9 then 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/'||rm_test_project_delete.id('5',n)||'/'||rm_test_project_delete.id('b',n)||'.pdf' end from generate_series(7,10)n;
insert into rm_private.project_attachment_uploads(id,auth_user_id,actor_id,projeto_id,nome,filename,mime_type,byte_size,sha256,object_path,status_documento,finalized_doc_id,completed_at)
 select rm_test_project_delete.id('b',n),rm_test_project_delete.id('1',1),rm_test_project_delete.id('2',1),rm_test_project_delete.id('5',n),'Owned PDF','file.pdf','application/pdf',12,repeat('a',64),'web-dossier/'||rm_test_project_delete.id('5',n)||'/'||rm_test_project_delete.id('b',n)||'.pdf','No prazo',rm_test_project_delete.id('b',n),clock_timestamp() from generate_series(9,10)n;
update rm_private.sso_settings set require_sso=false;
create function rm_test_project_delete.actor() returns void language plpgsql as $$begin perform set_config('request.jwt.claim.sub',rm_test_project_delete.id('1',1)::text,true);perform set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);end$$;
create function rm_test_project_delete.payload(n int) returns jsonb language sql as $$with s as(select public.rm_web_project_delete_snapshot_v1(rm_test_project_delete.id('5',n))v)select jsonb_build_object('id',v->'project'->>'id','expected_updated_at',v->'project'->>'updated_at','expected_context_version',v->>'context_version','confirm_delete',true,'justificativa','Explicit race check') from s$$;
create function rm_test_project_delete.run(rid uuid,p jsonb,hold_seconds numeric) returns jsonb language plpgsql as $$declare r jsonb;state text;begin
 perform rm_test_project_delete.actor();set local role authenticated;r:=public.rm_web_mutate_v1(rid,'delete_project',p);reset role;
 perform pg_sleep(hold_seconds);return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role;get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);end$$;
create function rm_test_project_delete.write(n int,kind text,hold_seconds numeric) returns jsonb language plpgsql as $$declare state text;begin
 perform rm_test_project_delete.actor();
 if kind='project' then update public.rm_projetos set nome='Concurrent edit won' where id=rm_test_project_delete.id('5',n);if not found then raise exception 'Deleted project' using errcode='PT410';end if;
 elsif kind='photo' then update public.rm_fotos set foto_url='https://invalid.example/race.jpg' where id=rm_test_project_delete.id('9',n);if not found then raise exception 'Deleted photo' using errcode='PT410';end if;
 elsif kind='answer' then insert into public.rm_respostas(id,registro_formulario_id,questao_id,resposta) values(rm_test_project_delete.id('d',n),rm_test_project_delete.id('8',n),rm_test_project_delete.id('a',1),'Concurrent answer won');
 elsif kind='origin' then insert into public.rm_documentos(id,projeto_id,documentos_origem_ids,nome) values(rm_test_project_delete.id('d',n),rm_test_project_delete.id('5',13),array[rm_test_project_delete.id('b',n)],'Shared document source');
 elsif kind='file' then insert into public.rm_docs(id,projeto_id,nome,arquivo_url) values(rm_test_project_delete.id('d',n),rm_test_project_delete.id('5',13),'New shared reference','https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/'||rm_test_project_delete.id('5',n)||'/'||rm_test_project_delete.id('b',n)||'.pdf');
 elsif kind='bubble' then insert into public.rm_projetos(id,bubble_id,nome) values(rm_test_project_delete.id('f',n),'delete-race-bubble-'||n,'Reimport must fail');
 end if;
 perform pg_sleep(hold_seconds);return '{"sqlstate":"00000"}'::jsonb;
exception when others then get stacked diagnostics state=returned_sqlstate;return jsonb_build_object('sqlstate',state,'message',sqlerrm);end$$;
create function rm_test_project_delete.wait_for_sleep(pid int) returns void language plpgsql as $$begin
 for n in 1..500 loop perform pg_stat_clear_snapshot();if exists(select 1 from pg_stat_activity where pg_stat_activity.pid=$1 and wait_event='PgSleep') then return;end if;perform pg_sleep(.01);end loop;raise exception 'Fixture did not acquire its locks';end$$;
commit;
do $$declare p jsonb;r1 jsonb;r2 jsonb;pid_a int;n int;kind text;first_write boolean;begin
 perform rm_test_project_delete.actor();
 perform dblink_connect('pd_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('pd_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('pd_a','select pg_backend_pid()')t(pid int);
 for n in 1..10 loop
  kind:=case when n<=2 then 'project' when n<=4 then 'photo' when n<=6 then 'answer' when n<=8 then 'origin' else 'file' end;
  first_write:=n%2=1;p:=rm_test_project_delete.payload(n);
  if first_write then
   perform dblink_send_query('pd_a',format('select rm_test_project_delete.write(%s,%L,1.1)',n,kind));perform rm_test_project_delete.wait_for_sleep(pid_a);
   perform dblink_send_query('pd_b',format('select rm_test_project_delete.run(%L::uuid,%L::jsonb,0)',rm_test_project_delete.id('e',n),p));
  else
   perform dblink_send_query('pd_a',format('select rm_test_project_delete.run(%L::uuid,%L::jsonb,1.1)',rm_test_project_delete.id('e',n),p));perform rm_test_project_delete.wait_for_sleep(pid_a);
   perform dblink_send_query('pd_b',format('select rm_test_project_delete.write(%s,%L,0)',n,kind));
  end if;
  select r into r1 from dblink_get_result('pd_a')t(r jsonb);perform r from dblink_get_result('pd_a')t(r jsonb);
  select r into r2 from dblink_get_result('pd_b')t(r jsonb);perform r from dblink_get_result('pd_b')t(r jsonb);
  if r1->>'sqlstate'<>'00000' or(first_write and r2->>'sqlstate'<>'PT409') or(not first_write and r2->>'sqlstate' not in('PT410','PT409','23503')) then raise exception 'FAIL: deletion race % (%), winner % / loser %',n,kind,r1,r2;end if;
  if first_write then
   if not exists(select 1 from public.rm_projetos where id=rm_test_project_delete.id('5',n)) or exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=rm_test_project_delete.id('e',n)) then raise exception 'FAIL: winning write lost its project or rejected deletion left receipt';end if;
  elsif exists(select 1 from public.rm_projetos where id=rm_test_project_delete.id('5',n)) or exists(select 1 from public.rm_documentos where id=rm_test_project_delete.id('d',n)) or exists(select 1 from public.rm_docs where id=rm_test_project_delete.id('d',n)) then raise exception 'FAIL: loser recreated or cross-referenced deleted data';end if;
 end loop;
 -- Same UUID/content concurrently reserves exactly one deletion and replays it.
 p:=rm_test_project_delete.payload(11);
 perform dblink_send_query('pd_a',format('select rm_test_project_delete.run(%L::uuid,%L::jsonb,1.1)',rm_test_project_delete.id('e',11),p));perform rm_test_project_delete.wait_for_sleep(pid_a);
 perform dblink_send_query('pd_b',format('select rm_test_project_delete.run(%L::uuid,%L::jsonb,0)',rm_test_project_delete.id('e',11),p));
 select r into r1 from dblink_get_result('pd_a')t(r jsonb);perform r from dblink_get_result('pd_a')t(r jsonb);select r into r2 from dblink_get_result('pd_b')t(r jsonb);perform r from dblink_get_result('pd_b')t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'00000' or not(r2->'result'->>'idempotent_replay')::boolean or(select count(*) from rm_private.web_mutation_receipts where client_submission_id=rm_test_project_delete.id('e',11))<>1 then raise exception 'FAIL: duplicate deletion protocol race % / %',r1,r2;end if;
 -- A different UUID cannot resurrect the same Bubble project identity.
 p:=rm_test_project_delete.payload(12);
 perform dblink_send_query('pd_a',format('select rm_test_project_delete.run(%L::uuid,%L::jsonb,1.1)',rm_test_project_delete.id('e',12),p));perform rm_test_project_delete.wait_for_sleep(pid_a);
 perform dblink_send_query('pd_b','select rm_test_project_delete.write(12,''bubble'',0)');
 select r into r1 from dblink_get_result('pd_a')t(r jsonb);perform r from dblink_get_result('pd_a')t(r jsonb);select r into r2 from dblink_get_result('pd_b')t(r jsonb);perform r from dblink_get_result('pd_b')t(r jsonb);
 if r1->>'sqlstate'<>'00000' or r2->>'sqlstate'<>'PT410' or exists(select 1 from public.rm_projetos where id=rm_test_project_delete.id('f',12)) then raise exception 'FAIL: Bubble tombstone race % / %',r1,r2;end if;
 perform dblink_disconnect('pd_a');perform dblink_disconnect('pd_b');
exception when others then if 'pd_a'=any(dblink_get_connections()) then perform dblink_disconnect('pd_a');end if;if 'pd_b'=any(dblink_get_connections()) then perform dblink_disconnect('pd_b');end if;raise;end$$;
select 'PASS: 039 twelve real races protect edits/photos/answers/document origins/private paths in both orders, one UUID and Bubble reimport' result;
