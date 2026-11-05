\set ON_ERROR_STOP on
\if :{?rm_migration_037_path}
\else
\echo 'Run through isolated runner with rm_migration_037_path.'
\quit 3
\endif
select set_config('rm.test.migration_037_path',:'rm_migration_037_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required'; end if; end $$;
create function pg_temp.route_upgrade_check(v boolean,msg text) returns void language plpgsql as $$ begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('11370000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('21370000-0000-4000-8000-000000000001','11370000-0000-4000-8000-000000000001','Route upgrade actor','administrador','ativo');
insert into auth.sessions(id,user_id) values('31370000-0000-4000-8000-000000000001','11370000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('81370000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','91370000-0000-4000-8000-000000000001','21370000-0000-4000-8000-000000000001','11370000-0000-4000-8000-000000000001',true,'21370000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('37',32),'81370000-0000-4000-8000-000000000001','31370000-0000-4000-8000-000000000001','opaque-route-upgrade-fixture',clock_timestamp()+interval '45 minutes');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','11370000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"31370000-0000-4000-8000-000000000001","aal":"aal1"}',true);
insert into public.rm_tipos_equipamento(id,nome) values('51370000-0000-4000-8000-000000000001','Route upgrade empty type');
insert into public.rm_clientes(id,nome) values('41370000-0000-4000-8000-000000000001','Route mobile client fixture');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
 values(extensions.digest('route-upgrade-mobile','sha256'),'11370000-0000-4000-8000-000000000001','21370000-0000-4000-8000-000000000001','21370000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
create temporary table route_upgrade_payload(payload jsonb);
grant select on route_upgrade_payload to authenticated;
insert into route_upgrade_payload values('{"id":"b1370000-0000-4000-8000-000000000001","expected_updated_at":null,"changes":{"nome":"Warm 036 fixture"},"equipment":{"id":"c1370000-0000-4000-8000-000000000001","expected_updated_at":null,"expected_context_version":null,"changes":{"descricao":"Warm equipment"}}}');
-- Warm 036 dispatch and preserve a permit issued before the migration.
select public.rm_sso_action_permit_v1(repeat('37',32),'d1370000-0000-4000-8000-000000000001','save_project_with_equipment',(select payload from route_upgrade_payload),'em.projects.manage');
set local role authenticated;
select public.rm_web_mutate_v1('d1370000-0000-4000-8000-000000000001','save_project_with_equipment',(select payload from route_upgrade_payload));
select public.rm_mobile_mutate_v1('d1370000-0000-4000-8000-000000000005','rm_submit_recebimento_v1',
 '{"p_projeto_id":"b1370000-0000-4000-8000-000000000001","p_cliente_id":"41370000-0000-4000-8000-000000000001","p_equipamento":{"descricao":"Warm equipment"}}','route-upgrade-mobile');
reset role;
select public.rm_sso_action_permit_v1(repeat('37',32),'d1370000-0000-4000-8000-000000000001','save_project_with_equipment',(select payload from route_upgrade_payload),'em.projects.manage');
create temporary table route_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table route_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table route_upgrade_policies(id oid primary key,value jsonb);
do $$ declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into route_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into route_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into route_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p;
end $$;
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_037_path')); begin
 if (select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or (select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Migration transaction structure mismatch'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n',''); source:=regexp_replace(source,'(?m)^commit;\s*$',''); execute source;
end $$;
do $$ declare t record;n bigint;h text;expected text;begin
 for t in select * from route_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: data changed on upgrade: %',t.name;end if;
 end loop;
 if exists(select 1 from route_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.value)) then raise exception 'FAIL: policy changed';end if;
 for t in select * from route_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner) then raise exception 'FAIL: function owner/ACL changed: %',t.name;end if;
  if t.name='web_mutate_core_v1' then
   expected:=replace(t.definition,'CREATE OR REPLACE FUNCTION rm_private.web_mutate_core_v1(','CREATE OR REPLACE FUNCTION rm_private.web_mutate_before_route_instance_v1(');
   if pg_get_functiondef(t.id)<>expected then raise exception 'FAIL: legacy dispatcher body changed';end if;
  elsif t.name not in('rm_web_project_equipment_snapshot_v1','rm_web_project_route_snapshot_v1','rm_web_receivings_v1','web_mutate_project_core_v1','rm_materialize_project_cells_v1') and pg_get_functiondef(t.id)<>t.definition then raise exception 'FAIL: unrelated function changed: %',t.name;end if;
 end loop;
 perform pg_temp.route_upgrade_check(not exists(select 1 from rm_private.project_route_instances),'upgrade creates no legacy route instances');
end $$;
set local role authenticated;
do $$ declare r jsonb;begin
 r:=public.rm_web_mutate_v1('d1370000-0000-4000-8000-000000000001','save_project_with_equipment',(select payload from route_upgrade_payload));
 perform pg_temp.route_upgrade_check((r->>'idempotent_replay')::boolean,'pre-issued SSO permit and old warmed receipt replay after upgrade');
 r:=public.rm_mobile_mutate_v1('d1370000-0000-4000-8000-000000000005','rm_submit_recebimento_v1',
  '{"p_projeto_id":"b1370000-0000-4000-8000-000000000001","p_cliente_id":"41370000-0000-4000-8000-000000000001","p_equipamento":{"descricao":"Warm equipment"}}','route-upgrade-mobile');
 perform pg_temp.route_upgrade_check((r->>'idempotent_replay')::boolean,'old mobile receipt survives the fresh-web-create guard');
 r:=public.rm_mobile_mutate_v1('d1370000-0000-4000-8000-000000000006','rm_submit_recebimento_v1',
  '{"p_projeto_id":"b1370000-0000-4000-8000-000000000001","p_cliente_id":"41370000-0000-4000-8000-000000000001","p_equipamento":{"descricao":"Warm equipment"}}','route-upgrade-mobile');
 perform pg_temp.route_upgrade_check(r is not null,'existing mobile receiving remains available after the web guard');
end $$;
reset role;
-- New typed request uses exactly the existing capability and needs its own
-- one-shot permit bound to the full extended payload.
update route_upgrade_payload set payload=jsonb_set(jsonb_set(payload,'{id}','"b1370000-0000-4000-8000-000000000002"'),'{equipment,id}','"c1370000-0000-4000-8000-000000000002"');
-- Even an authorized SSO permit cannot reopen the old fresh creation path.
select public.rm_sso_action_permit_v1(repeat('37',32),'d1370000-0000-4000-8000-000000000003','save_project_with_equipment',(select payload from route_upgrade_payload),'em.projects.manage');
set local role authenticated;
do $$ begin begin perform public.rm_web_mutate_v1('d1370000-0000-4000-8000-000000000003','save_project_with_equipment',(select payload from route_upgrade_payload));raise exception 'FAIL: permitted fresh untyped bundle accepted';exception when sqlstate 'PT423' then null;end;end $$;
reset role;
do $$ declare p jsonb:=jsonb_build_object('id','b1370000-0000-4000-8000-000000000003','expected_updated_at',null,'changes',jsonb_build_object('nome','Must not create alone'));begin
 perform public.rm_sso_action_permit_v1(repeat('37',32),'d1370000-0000-4000-8000-000000000004','save_project',p,'em.projects.manage');
 set local role authenticated;
 begin perform public.rm_web_mutate_v1('d1370000-0000-4000-8000-000000000004','save_project',p);raise exception 'FAIL: permitted fresh project-only create accepted';exception when sqlstate 'PT423' then null;end;
 reset role;
 perform pg_temp.route_upgrade_check(not exists(select 1 from public.rm_projetos where id in('b1370000-0000-4000-8000-000000000002','b1370000-0000-4000-8000-000000000003'))
  and not exists(select 1 from public.rm_equipamentos where id='c1370000-0000-4000-8000-000000000002')
  and not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id in('d1370000-0000-4000-8000-000000000003','d1370000-0000-4000-8000-000000000004')),'rejected authorized fresh legacy creation is atomic');
 perform pg_temp.route_upgrade_check((select count(*)=2 from rm_private.sso_action_permits where submission_id in('d1370000-0000-4000-8000-000000000003','d1370000-0000-4000-8000-000000000004')),'failed legacy creation rolls back permit consumption');
