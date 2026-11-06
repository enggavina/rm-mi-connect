\set ON_ERROR_STOP on
\if :{?rm_migration_039_path}
\else
\echo 'Run through isolated runner with rm_migration_039_path.'
\quit 3
\endif
select set_config('rm.test.migration_039_path',:'rm_migration_039_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
create function pg_temp.pd_upgrade_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
insert into auth.users(id) values('1f390000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2f390000-0000-4000-8000-000000000001','1f390000-0000-4000-8000-000000000001','Delete upgrade administrator','administrador','ativo');
insert into auth.sessions(id,user_id) values('3f390000-0000-4000-8000-000000000001','1f390000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values('8f390000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9f390000-0000-4000-8000-000000000001','2f390000-0000-4000-8000-000000000001','1f390000-0000-4000-8000-000000000001',true,'2f390000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('39',32),'8f390000-0000-4000-8000-000000000001','3f390000-0000-4000-8000-000000000001','opaque-project-deletion-upgrade',clock_timestamp()+interval '45 minutes');
insert into public.rm_projetos(id,nome) values('5f390000-0000-4000-8000-000000000001','Legacy upgrade project'),('5f390000-0000-4000-8000-000000000002','Explicit deletion fixture');
insert into public.rm_celulas(id,nome) values('4f390000-0000-4000-8000-000000000001','Upgrade cell');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,indice) values('6f390000-0000-4000-8000-000000000001','5f390000-0000-4000-8000-000000000001','4f390000-0000-4000-8000-000000000001',1);
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','1f390000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"3f390000-0000-4000-8000-000000000001","aal":"aal1"}',true);
create temporary table pd_upgrade_payload(id uuid,payload jsonb);
grant select on pd_upgrade_payload to authenticated;
insert into pd_upgrade_payload select 'ef390000-0000-4000-8000-000000000001',jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Warm operation before 039')) from public.rm_celulas_projeto where id='6f390000-0000-4000-8000-000000000001';
select public.rm_sso_action_permit_v1(repeat('39',32),'ef390000-0000-4000-8000-000000000001','plan_cell',(select payload from pd_upgrade_payload),'em.planning.manage');
set local role authenticated;
select public.rm_web_mutate_v1('ef390000-0000-4000-8000-000000000001','plan_cell',(select payload from pd_upgrade_payload));
reset role;
select public.rm_sso_action_permit_v1(repeat('39',32),'ef390000-0000-4000-8000-000000000001','plan_cell',(select payload from pd_upgrade_payload),'em.planning.manage');
insert into pd_upgrade_payload select 'ef390000-0000-4000-8000-000000000002',jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Permit issued before 039')) from public.rm_celulas_projeto where id='6f390000-0000-4000-8000-000000000001';
select public.rm_sso_action_permit_v1(repeat('39',32),'ef390000-0000-4000-8000-000000000002','plan_cell',(select payload from pd_upgrade_payload where id='ef390000-0000-4000-8000-000000000002'),'em.planning.manage');
create temporary table pd_upgrade_rows(name text primary key,projection text,rows bigint,hash text);
create temporary table pd_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table pd_upgrade_catalog(kind text,id oid,value jsonb,primary key(kind,id));
do $$declare t record;cols text;n bigint;h text;begin
 for t in select ns.nspname,c.relname,c.oid from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and(ns.nspname='rm_private' or(ns.nspname='public' and c.relname like 'rm\_%' escape '\') or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  select string_agg(quote_ident(attname),',' order by attnum) into cols from pg_attribute where attrelid=t.oid and attnum>0 and not attisdropped;
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %I.%I) r',cols,t.nspname,t.relname) into n,h;
  insert into pd_upgrade_rows values(format('%I.%I',t.nspname,t.relname),cols,n,h);
 end loop;
 insert into pd_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into pd_upgrade_catalog select 'policy',p.oid,to_jsonb(p) from pg_policy p;
 insert into pd_upgrade_catalog select 'trigger',p.oid,to_jsonb(p) from pg_trigger p;
 insert into pd_upgrade_catalog select 'constraint',p.oid,to_jsonb(p) from pg_constraint p where p.conname<>'sso_action_permits_operation_check';
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_039_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected migration boundary';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare t record;n bigint;h text;expected text;begin
 for t in select * from pd_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %s) r',t.projection,t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: installation rewrote old data: %',t.name;end if;
 end loop;
 for t in select * from pd_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner) then raise exception 'FAIL: old function OID/ACL/owner changed: %',t.name;end if;
  expected:=t.definition;
  if t.name='web_mutate_core_v1' then expected:=replace(expected,'CREATE OR REPLACE FUNCTION rm_private.web_mutate_core_v1(','CREATE OR REPLACE FUNCTION rm_private.web_mutate_before_project_delete_v1(');end if;
  if t.name not in('guard_cell_availability_v1','guard_operational_stage_identity_v1','assert_allocation_available_v1','rm_mobile_mutate_v1','rm_sso_action_permit_v1') and pg_get_functiondef(t.id) is distinct from expected then raise exception 'FAIL: unrelated function changed: %',t.name;end if;
 end loop;
 if exists(select 1 from pd_upgrade_catalog c where c.kind='policy' and not exists(select 1 from pg_policy p where p.oid=c.id and to_jsonb(p)=c.value))
  or exists(select 1 from pd_upgrade_catalog c where c.kind='trigger' and not exists(select 1 from pg_trigger p where p.oid=c.id and to_jsonb(p)=c.value))
  or exists(select 1 from pd_upgrade_catalog c where c.kind='constraint' and not exists(select 1 from pg_constraint p where p.oid=c.id and to_jsonb(p)=c.value)) then raise exception 'FAIL: old catalog contract changed';end if;
