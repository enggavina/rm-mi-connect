\set ON_ERROR_STOP on
begin;
create function pg_temp.photo_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.photo_key(h text,n integer) returns uuid language sql immutable as $$
 select (h||'a100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.photo_actor(n integer,aal text default 'aal1') returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',pg_temp.photo_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.photo_key('3',n),'aal',aal)::text,true);
 perform set_config('rm.test.photo.actor',n::text,true);
end $$;
create function pg_temp.photo_payload(n integer default 1,selected boolean default true) returns jsonb language sql as $$
 select jsonb_build_object('projeto_id',pg_temp.photo_key('5',1),'foto_id',id,'expected_updated_at',updated_at,'selected',selected)
 from public.rm_fotos where id=pg_temp.photo_key('6',n);
$$;
create function pg_temp.photo_call(rid uuid,p jsonb,cap text default 'em.projects.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.photo.actor'),64,'a'),rid,'set_project_photo_selection',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'set_project_photo_selection',p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.photo_reject(p jsonb,wanted text,cap text default 'em.projects.manage') returns void language plpgsql as $$
declare actual text; begin
 begin perform pg_temp.photo_call(gen_random_uuid(),p,cap);
 exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
 end; raise exception 'FAIL: photo selection succeeded (expected %)',wanted;
end $$;
do $$ declare n int; begin
 for n in 1..6 loop
  insert into auth.users(id) values(pg_temp.photo_key('1',n));
  if n<>5 then insert into public.rm_users(id,auth_user_id,nome,perfil,status)
   values(pg_temp.photo_key('2',n),pg_temp.photo_key('1',n),'Photo selection fixture '||n,
    case when n in(1,6) then 'administrador'::public.rm_perfil_usuario_enum when n=3 then 'auditor' else 'padr_o' end,
    case when n=4 then 'inativo'::public.rm_status_user_enum else 'ativo' end); end if;
  insert into auth.sessions(id,user_id) values(pg_temp.photo_key('3',n),pg_temp.photo_key('1',n));
  if n not in(4,5) then
   insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.photo_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.photo_key('9',n),
    pg_temp.photo_key('2',n),pg_temp.photo_key('1',n),true,pg_temp.photo_key('2',1),clock_timestamp());
   perform public.rm_sso_session_put_v1(lpad(n::text,64,'a'),pg_temp.photo_key('8',n),pg_temp.photo_key('3',n),
    'opaque-local-photo-fixture-'||n,clock_timestamp()+interval '45 minutes');
  end if;
 end loop;
end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) values(pg_temp.photo_key('4',1),'Photo fixture cell');
insert into public.rm_projetos(id,numero,status_pcp,data_real_de_entrega) values
 (pg_temp.photo_key('5',1),'PHOTO-22-CLOSED','cancelado','2026-10-29T10:00:00Z'),
 (pg_temp.photo_key('5',2),'PHOTO-22-OTHER','finalizando_para_faturar',null);
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status)
 values(pg_temp.photo_key('7',1),pg_temp.photo_key('5',1),pg_temp.photo_key('4',1),'finalizado'),
 (pg_temp.photo_key('7',2),pg_temp.photo_key('5',2),pg_temp.photo_key('4',1),'finalizado');
insert into public.rm_fotos(id,bubble_id,projeto_id,celula_id,celula_projeto_id,categoria_foto,titulo,descricao,legenda,tag,
 foto_url,fotos_arquivos_urls,numero,numero_foto_complementar,lixeira,selecao_relatorio,created_by_user_id,sync_source)
 select pg_temp.photo_key('6',n),'photo-local-22-'||n,
  case when n=6 then null when n=3 then pg_temp.photo_key('5',2) else pg_temp.photo_key('5',1) end,
  pg_temp.photo_key('4',1),case when n=3 then pg_temp.photo_key('7',2) when n<>6 then pg_temp.photo_key('7',1) end,'obrigat_ria','Photo '||n,'Description','Caption','FRONTAL',
  case when n=5 then '   ' when n=7 then null else 'https://example.invalid/photo-'||n||'.jpg' end,
  array['https://example.invalid/attachment.pdf'],17,3,n=4,false,pg_temp.photo_key('2',2),'bubble'
 from generate_series(1,7) n;
