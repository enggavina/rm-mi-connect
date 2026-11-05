-- Local disposable database only. Upgrade from 035 with warmed web/mobile
-- callers, existing records, pending SSO permit and frozen offline receipt.
\set ON_ERROR_STOP on
\if :{?rm_migration_036_path}
\else
\echo 'Run through isolated runner with rm_migration_036_path.'
\quit 3
\endif
select set_config('rm.test.migration_036_path',:'rm_migration_036_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required'; end if; end $$;
create temporary table bundle_upgrade_snapshots(name text primary key,rows bigint,hash text);
create temporary table bundle_upgrade_functions(id oid primary key,identity text,definition text,acl text);
create temporary table bundle_upgrade_policies(id oid primary key,definition jsonb);
create function pg_temp.check_upgrade(value boolean,message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAIL: %',message; end if; end $$;
create function pg_temp.bundle_sso_call(rid uuid,operation text,payload jsonb) returns jsonb language plpgsql as $$
declare result jsonb; begin
 perform public.rm_sso_action_permit_v1(repeat('6',64),rid,operation,payload,'em.projects.manage');
 set local role authenticated; result:=public.rm_web_mutate_v1(rid,operation,payload); reset role; return result;
exception when others then reset role; raise; end $$;
insert into auth.users(id) values('1eb36000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2eb36000-0000-4000-8000-000000000001','1eb36000-0000-4000-8000-000000000001','Upgrade actor fixture','administrador','ativo');
insert into auth.sessions(id,user_id) values('3eb36000-0000-4000-8000-000000000001','1eb36000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('8eb36000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9eb36000-0000-4000-8000-000000000001',
 '2eb36000-0000-4000-8000-000000000001','1eb36000-0000-4000-8000-000000000001',true,'2eb36000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('6',64),'8eb36000-0000-4000-8000-000000000001','3eb36000-0000-4000-8000-000000000001','opaque-bundle-upgrade-fixture',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','1eb36000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"3eb36000-0000-4000-8000-000000000001","aal":"aal1"}',true);
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('bundle-upgrade-mobile','sha256'),'1eb36000-0000-4000-8000-000000000001','2eb36000-0000-4000-8000-000000000001','2eb36000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
insert into public.rm_clientes(id,nome) values('4eb36000-0000-4000-8000-000000000001','Upgrade client fixture');
insert into public.rm_projetos(id,nome,cliente_id) values('5eb36000-0000-4000-8000-000000000001','Upgrade original','4eb36000-0000-4000-8000-000000000001');
insert into public.rm_equipamentos(id,projeto_id,descricao,modelo) values('6eb36000-0000-4000-8000-000000000001','5eb36000-0000-4000-8000-000000000001','Legacy description','Legacy model');
update public.rm_projetos set equipamento_id='6eb36000-0000-4000-8000-000000000001' where id='5eb36000-0000-4000-8000-000000000001';
-- Warm old SSO dispatcher, equipment snapshot, and delegated mobile receipt.
do $$ declare s jsonb; p jsonb; r jsonb; begin
 s:=public.rm_web_project_equipment_snapshot_v1('5eb36000-0000-4000-8000-000000000001');
 p:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('nome','Warm legacy writer'));
 r:=pg_temp.bundle_sso_call('aeb36000-0000-4000-8000-000000000001','save_project',p);
 perform pg_temp.check_upgrade(r->>'id'='5eb36000-0000-4000-8000-000000000001','old project dispatcher warmed');
 set local role authenticated;
 r:=public.rm_mobile_mutate_v1('aeb36000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',
  '{"p_projeto_id":"5eb36000-0000-4000-8000-000000000001","p_cliente_id":"4eb36000-0000-4000-8000-000000000001","p_equipamento":{"descricao":"Legacy description"}}','bundle-upgrade-mobile');
 reset role;
 perform pg_temp.check_upgrade(r is not null,'old mobile receipt warmed');
end $$;
-- Hold a permit issued before the upgrade. It must survive the DDL untouched.
create temporary table bundle_upgrade_pending(payload jsonb);
insert into bundle_upgrade_pending select jsonb_build_object('id',id,'expected_updated_at',updated_at,'changes',jsonb_build_object('nome','After upgrade')) from public.rm_projetos where id='5eb36000-0000-4000-8000-000000000001';
select public.rm_sso_action_permit_v1(repeat('6',64),'aeb36000-0000-4000-8000-000000000003','save_project',(select payload from bundle_upgrade_pending),'em.projects.manage');
do $$ declare t record; n bigint; h text; begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r'
 and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into bundle_upgrade_snapshots values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 if (select count(*) from bundle_upgrade_snapshots)<>76 then raise exception 'Unexpected RM/Storage tables before 036'; end if;
 insert into bundle_upgrade_functions select p.oid,p.oid::regprocedure::text,pg_get_functiondef(p.oid),coalesce(p.proacl::text,'') from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='rm_private' or (ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into bundle_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace ns on ns.oid=c.relnamespace
  where (ns.nspname='public' and c.relname like 'rm\_%' escape '\') or (ns.nspname='storage' and c.relname in('buckets','objects'));
end $$;
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_036_path')); begin
 if (select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or (select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Migration transaction structure mismatch'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n',''); source:=regexp_replace(source,'(?m)^commit;\s*$',''); execute source;
end $$;
do $$ declare t record; n bigint; h text; expected text; marker text; begin
 for t in select * from bundle_upgrade_snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: existing table data changed: %',t.name; end if;
 end loop;
 if exists(select 1 from bundle_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.definition)) then raise exception 'FAIL: existing policy changed'; end if;
 for t in select * from bundle_upgrade_functions loop
  expected:=t.definition;
  if t.identity='rm_private.web_mutate_core_v1(uuid,text,jsonb)' then
   expected:=replace(expected,'CREATE OR REPLACE FUNCTION rm_private.web_mutate_core_v1(','CREATE OR REPLACE FUNCTION rm_private.web_mutate_before_equipment_bundle_v1(');
  elsif t.identity in('rm_sso_action_permit_v1(text,uuid,text,jsonb,text)','public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)') then
   marker:='when ''finalize_project_attachment_version'' then ''em.projects.manage'' end;';
   expected:=replace(expected,marker,'when ''finalize_project_attachment_version'' then ''em.projects.manage'' when ''save_project_with_equipment'' then ''em.projects.manage'' end;');
  end if;
  if not exists(select 1 from pg_proc p where p.oid=t.id and pg_get_functiondef(p.oid)=expected and coalesce(p.proacl::text,'')=t.acl) then raise exception 'FAIL: prior function changed unexpectedly: %',t.identity; end if;
 end loop;
end $$;
-- Pending permit, authenticated entry point and mobile replay all remain usable.
do $$ declare r jsonb; p jsonb; begin
 p:=(select payload from bundle_upgrade_pending);
 set local role authenticated;
 r:=public.rm_web_mutate_v1('aeb36000-0000-4000-8000-000000000003','save_project',p);
 perform pg_temp.check_upgrade(r->>'id'='5eb36000-0000-4000-8000-000000000001','old SSO permit survives upgrade');
 r:=public.rm_mobile_mutate_v1('aeb36000-0000-4000-8000-000000000002','rm_submit_recebimento_v1',
  '{"p_projeto_id":"5eb36000-0000-4000-8000-000000000001","p_cliente_id":"4eb36000-0000-4000-8000-000000000001","p_equipamento":{"descricao":"Legacy description"}}','bundle-upgrade-mobile');
 perform pg_temp.check_upgrade((r->>'idempotent_replay')::boolean,'old offline receipt can replay');
 reset role;
 p:=jsonb_build_object('id','5eb36000-0000-4000-8000-000000000002','expected_updated_at',null,'changes',jsonb_build_object('nome','New after upgrade'),
  'equipment',jsonb_build_object('id','6eb36000-0000-4000-8000-000000000002','expected_updated_at',null,'expected_context_version',null,'changes',jsonb_build_object('fabricante','Fixture')));
 r:=pg_temp.bundle_sso_call('aeb36000-0000-4000-8000-000000000004','save_project_with_equipment',p);
 perform pg_temp.check_upgrade(r->'record'->>'equipamento_id'='6eb36000-0000-4000-8000-000000000002','new operation uses refreshed SSO map');
end $$;
rollback;
\ir ../migrations/036_rm_web_project_equipment_bundle.sql
select 'PASS: 036 upgrade preserves RM/Storage rows, policies, old function ACLs, warmed SSO and mobile receipts' as result;
