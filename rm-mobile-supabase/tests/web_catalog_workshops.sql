\set ON_ERROR_STOP on
begin;
create function pg_temp.cw_id(n int) returns uuid language sql immutable as $$select ('05700000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.cw_check(v boolean,msg text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
create function pg_temp.cw_deny(statement text,state text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlstate=state then return;end if;raise;end;
 raise exception 'FAIL: request unexpectedly accepted: %',statement;end$$;
create function pg_temp.cw_context(office int default 1) returns jsonb language sql as $$
 select jsonb_build_object('version',2,'application','em','channel','web','authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
 'workshop',jsonb_build_object('id',pg_temp.cw_id(office),'code',case office when 1 then 'BMA' else 'BRJ' end,'name','LOCAL office','active',true,'revision',1,'updated_at',clock_timestamp()),
 'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','subject',pg_temp.cw_id(14),'revision',1)),
 'issued_at',stamp,'expires_at',stamp+interval '5 minutes') from(select clock_timestamp() stamp)s;$$;
create function pg_temp.cw_payload(kind text,id uuid,version text default null) returns jsonb language sql as $$
 select jsonb_build_object('kind',kind,'id',id,'expected_updated_at',version,'changes',jsonb_build_object('nome','LOCAL scoped '||id));$$;
create function pg_temp.cw_mint(rid uuid,operation text,payload jsonb,office int default 1) returns void language sql as $$
 select public.rm_sso_catalog_workshop_permit_v1(repeat('9',64),rid,operation,payload,pg_temp.cw_context(office));$$;
create function pg_temp.cw_call(rid uuid,operation text,payload jsonb,office int default 1) returns jsonb language plpgsql as $$declare result jsonb;begin
 perform pg_temp.cw_mint(rid,operation,payload,office);
 set local role authenticated;result:=public.rm_web_mutate_v1(rid,operation,payload);reset role;return result;
 exception when others then reset role;raise;end$$;

select pg_temp.cw_check(not(select enforced from rm_private.catalog_workshop_write_settings),'installation staged disabled');
select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"05700000-0000-4000-8000-000000000001","code":"BMA"},{"id":"05700000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"05700000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
select rm_private.workshop_catalog_adopt_bma_v1('f08dcd11906184bede3406fbd2acbc193f455334362d1915b8d25c86b61621ff',
 (select count(*) from public.rm_clientes),(select count(*) from public.rm_tipos_equipamento),(select count(*) from public.rm_forms));
insert into auth.users(id) values(pg_temp.cw_id(11));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.cw_id(12),pg_temp.cw_id(11),'LOCAL scoped admin','administrador');
insert into auth.sessions(id,user_id) values(pg_temp.cw_id(13),pg_temp.cw_id(11));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 (pg_temp.cw_id(15),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.cw_id(14),pg_temp.cw_id(12),pg_temp.cw_id(11),true,pg_temp.cw_id(12),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('9',64),pg_temp.cw_id(15),pg_temp.cw_id(13),'opaque-local-catalog-workshop',clock_timestamp()+interval '30 minutes');
select set_config('request.jwt.claim.sub',pg_temp.cw_id(11)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.cw_id(13),'aal','aal1')::text,true);
select pg_temp.cw_deny(format('select rm_private.activate_catalog_workshop_writes_v1(%L,%L)',repeat('a',40),pg_temp.cw_id(90)),'PT409');
update rm_private.sso_settings set require_sso=true;
select rm_private.activate_catalog_workshop_writes_v1(repeat('a',40),pg_temp.cw_id(90));
select pg_temp.cw_check((rm_private.activate_catalog_workshop_writes_v1(repeat('a',40),pg_temp.cw_id(90))->>'replayed')::boolean,'activation exact retry');
select pg_temp.cw_deny(format('select rm_private.activate_catalog_workshop_writes_v1(%L,%L)',repeat('b',40),pg_temp.cw_id(90)),'PT409');

-- A fresh original v1 action permit cannot bypass the activated workshop guard.
select public.rm_sso_action_permit_v1(repeat('9',64),pg_temp.cw_id(31),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(21)),'em.catalogs.manage');
set local role authenticated;
select pg_temp.cw_deny('select public.rm_web_mutate_v1(pg_temp.cw_id(31),''save_catalog'',pg_temp.cw_payload(''clients'',pg_temp.cw_id(21)))','42501');
select pg_temp.cw_deny('select pg_temp.cw_mint(pg_temp.cw_id(31),''save_catalog'',pg_temp.cw_payload(''clients'',pg_temp.cw_id(21)))','42501');
reset role;

-- Service RPC validates exact authority/schema, identity, freshness and office.
do $$declare bad jsonb;begin
 foreach bad in array array[
  pg_temp.cw_context()||'{"extra":true}',jsonb_set(pg_temp.cw_context(),'{channel}','"mobile"'),
  jsonb_set(pg_temp.cw_context(),'{workshop,active}','false'),jsonb_set(pg_temp.cw_context(),'{workshop,id}',to_jsonb(pg_temp.cw_id(99))),
  jsonb_set(pg_temp.cw_context(),'{principals,0,subject}',to_jsonb(pg_temp.cw_id(99))),
  jsonb_set(pg_temp.cw_context(),'{principals,0,revision}','0'),jsonb_set(pg_temp.cw_context(),'{issued_at}',to_jsonb(clock_timestamp()-interval '1 minute')),
  jsonb_set(pg_temp.cw_context(),'{expires_at}',to_jsonb(clock_timestamp()-interval '1 second'))]
 loop
  perform pg_temp.cw_deny(format('select public.rm_sso_catalog_workshop_permit_v1(%L,%L,%L,%L,%L)',repeat('9',64),gen_random_uuid(),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(21)),bad),
   case when bad ? 'extra' or bad->>'channel'='mobile' or bad->'workshop'->>'active'='false' or bad->'principals'->0->>'revision'='0' then '22023' else '42501' end);
 end loop;end$$;