select pg_temp.photo_actor(1);
do $$ declare p jsonb:=pg_temp.photo_payload(); before_row jsonb; after_row jsonb; r jsonb; rid uuid:=gen_random_uuid(); before_version text; begin
 perform pg_temp.photo_reject(p,'22023','em.photos.read');
 perform pg_temp.photo_reject(p,'22023','em.planning.manage');
 perform pg_temp.photo_reject(p||'{"actor_id":"2a100000-0000-4000-8000-000000000002"}','22023');
 perform pg_temp.photo_reject(p||'{"tag":"arbitrary"}','22023');
 perform pg_temp.photo_reject(p-'selected','22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{selected}','"true"'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{selected}','1'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{selected}','null'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{foto_id}','null'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{projeto_id}','"invalid"'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{expected_updated_at}','null'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{expected_updated_at}','"infinity"'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{expected_updated_at}','"2026-01-01 10:00:00"'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{expected_updated_at}','"2026-99-01T10:00:00Z"'),'22023');
 perform pg_temp.photo_reject(jsonb_set(p,'{expected_updated_at}','"2000-01-01T00:00:00Z"'),'PT409');
 perform pg_temp.photo_reject(p||jsonb_build_object('projeto_id',gen_random_uuid()),'P0002');
 perform pg_temp.photo_reject(p||jsonb_build_object('foto_id',gen_random_uuid()),'P0002');
 perform pg_temp.photo_reject(pg_temp.photo_payload(3),'22023');
 perform pg_temp.photo_reject(pg_temp.photo_payload(4),'22023');
 perform pg_temp.photo_reject(pg_temp.photo_payload(5),'22023');
 perform pg_temp.photo_reject(pg_temp.photo_payload(6),'22023');
 perform pg_temp.photo_reject(pg_temp.photo_payload(7),'22023');
 select to_jsonb(f) into before_row from public.rm_fotos f where id=pg_temp.photo_key('6',1);
 before_version:=before_row->>'updated_at';
 r:=pg_temp.photo_call(rid,p);
 select to_jsonb(f) into after_row from public.rm_fotos f where id=pg_temp.photo_key('6',1);
 perform pg_temp.photo_check((after_row->>'selecao_relatorio')::boolean and after_row->>'modified_by_id'=pg_temp.photo_key('2',1)::text
  and after_row->>'sync_source'='supabase' and after_row->>'updated_at'<>before_version,'selection works for delivered/cancelled project and records exact author');
 perform pg_temp.photo_check((before_row-array['selecao_relatorio','modified_by_id','sync_source','updated_at'])=
  (after_row-array['selecao_relatorio','modified_by_id','sync_source','updated_at']),'selection preserves every file, order, tag, title, allocation, creator and metadata field');
 perform pg_temp.photo_check(r->'record'=jsonb_build_object('foto_id',pg_temp.photo_key('6',1),'projeto_id',pg_temp.photo_key('5',1),
  'selecao_relatorio',true,'updated_at',after_row->'updated_at'),'mutation exports only the four exact result fields');
 perform pg_temp.photo_check((select before_record=before_row from rm_private.web_mutation_receipts where client_submission_id=rid),'receipt preserves full before row');
 perform pg_temp.photo_check((pg_temp.photo_call(rid,p)->>'idempotent_replay')::boolean,'fresh permit and exact replay returns previous result before stale-version check');
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'set_project_photo_selection',p);
  raise exception 'FAIL: permitless replay'; exception when insufficient_privilege then reset role; end;
 begin perform pg_temp.photo_call(rid,p||'{"selected":false}'); raise exception 'FAIL: changed payload replay'; exception when unique_violation then null; end;
 perform pg_temp.photo_actor(6);
 begin perform pg_temp.photo_call(rid,p); raise exception 'FAIL: other actor replay'; exception when unique_violation then null; end;
 perform pg_temp.photo_actor(1);
 insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
 begin perform pg_temp.photo_call(rid,p); raise exception 'FAIL: AAL1 replay'; exception when insufficient_privilege then null; end;
 perform pg_temp.photo_actor(1,'aal2');
 perform pg_temp.photo_check((pg_temp.photo_call(rid,p)->>'idempotent_replay')::boolean,'MFA rechecked before replay');
 delete from auth.mfa_factors where user_id=auth.uid(); perform pg_temp.photo_actor(1);
 p:=pg_temp.photo_payload(); r:=pg_temp.photo_call(gen_random_uuid(),p);
 perform pg_temp.photo_check((select to_jsonb(f)=after_row from public.rm_fotos f where id=pg_temp.photo_key('6',1))
  and r->'record'->>'updated_at'=after_row->>'updated_at','no-op preserves whole row including timestamp and author');
 p:=pg_temp.photo_payload(1,false); perform pg_temp.photo_call(gen_random_uuid(),p);
 perform pg_temp.photo_check((select not selecao_relatorio from public.rm_fotos where id=pg_temp.photo_key('6',1)),'deselection persists');
 -- Any metadata writer invalidates the exact version, without replacing fields.
 p:=pg_temp.photo_payload(); update public.rm_fotos set legenda='New external caption' where id=pg_temp.photo_key('6',1);
 perform pg_temp.photo_reject(p,'PT409');