end $$;
update route_upgrade_payload set payload=jsonb_set(payload,'{equipment,tipo_equipamento_id}','"51370000-0000-4000-8000-000000000001"');
set local role authenticated;
do $$ begin begin perform public.rm_web_mutate_v1('d1370000-0000-4000-8000-000000000002','save_project_with_equipment',(select payload from route_upgrade_payload)); raise exception 'FAIL: typed clone without SSO permit'; exception when insufficient_privilege then null; end;end $$;
reset role;
select public.rm_sso_action_permit_v1(repeat('37',32),'d1370000-0000-4000-8000-000000000002','save_project_with_equipment',(select payload from route_upgrade_payload),'em.projects.manage');
set local role authenticated;
do $$ declare r jsonb;s jsonb;begin
 r:=public.rm_web_mutate_v1('d1370000-0000-4000-8000-000000000002','save_project_with_equipment',(select payload from route_upgrade_payload));
 s:=public.rm_web_project_route_snapshot_v1('b1370000-0000-4000-8000-000000000002');
 perform pg_temp.route_upgrade_check((s->>'initialized_from_type')::boolean,'typed clone through warmed SSO dispatcher');
end $$;
reset role;
rollback;
\ir ../migrations/037_rm_web_project_route_instances.sql
select 'PASS: 037 upgrade preserves existing data, identities, RLS, ACLs, warmed receipts and pre-issued SSO permits' as result;
