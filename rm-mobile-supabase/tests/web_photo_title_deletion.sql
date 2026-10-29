\set ON_ERROR_STOP on
begin;
create function pg_temp.title_key(prefix text,n int default 1) returns uuid language sql immutable as $$
 select (prefix||'2300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.title_check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.title_actor(n int) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',pg_temp.title_key('1',n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.title_key('3',n),'aal','aal1')::text,true);
 perform set_config('rm.test.title.actor',n::text,true);
end $$;
create function pg_temp.title_payload(n int default 1) returns jsonb language sql as $$
 select jsonb_build_object('id',id,'expected_updated_at',updated_at) from public.rm_cadastro_fotos where id=pg_temp.title_key('a',n);
$$;
create function pg_temp.title_call(rid uuid,p jsonb,cap text default 'em.engineering.manage') returns jsonb language plpgsql as $$
declare r jsonb; begin
 perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.title.actor'),64,'c'),rid,'delete_photo_title',p,cap);
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'delete_photo_title',p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.title_reject(p jsonb,wanted text,cap text default 'em.engineering.manage') returns void language plpgsql as $$
declare actual text; begin
 begin perform pg_temp.title_call(gen_random_uuid(),p,cap);
 exception when others then get stacked diagnostics actual=returned_sqlstate;
  if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
 end; raise exception 'FAIL: deletion succeeded (expected %)',wanted;
end $$;
do $$ declare n int; begin
 for n in 1..2 loop
  insert into auth.users(id) values(pg_temp.title_key('1',n));
  insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.title_key('2',n),pg_temp.title_key('1',n),'Title fixture '||n,'administrador');
  insert into auth.sessions(id,user_id) values(pg_temp.title_key('3',n),pg_temp.title_key('1',n));
  insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
   values(pg_temp.title_key('8',n),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.title_key('9',n),
    pg_temp.title_key('2',n),pg_temp.title_key('1',n),true,pg_temp.title_key('2',1),clock_timestamp());
  perform public.rm_sso_session_put_v1(lpad(n::text,64,'c'),pg_temp.title_key('8',n),pg_temp.title_key('3',n),
   'opaque-local-title-fixture-'||n,clock_timestamp()+interval '45 minutes');
 end loop;
end $$;
update rm_private.sso_settings set require_sso=true;
select pg_temp.title_actor(1);
insert into public.rm_cadastro_fotos(id,titulo,celula_nome)
 select pg_temp.title_key('a',n),'Title fixture '||n,null from generate_series(1,6) n;
insert into public.rm_projetos(id,numero) values(pg_temp.title_key('5'),'TITLE-DELETION-23');
insert into public.rm_fotos(id,projeto_id,cadastro_foto_id,titulo,lixeira) values
 (pg_temp.title_key('6',1),null,pg_temp.title_key('a',2),'Old model snapshot',true),
 (pg_temp.title_key('6',2),pg_temp.title_key('5'),pg_temp.title_key('a',3),'Operational snapshot',false);
select set_config('rm.test.title.outbox',(select count(*)::text from public.rm_sync_outbox),true);

-- A concurrent engineering-photo writer holds this same shared master lock.
-- Failed lock acquisition leaves both title and receipt untouched.
create extension if not exists dblink;
alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) set lock_timeout='100ms';
do $title_lock$ begin
 perform dblink_connect('title_delete_lock','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user='||current_user);
 perform dblink_exec('title_delete_lock','begin');
 perform dblink_exec('title_delete_lock',$remote$do $$ begin perform pg_advisory_xact_lock_shared(hashtextextended('rm.web.catalogs',17)); end $$;$remote$);
 perform pg_temp.title_reject(pg_temp.title_payload(4),'55P03');
 perform pg_temp.title_check(exists(select 1 from public.rm_cadastro_fotos where id=pg_temp.title_key('a',4)),'concurrent writer preserves title');
 perform dblink_exec('title_delete_lock','rollback'); perform dblink_disconnect('title_delete_lock');
exception when others then
 if 'title_delete_lock'=any(dblink_get_connections()) then perform dblink_exec('title_delete_lock','rollback'); perform dblink_disconnect('title_delete_lock'); end if; raise;
end $title_lock$;