end $$;
select pg_temp.photo_actor(2);
select pg_temp.photo_check((pg_temp.photo_call(gen_random_uuid(),pg_temp.photo_payload())->'record'->>'selecao_relatorio')::boolean,'standard profile may select without changing operator/cell grants');
select pg_temp.photo_actor(3);
select pg_temp.photo_reject(pg_temp.photo_payload(),'42501');
select pg_temp.photo_actor(4);
select pg_temp.photo_reject(pg_temp.photo_payload(),'42501');
select pg_temp.photo_actor(5);
select pg_temp.photo_reject(pg_temp.photo_payload(),'42501');
select pg_temp.photo_actor(1);
do $$ declare p jsonb:=pg_temp.photo_payload(); rid uuid:=gen_random_uuid(); begin
 -- Auth JWT must belong to the exact local session for the approved binding.
 perform public.rm_sso_action_permit_v1(lpad('1',64,'a'),rid,'set_project_photo_selection',p,'em.projects.manage');
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',gen_random_uuid(),'aal','aal1')::text,true);
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'set_project_photo_selection',p);
  raise exception 'FAIL: wrong Auth session'; exception when insufficient_privilege then reset role; end;
 perform pg_temp.photo_actor(1);
 update rm_private.sso_action_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=rid;
 begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'set_project_photo_selection',p);
  raise exception 'FAIL: expired permit'; exception when insufficient_privilege then reset role; end;
 update rm_private.sso_sessions set expires_at=clock_timestamp()-interval '1 second' where hash=lpad('1',64,'a');
 perform pg_temp.photo_reject(p,'42501');
 update rm_private.sso_sessions set expires_at=clock_timestamp()+interval '45 minutes' where hash=lpad('1',64,'a');
 update rm_private.sso_identity_bindings set enabled=false where id=pg_temp.photo_key('8',1);
 perform pg_temp.photo_reject(p,'42501');
