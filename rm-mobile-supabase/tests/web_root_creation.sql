\set ON_ERROR_STOP on
begin;
create function pg_temp.root_id(n int) returns uuid language sql immutable as $$
 select ('06500000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.verify_root(v boolean,msg text) returns void language plpgsql as $$
begin
 if v is distinct from true then raise exception 'FAIL: %',msg; end if;
end $$;
create function pg_temp.root_denied(command text,state text) returns void language plpgsql as $$
begin
 begin execute command; exception when others then if sqlstate=state then return; end if; raise; end;
 raise exception 'FAIL: request unexpectedly accepted';
end $$;
create function pg_temp.root_context(office int default 1) returns jsonb language sql as $$
 select jsonb_build_object('version',2,'application','em','channel','web','authority','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
  'workshop',jsonb_build_object('id',pg_temp.root_id(office),'code',case office when 1 then 'BMA' else 'BRJ' end,
   'name','Local workshop','active',true,'revision',1,'updated_at',stamp),
  'principals',jsonb_build_array(jsonb_build_object('kind','corporate','issuer','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',
   'subject',pg_temp.root_id(14),'revision',1)), 'issued_at',stamp,'expires_at',stamp+interval '4 minutes')
 from (select clock_timestamp() stamp)s;
$$;
create function pg_temp.root_payload(i int,cell boolean default false) returns jsonb language sql as $$
 select jsonb_build_object('id',pg_temp.root_id(i),'expected_updated_at',null,'changes',jsonb_build_object('nome','LOCAL 065 '||i))
  ||case when cell then '{"kind":"cells"}'::jsonb else '{}'::jsonb end;
$$;
create function pg_temp.root_mint(rid int,operation text,payload jsonb,office int default 1) returns void language sql as $$
 select public.rm_sso_root_creation_permit_v1(repeat('5',64),pg_temp.root_id(rid),operation,payload,pg_temp.root_context(office));
$$;
create function pg_temp.root_call(rid int,operation text,payload jsonb,office int default 1) returns jsonb language plpgsql as $$
declare result jsonb;
begin
 perform pg_temp.root_mint(rid,operation,payload,office);
 set local role authenticated;
 result:=public.rm_web_mutate_v1(pg_temp.root_id(rid),operation,payload);
 reset role;
 return result;
end $$;

select rm_private.workshop_adopt_bma_roots_v1(
 '[{"id":"06500000-0000-4000-8000-000000000001","code":"BMA"},{"id":"06500000-0000-4000-8000-000000000002","code":"BRJ"},{"id":"06500000-0000-4000-8000-000000000003","code":"BBH"}]',
 'c45f1ff7d60b695cfa708041e959489b7e05a02ace4bcdce1ff16c8b80d14db2',
 (select count(*) from public.rm_projetos),(select count(*) from public.rm_celulas));
insert into auth.users(id) values(pg_temp.root_id(11));
insert into public.rm_users(id,auth_user_id,nome,perfil) values(pg_temp.root_id(12),pg_temp.root_id(11),'Local manager 065','administrador');
insert into auth.sessions(id,user_id) values(pg_temp.root_id(13),pg_temp.root_id(11));
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 (pg_temp.root_id(15),'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.root_id(14),pg_temp.root_id(12),pg_temp.root_id(11),true,pg_temp.root_id(12),clock_timestamp());
select public.rm_sso_session_put_v1(repeat('5',64),pg_temp.root_id(15),pg_temp.root_id(13),'opaque-local-root-creation',clock_timestamp()+interval '30 minutes');
select set_config('request.jwt.claim.sub',pg_temp.root_id(11)::text,true);
select set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.root_id(13),'aal','aal1')::text,true);
select pg_temp.verify_root((select deployment_id is null from rm_private.root_creation_settings),'staged rollout');
select pg_temp.root_denied(format('select rm_private.activate_root_creation_v1(%L,%L)',repeat('a',40),pg_temp.root_id(90)),'PT409');
update rm_private.sso_settings set require_sso=true;
select rm_private.activate_root_creation_v1(repeat('a',40),pg_temp.root_id(90));
select rm_private.activate_root_creation_v1(repeat('a',40),pg_temp.root_id(90));
select pg_temp.root_denied(format('select rm_private.activate_root_creation_v1(%L,%L)',repeat('b',40),pg_temp.root_id(90)),'PT409');

-- Both business paths require the new office permit once activated.
select public.rm_sso_action_permit_v1(repeat('5',64),pg_temp.root_id(31),'save_project',pg_temp.root_payload(21),'em.projects.manage');
select public.rm_sso_action_permit_v1(repeat('5',64),pg_temp.root_id(32),'save_catalog',pg_temp.root_payload(22,true),'em.catalogs.manage');
set local role authenticated;
select pg_temp.root_denied('select public.rm_web_mutate_v1(pg_temp.root_id(31),''save_project'',pg_temp.root_payload(21))','42501');
select pg_temp.root_denied('select public.rm_web_mutate_v1(pg_temp.root_id(32),''save_catalog'',pg_temp.root_payload(22,true))','42501');
select pg_temp.root_denied('select pg_temp.root_mint(31,''save_project'',pg_temp.root_payload(21))','42501');
reset role;