set local role service_role;
select pg_temp.cw_mint(pg_temp.cw_id(31),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(21)));
reset role;
select pg_temp.cw_deny('select pg_temp.cw_mint(pg_temp.cw_id(31),''save_catalog'',pg_temp.cw_payload(''clients'',pg_temp.cw_id(21)),2)','23505');
set local role authenticated;
select public.rm_web_mutate_v1(pg_temp.cw_id(31),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(21)));
reset role;
select pg_temp.cw_check((select workshop_id=pg_temp.cw_id(1) from rm_private.workshop_catalog_ownership where object_kind='client' and object_id=pg_temp.cw_id(21)),'creation classified atomically');
select pg_temp.cw_check((pg_temp.cw_call(pg_temp.cw_id(31),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(21)))->>'idempotent_replay')::boolean,'fresh scope replay');
select pg_temp.cw_call(pg_temp.cw_id(32),'save_catalog',pg_temp.cw_payload('types',pg_temp.cw_id(22)));

-- Known other-office and unknown existing roots fail without adopting them.
insert into public.rm_clientes(id,nome) values(pg_temp.cw_id(23),'LOCAL unknown'),(pg_temp.cw_id(24),'LOCAL other office');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',pg_temp.cw_id(24),pg_temp.cw_id(2));
do $$declare n int;v text;begin foreach n in array array[23,24] loop
 select updated_at::text into v from public.rm_clientes where id=pg_temp.cw_id(n);
 perform pg_temp.cw_deny(format('select pg_temp.cw_call(%L,''save_catalog'',%L)',gen_random_uuid(),pg_temp.cw_payload('clients',pg_temp.cw_id(n),v)),'42501');end loop;end$$;
select pg_temp.cw_check(not exists(select 1 from rm_private.workshop_catalog_ownership where object_id=pg_temp.cw_id(23)),'unknown origin remains pending');

-- Edit/delete are own-office, optimistic and retain durable origin after delete.
do $$declare p jsonb;r jsonb;rid uuid:=gen_random_uuid();begin
 p:=pg_temp.cw_payload('types',pg_temp.cw_id(22),(select updated_at::text from public.rm_tipos_equipamento where id=pg_temp.cw_id(22)));
 r:=pg_temp.cw_call(gen_random_uuid(),'save_catalog',p);
 p:=jsonb_build_object('kind','types','id',pg_temp.cw_id(22),'expected_updated_at',r->>'updated_at');
 perform pg_temp.cw_call(rid,'delete_catalog',p);
 perform pg_temp.cw_check((pg_temp.cw_call(rid,'delete_catalog',p)->>'idempotent_replay')::boolean,'delete replay retains office');
 perform pg_temp.cw_deny(format('select pg_temp.cw_call(%L,''save_catalog'',%L)',gen_random_uuid(),pg_temp.cw_payload('types',pg_temp.cw_id(22))),'PT410');end$$;

-- Expiry and local session/MFA revocation preserve both protocol and business data.
create function pg_temp.cw_fail_assignment() returns trigger language plpgsql as $$begin raise exception using errcode='PT409',message='LOCAL classification conflict';end$$;
create trigger cw_local_assignment_failure before insert on rm_private.workshop_catalog_ownership for each row execute function pg_temp.cw_fail_assignment();
select pg_temp.cw_deny('select pg_temp.cw_call(pg_temp.cw_id(35),''save_catalog'',pg_temp.cw_payload(''clients'',pg_temp.cw_id(26)))','PT409');
select pg_temp.cw_check(not exists(select 1 from public.rm_clientes where id=pg_temp.cw_id(26))
 and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=pg_temp.cw_id(35)),'late classification failure rolls back row and receipt');
drop trigger cw_local_assignment_failure on rm_private.workshop_catalog_ownership;
select pg_temp.cw_mint(pg_temp.cw_id(34),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(25)));
update rm_private.catalog_workshop_write_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=pg_temp.cw_id(34);
set local role authenticated;
select pg_temp.cw_deny('select public.rm_web_mutate_v1(pg_temp.cw_id(34),''save_catalog'',pg_temp.cw_payload(''clients'',pg_temp.cw_id(25)))','42501');
reset role;
select pg_temp.cw_mint(pg_temp.cw_id(34),'save_catalog',pg_temp.cw_payload('clients',pg_temp.cw_id(25)));
insert into auth.mfa_factors(user_id,factor_type,status) values(pg_temp.cw_id(11),'totp','verified');
set local role authenticated;
select pg_temp.cw_deny('select public.rm_web_mutate_v1(pg_temp.cw_id(34),''save_catalog'',pg_temp.cw_payload(''clients'',pg_temp.cw_id(25)))','42501');
reset role;
select pg_temp.cw_check(not exists(select 1 from public.rm_clientes where id=pg_temp.cw_id(25)) and not exists(select 1 from rm_private.workshop_catalog_ownership where object_id=pg_temp.cw_id(25)),'failed mutation creates neither row nor ownership');
select public.rm_sso_session_delete_v1(repeat('9',64));
select pg_temp.cw_check(not exists(select 1 from rm_private.catalog_workshop_write_permits),'logout cascades scope permits');
select pg_temp.cw_check(not has_table_privilege('service_role','rm_private.catalog_workshop_write_permits','select')
 and not has_function_privilege('authenticated','public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.activate_catalog_workshop_writes_v1(text,uuid)','execute'),'private tables and activation remain private');
select 'PASS: scoped catalog web writes, authority, activation, no bypass, atomic origin, replay, expiry, MFA and logout' result;
rollback;