end $$;
select pg_temp.photo_check(not has_function_privilege('anon','public.rm_web_mutate_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('service_role','public.rm_web_mutate_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('authenticated','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_pcp_core_v1(uuid,text,jsonb)','execute'),'new private dispatcher and existing entrypoint remain closed');
rollback;
select 'PASS: photo selection validates exact payload, scope, files, role/SSO/MFA, replay, metadata, historical projects and no-op' as result;

-- Committed fixtures and two real PostgreSQL sessions, only in the disposable DB.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_photos;
create function rm_test_photos.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function rm_test_photos.key(h text,n integer) returns uuid language sql immutable as $$
 select (h||'a200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
insert into auth.users(id) values(rm_test_photos.key('1',1));
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values(rm_test_photos.key('2',1),rm_test_photos.key('1',1),'Photo concurrent admin','administrador');
insert into auth.sessions(id,user_id) values(rm_test_photos.key('3',1),rm_test_photos.key('1',1));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
 values(rm_test_photos.key('8',1),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',rm_test_photos.key('9',1),
  rm_test_photos.key('2',1),rm_test_photos.key('1',1),true,rm_test_photos.key('2',1),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('a2',32),rm_test_photos.key('8',1),rm_test_photos.key('3',1),
 'opaque-fixture-photo-races',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_projetos(id,numero) select rm_test_photos.key('5',n),'PHOTO-RACE-22-'||n from generate_series(1,8) n;
insert into public.rm_fotos(id,projeto_id,foto_url,numero,tag,selecao_relatorio)
 select rm_test_photos.key('6',n),rm_test_photos.key('5',n),'https://example.invalid/original.jpg',77,'ORIGINAL',false from generate_series(1,7) n;
create function rm_test_photos.run(mode text,rid uuid,p jsonb,hold_seconds real default 0) returns jsonb language plpgsql as $$
declare r jsonb; state text; begin
 perform set_config('request.jwt.claim.sub',rm_test_photos.key('1',1)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',rm_test_photos.key('3',1),'aal','aal1')::text,true);
 if mode='select' then
  perform public.rm_sso_action_permit_v1(repeat('a2',32),rid,'set_project_photo_selection',p,'em.projects.manage');
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,'set_project_photo_selection',p); reset role;
 elsif mode='metadata' then
  update public.rm_fotos set foto_url='https://example.invalid/concurrent.jpg',tag='CONCURRENT',numero=88 where id=(p->>'foto_id')::uuid;
 elsif mode='close' then
  perform pg_advisory_xact_lock(hashtextextended(p->>'projeto_id',11));
  update public.rm_projetos set status_pcp='cancelado',data_real_de_entrega=clock_timestamp() where id=(p->>'projeto_id')::uuid;
 elsif mode='move' then
  update public.rm_fotos set projeto_id=rm_test_photos.key('5',8) where id=(p->>'foto_id')::uuid;
 elsif mode='delete' then
  perform pg_advisory_xact_lock(hashtextextended(p->>'projeto_id',11));
  delete from public.rm_projetos where id=(p->>'projeto_id')::uuid;
 else raise exception 'Unknown test mode'; end if;
 perform pg_sleep(hold_seconds);
 return jsonb_build_object('sqlstate','00000','result',r);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate;
 return jsonb_build_object('sqlstate',state,'message',sqlerrm);
end $$;
commit;
do $$ declare scenario int; p jsonb; a jsonb; b jsonb; pid_a int; pid_b int; waited int;
 first_mode text; second_mode text; first_id uuid; second_id uuid; begin
 perform dblink_connect('photo_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 perform dblink_connect('photo_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
 select pid into pid_a from dblink('photo_a','select pg_backend_pid()') as t(pid integer);
 select pid into pid_b from dblink('photo_b','select pg_backend_pid()') as t(pid integer);
 for scenario in 1..7 loop
  select jsonb_build_object('projeto_id',projeto_id,'foto_id',id,'expected_updated_at',updated_at,'selected',true) into p
   from public.rm_fotos where id=rm_test_photos.key('6',scenario);
  first_mode:=case scenario when 3 then 'metadata' when 5 then 'close' when 6 then 'move' when 7 then 'delete' else 'select' end;
  second_mode:=case scenario when 4 then 'metadata' else 'select' end;
  first_id:=gen_random_uuid(); second_id:=case when scenario=2 then first_id else gen_random_uuid() end;
  perform dblink_send_query('photo_a',format('select rm_test_photos.run(%L,%L,%L::jsonb,1.0)',first_mode,first_id,p::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
   waited:=waited+1; if waited>250 then raise exception 'FAIL: first photo scenario % did not hold',scenario; end if; perform pg_sleep(0.01);
  end loop;
  perform dblink_send_query('photo_b',format('select rm_test_photos.run(%L,%L,%L::jsonb,0)',second_mode,second_id,p::text));
  waited:=0; loop
   perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
   waited:=waited+1; if waited>150 then raise exception 'FAIL: second photo scenario % did not contend',scenario; end if; perform pg_sleep(0.005);
  end loop;
  select r into a from dblink_get_result('photo_a') as t(r jsonb); perform r from dblink_get_result('photo_a') as t(r jsonb);
  select r into b from dblink_get_result('photo_b') as t(r jsonb); perform r from dblink_get_result('photo_b') as t(r jsonb);
  perform rm_test_photos.check(a->>'sqlstate'='00000',format('first photo scenario %s succeeds: %s',scenario,a));
  perform rm_test_photos.check(b->>'sqlstate'=case when scenario in(1,3) then 'PT409' when scenario=6 then '22023'
   when scenario=7 then 'P0002' else '00000' end,format('second photo scenario %s respects locks/revision/scope: %s',scenario,b));
  if scenario=2 then
   perform rm_test_photos.check((b->'result'->>'idempotent_replay')::boolean,'same UUID replay after real contention');
   perform rm_test_photos.check((select count(*)=1 from rm_private.web_mutation_receipts where client_submission_id=first_id),'one receipt for simultaneous same UUID');
  end if;
  if scenario=3 then perform rm_test_photos.check((select not selecao_relatorio and numero=88 and tag='CONCURRENT' from public.rm_fotos where id=rm_test_photos.key('6',scenario)),'metadata winner is never overwritten'); end if;
  if scenario=4 then perform rm_test_photos.check((select selecao_relatorio and numero=88 and tag='CONCURRENT' from public.rm_fotos where id=rm_test_photos.key('6',scenario)),'metadata after selection preserves its flag'); end if;
  if scenario=5 then perform rm_test_photos.check((select selecao_relatorio from public.rm_fotos where id=rm_test_photos.key('6',scenario)),'project closing serializes but does not forbid historical selection'); end if;
  if scenario=6 then perform rm_test_photos.check((select not selecao_relatorio and projeto_id=rm_test_photos.key('5',8) from public.rm_fotos where id=rm_test_photos.key('6',scenario)),'changed project reference is preserved'); end if;
  if scenario=7 then perform rm_test_photos.check(not exists(select 1 from public.rm_fotos where id=rm_test_photos.key('6',scenario)),'project deletion leaves no stale selection or recreated photo'); end if;
 end loop;
 perform dblink_disconnect('photo_a'); perform dblink_disconnect('photo_b');
exception when others then
 if 'photo_a'=any(dblink_get_connections()) then perform dblink_disconnect('photo_a'); end if;
 if 'photo_b'=any(dblink_get_connections()) then perform dblink_disconnect('photo_b'); end if; raise;
end $$;
select 'PASS: real photo concurrency covers competing selections, same UUID, metadata both directions, project closure, changed reference and deletion' as result;