select pg_temp.root_call(31,'save_project',pg_temp.root_payload(21));
select pg_temp.root_call(32,'save_catalog',pg_temp.root_payload(22,true),2);
select pg_temp.root_call(33,'save_project_with_equipment',pg_temp.root_payload(23)||jsonb_build_object('equipment',
 jsonb_build_object('id',pg_temp.root_id(24),'expected_updated_at',null,'expected_context_version',null,'changes','{}'::jsonb)));
select pg_temp.verify_root(
 (select count(*)=2 from rm_private.workshop_project_ownership where id in(pg_temp.root_id(21),pg_temp.root_id(23)) and workshop_id=pg_temp.root_id(1))
 and (select workshop_id=pg_temp.root_id(2) from rm_private.workshop_cell_ownership where cell_id=pg_temp.root_id(22))
 and (select equipamento_id=pg_temp.root_id(24) from public.rm_projetos where id=pg_temp.root_id(23))
 and (select count(*)=3 from rm_private.workshop_object_origins where object_id in(pg_temp.root_id(21),pg_temp.root_id(22),pg_temp.root_id(23))),
 'all three portal creations record durable origin with the bundle');
select pg_temp.verify_root((pg_temp.root_call(31,'save_project',pg_temp.root_payload(21))->>'idempotent_replay')::boolean,'same office replay');
select pg_temp.root_denied('select pg_temp.root_call(31,''save_project'',pg_temp.root_payload(21),2)','42501');
select pg_temp.root_denied('select pg_temp.root_call(35,''save_catalog'',pg_temp.root_payload(22,true))','42501');

do $$
declare command jsonb;
begin
 command:=jsonb_build_object('kind','cells','id',pg_temp.root_id(22),'expected_updated_at',
  (select updated_at from public.rm_celulas where id=pg_temp.root_id(22)));
 perform pg_temp.root_denied(format('select pg_temp.root_call(45,''delete_catalog'',%L)',command),'42501');
 perform pg_temp.root_call(45,'delete_catalog',command,2);
 perform pg_temp.verify_root((pg_temp.root_call(45,'delete_catalog',command,2)->>'idempotent_replay')::boolean,'authorized cell deletion retries');
end $$;
select pg_temp.verify_root(not exists(select 1 from public.rm_celulas where id=pg_temp.root_id(22))
 and exists(select 1 from rm_private.workshop_origin_retirements where object_kind='cell' and object_id=pg_temp.root_id(22)),
 'cell deletion cascades ownership and retains origin');
select pg_temp.root_denied('select pg_temp.root_call(46,''save_catalog'',pg_temp.root_payload(22,true),2)','PT410');

-- The same root cannot be reassigned, including roots with pending legacy origin.
insert into public.rm_projetos(id,nome) values(pg_temp.root_id(25),'Local pending 065');
select pg_temp.root_denied('select pg_temp.root_call(36,''save_project'',pg_temp.root_payload(25))','42501');
select pg_temp.verify_root(not exists(select 1 from rm_private.workshop_project_ownership where id=pg_temp.root_id(25)),'unknown origin preserved');

-- Late ownership failure rolls back the business row, the equipment and its receipt.
insert into public.rm_clientes(id,nome) values(pg_temp.root_id(26),'Local BRJ customer');
insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values('client',pg_temp.root_id(26),pg_temp.root_id(2));
select pg_temp.root_denied('select pg_temp.root_call(37,''save_project'',jsonb_set(pg_temp.root_payload(27),''{changes,cliente_id}'',to_jsonb(pg_temp.root_id(26))))','PT409');
select pg_temp.verify_root(not exists(select 1 from public.rm_projetos where id=pg_temp.root_id(27))
 and not exists(select 1 from rm_private.workshop_object_origins where object_id=pg_temp.root_id(27))
 and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=pg_temp.root_id(37)),
 'late classification failure rolled back mutation and receipt');

select pg_temp.root_mint(38,'save_project',pg_temp.root_payload(28));
update rm_private.root_creation_permits set expires_at=clock_timestamp()-interval '1 second' where submission_id=pg_temp.root_id(38);
set local role authenticated;
select pg_temp.root_denied('select public.rm_web_mutate_v1(pg_temp.root_id(38),''save_project'',pg_temp.root_payload(28))','42501');
reset role;
select pg_temp.verify_root(not has_function_privilege('authenticated','public.rm_sso_root_creation_permit_v1(text,uuid,text,jsonb,jsonb)','execute')
 and not has_function_privilege('service_role','rm_private.activate_root_creation_v1(text,uuid)','execute')
 and not has_table_privilege('service_role','rm_private.root_creation_permits','select'),'permit and activation privileges');
select 'PASS: portal root creation, atomic office assignment, authorization and replay' result;
rollback;