do $$ declare p jsonb:=pg_temp.title_payload(); r jsonb; rid uuid:=gen_random_uuid(); original jsonb; begin
 perform pg_temp.title_reject(p,'22023','em.catalogs.manage');
 perform pg_temp.title_reject(p||jsonb_build_object('actor_id',pg_temp.title_key('2',2)),'22023');
 perform pg_temp.title_reject(p||'{"changes":{}}','22023');
 perform pg_temp.title_reject(p-'id','22023');
 perform pg_temp.title_reject(jsonb_set(p,'{id}','null'),'22023');
 perform pg_temp.title_reject(jsonb_set(p,'{id}','"invalid"'),'22023');
 perform pg_temp.title_reject(jsonb_set(p,'{expected_updated_at}','null'),'22023');
 perform pg_temp.title_reject(jsonb_set(p,'{expected_updated_at}','"infinity"'),'22023');
 perform pg_temp.title_reject(jsonb_set(p,'{expected_updated_at}','"2026-10-29 10:00:00"'),'22023');
 perform pg_temp.title_reject(jsonb_set(p,'{expected_updated_at}','"2026-01-01T00:00:00Z"'),'PT409');
 perform pg_temp.title_reject(jsonb_set(p,'{id}',to_jsonb(gen_random_uuid())),'PT409');
 perform pg_temp.title_reject(pg_temp.title_payload(2),'23503');
 perform pg_temp.title_reject(pg_temp.title_payload(3),'23503');
 perform pg_temp.title_check((select titulo from public.rm_fotos where id=pg_temp.title_key('6',2))='Operational snapshot','referenced snapshots unchanged');
 update public.rm_users set perfil='auditor' where id=pg_temp.title_key('2',1);
 perform pg_temp.title_reject(p,'42501');
 update public.rm_users set perfil='padr_o' where id=pg_temp.title_key('2',1);
 perform pg_temp.title_reject(p,'42501');
 update public.rm_users set perfil='administrador' where id=pg_temp.title_key('2',1);
 insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.title_key('1',1),'totp','verified');
 perform pg_temp.title_reject(p,'42501');
 delete from auth.mfa_factors where user_id=pg_temp.title_key('1',1);
 -- The public envelope refuses missing permits even for an existing receipt.
 begin
  set local role authenticated; perform public.rm_web_mutate_v1(rid,'delete_photo_title',p); reset role;
  raise exception 'FAIL: missing permit accepted';
 exception when insufficient_privilege then reset role; end;
 select to_jsonb(t) into original from public.rm_cadastro_fotos t where id=pg_temp.title_key('a');
 r:=pg_temp.title_call(rid,p);
 perform pg_temp.title_check(r->>'operation'='delete_photo_title' and not exists(select 1 from public.rm_cadastro_fotos where id=pg_temp.title_key('a')),'unused title removed');
 perform pg_temp.title_check((select before_record from rm_private.web_mutation_receipts where client_submission_id=rid)=original,'audit stores exact prior record');
 perform pg_temp.title_check((pg_temp.title_call(rid,p)->>'idempotent_replay')::boolean,'exact replay after delete');
 begin perform pg_temp.title_call(rid,pg_temp.title_payload(4)); raise exception 'FAIL: changed payload reused'; exception when unique_violation then null; end;
 perform pg_temp.title_actor(2);
 begin perform pg_temp.title_call(rid,p); raise exception 'FAIL: changed actor replayed'; exception when unique_violation then null; end;
 perform pg_temp.title_actor(1);
 begin
  set local role authenticated; perform public.rm_web_mutate_v1(rid,'delete_photo_title',p); reset role;
  raise exception 'FAIL: replay bypassed fresh permit';
 exception when insufficient_privilege then reset role; end;
end $$;

do $$ declare r jsonb; rid uuid:=gen_random_uuid(); p jsonb; begin
 p:=jsonb_build_object('id',pg_temp.title_key('a',6),
  'expected_updated_at',(select updated_at from public.rm_cadastro_fotos where id=pg_temp.title_key('a',6)),
  'changes',jsonb_build_object('titulo','Existing save remains available'));
 perform public.rm_sso_action_permit_v1(lpad('1',64,'c'),rid,'save_photo_title',p,'em.engineering.manage');
 set local role authenticated; r:=public.rm_web_mutate_v1(rid,'save_photo_title',p); reset role;
 perform pg_temp.title_check(r->'record'->>'titulo'='Existing save remains available','existing title save still delegates');
 perform pg_temp.title_check((select count(*) from public.rm_sync_outbox)=current_setting('rm.test.title.outbox')::bigint,'no outbound jobs');
 perform pg_temp.title_check(not has_function_privilege('authenticated','rm_private.web_mutate_core_v1(uuid,text,jsonb)','EXECUTE'),'core remains private');
 perform pg_temp.title_check(not has_table_privilege('authenticated','public.rm_cadastro_fotos','DELETE'),'no direct delete grant');
end $$;
rollback;
select 'PASS: title deletion version, references, SSO/MFA, replay, audit and shared-writer lock' as result;