end$$;
set local role authenticated;
select pg_temp.pd_upgrade_check((public.rm_web_mutate_v1('ef390000-0000-4000-8000-000000000001','plan_cell',(select payload from pd_upgrade_payload where id='ef390000-0000-4000-8000-000000000001'))->>'idempotent_replay')::boolean,'warm pre-DDL receipt replays');
select public.rm_web_mutate_v1('ef390000-0000-4000-8000-000000000002','plan_cell',(select payload from pd_upgrade_payload where id='ef390000-0000-4000-8000-000000000002'));
reset role;
do $$declare s jsonb;p jsonb;rid uuid:='ef390000-0000-4000-8000-000000000003';begin
 s:=public.rm_web_project_delete_snapshot_v1('5f390000-0000-4000-8000-000000000002');
 p:=jsonb_build_object('id',s->'project'->>'id','expected_updated_at',s->'project'->>'updated_at','expected_context_version',s->>'context_version','confirm_delete',true,'justificativa','Explicit upgrade test');
 set local role authenticated;
 begin perform public.rm_web_mutate_v1(rid,'delete_project',p);raise exception 'FAIL: missing permit accepted';exception when insufficient_privilege then null;end;
 reset role;
 begin perform public.rm_sso_action_permit_v1(repeat('39',32),rid,'delete_project',p,'em.planning.manage');raise exception 'FAIL: wrong capability accepted';exception when invalid_parameter_value then null;end;
 perform public.rm_sso_action_permit_v1(repeat('39',32),rid,'delete_project',p,'em.projects.manage');
 set local role authenticated;
 perform public.rm_web_mutate_v1(rid,'delete_project',p);
 reset role;
 perform pg_temp.pd_upgrade_check(not exists(select 1 from public.rm_projetos where id='5f390000-0000-4000-8000-000000000002'),'new operation works through SSO after warm upgrade');
end$$;
rollback;
\i :rm_migration_039_path
select 'PASS: 038 to 039 preserves all old rows/OIDs/ACLs/triggers/policies/constraints, warm receipts and pre-DDL permits; new delete requires correct SSO permit' result;
