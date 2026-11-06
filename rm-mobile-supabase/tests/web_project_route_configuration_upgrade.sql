\set ON_ERROR_STOP on
\if :{?rm_migration_040_path}
\else
\echo 'Run through isolated runner with rm_migration_040_path.'
\quit 3
\endif
select set_config('rm.test.migration_040_path',:'rm_migration_040_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required';end if;end$$;
create function pg_temp.rc_upgrade_check(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL: %',msg;end if;end$$;
insert into auth.users(id) values('1f400000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2f400000-0000-4000-8000-000000000001','1f400000-0000-4000-8000-000000000001','Route upgrade planner','administrador','ativo');
insert into auth.sessions(id,user_id) values('3f400000-0000-4000-8000-000000000001','1f400000-0000-4000-8000-000000000001');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values('8f400000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9f400000-0000-4000-8000-000000000001','2f400000-0000-4000-8000-000000000001','1f400000-0000-4000-8000-000000000001',true,'2f400000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('40',32),'8f400000-0000-4000-8000-000000000001','3f400000-0000-4000-8000-000000000001','opaque-route-configuration-upgrade',clock_timestamp()+interval '45 minutes');
insert into public.rm_projetos(id,nome) values('5f400000-0000-4000-8000-000000000001','Legacy upgrade project');
insert into public.rm_celulas(id,nome) values('4f400000-0000-4000-8000-000000000001','Upgrade route origin'),('4f400000-0000-4000-8000-000000000002','Upgrade route destination');
insert into public.rm_forms(id,titulo) values('7f400000-0000-4000-8000-000000000001','Existing linked form'),('7f400000-0000-4000-8000-000000000002','Unused new form');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,forms_ids,indice) values('6f400000-0000-4000-8000-000000000001','5f400000-0000-4000-8000-000000000001','4f400000-0000-4000-8000-000000000001',array['7f400000-0000-4000-8000-000000000001']::uuid[],1),('6f400000-0000-4000-8000-000000000002','5f400000-0000-4000-8000-000000000001','4f400000-0000-4000-8000-000000000002','{}',2);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_origem_id,celula_destino_id,status) values('cf400000-0000-4000-8000-000000000001','5f400000-0000-4000-8000-000000000001','6f400000-0000-4000-8000-000000000001','4f400000-0000-4000-8000-000000000001','4f400000-0000-4000-8000-000000000002','aprovado'),('cf400000-0000-4000-8000-000000000002','5f400000-0000-4000-8000-000000000001','6f400000-0000-4000-8000-000000000001','4f400000-0000-4000-8000-000000000001','4f400000-0000-4000-8000-000000000002','nulo');
update rm_private.sso_settings set require_sso=true;
select set_config('request.jwt.claim.sub','1f400000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"3f400000-0000-4000-8000-000000000001","aal":"aal1"}',true);
create temporary table rc_upgrade_payload(id uuid,payload jsonb);
grant select on rc_upgrade_payload to authenticated;
insert into rc_upgrade_payload select 'ef400000-0000-4000-8000-000000000001',jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Warm existing operation')) from public.rm_celulas_projeto where id='6f400000-0000-4000-8000-000000000001';
select public.rm_sso_action_permit_v1(repeat('40',32),'ef400000-0000-4000-8000-000000000001','plan_cell',(select payload from rc_upgrade_payload),'em.planning.manage');
set local role authenticated;
select public.rm_web_mutate_v1('ef400000-0000-4000-8000-000000000001','plan_cell',(select payload from rc_upgrade_payload));
reset role;
select public.rm_sso_action_permit_v1(repeat('40',32),'ef400000-0000-4000-8000-000000000001','plan_cell',(select payload from rc_upgrade_payload),'em.planning.manage');
insert into rc_upgrade_payload select 'ef400000-0000-4000-8000-000000000002',jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,'changes',jsonb_build_object('observacao','Permit issued before DDL')) from public.rm_celulas_projeto where id='6f400000-0000-4000-8000-000000000001';
select public.rm_sso_action_permit_v1(repeat('40',32),'ef400000-0000-4000-8000-000000000002','plan_cell',(select payload from rc_upgrade_payload where id='ef400000-0000-4000-8000-000000000002'),'em.planning.manage');
create temporary table rc_upgrade_rows(name text primary key,projection text,rows bigint,hash text);
create temporary table rc_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table rc_upgrade_catalog(kind text,id oid,value jsonb,primary key(kind,id));
do $$declare t record;cols text;n bigint;h text;begin
 for t in select ns.nspname,c.relname,c.oid from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and(ns.nspname='rm_private' or(ns.nspname='public' and c.relname like 'rm\_%' escape '\') or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  select string_agg(quote_ident(attname),',' order by attnum) into cols from pg_attribute where attrelid=t.oid and attnum>0 and not attisdropped;
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %I.%I) r',cols,t.nspname,t.relname) into n,h;
  insert into rc_upgrade_rows values(format('%I.%I',t.nspname,t.relname),cols,n,h);
 end loop;
 insert into rc_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into rc_upgrade_catalog select 'policy',p.oid,to_jsonb(p) from pg_policy p;
 insert into rc_upgrade_catalog select 'trigger',p.oid,to_jsonb(p) from pg_trigger p;
 insert into rc_upgrade_catalog select 'constraint',p.oid,to_jsonb(p) from pg_constraint p where p.conname<>'sso_action_permits_operation_check';
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_040_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected migration boundary';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare t record;n bigint;h text;expected text;begin
 for t in select * from rc_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %s) r',t.projection,t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: installation rewrote old data: %',t.name;end if;
 end loop;
 for t in select * from rc_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner) then raise exception 'FAIL: old function OID/ACL/owner changed: %',t.name;end if;
  expected:=t.definition;
  if t.name='web_mutate_core_v1' then expected:=replace(expected,'CREATE OR REPLACE FUNCTION rm_private.web_mutate_core_v1(','CREATE OR REPLACE FUNCTION rm_private.web_mutate_before_route_config_v1(');end if;
  if t.name not in('stage_rule_metadata_v1','rm_web_operational_photos_snapshot_v1','rm_web_project_route_snapshot_v1','project_audit_events_v1','rm_sso_action_permit_v1') and pg_get_functiondef(t.id) is distinct from expected then raise exception 'FAIL: unrelated function changed: %',t.name;end if;
 end loop;
 if exists(select 1 from rc_upgrade_catalog c where c.kind='policy' and not exists(select 1 from pg_policy p where p.oid=c.id and to_jsonb(p)=c.value))
  or exists(select 1 from rc_upgrade_catalog c where c.kind='trigger' and not exists(select 1 from pg_trigger p where p.oid=c.id and to_jsonb(p)=c.value))
  or exists(select 1 from rc_upgrade_catalog c where c.kind='constraint' and not exists(select 1 from pg_constraint p where p.oid=c.id and to_jsonb(p)=c.value)) then raise exception 'FAIL: old catalog contract changed';end if;
 perform pg_temp.rc_upgrade_check((select not configuracao_utilizada from public.rm_aprovacoes_etapas where id='cf400000-0000-4000-8000-000000000001'),'legacy approved row not backfilled on installation');
 update public.rm_aprovacoes_etapas set status='nulo',aprovado_por_id=null,data_aprovacao=null where id='cf400000-0000-4000-8000-000000000001';
 perform pg_temp.rc_upgrade_check((select configuracao_utilizada from public.rm_aprovacoes_etapas where id='cf400000-0000-4000-8000-000000000001'),'first status reset seals legacy evidence');
 perform pg_temp.rc_upgrade_check((select not configuracao_utilizada from public.rm_aprovacoes_etapas where id='cf400000-0000-4000-8000-000000000002'),'unused rule stays editable');
end$$;
set local role authenticated;
select pg_temp.rc_upgrade_check((public.rm_web_mutate_v1('ef400000-0000-4000-8000-000000000001','plan_cell',(select payload from rc_upgrade_payload where id='ef400000-0000-4000-8000-000000000001'))->>'idempotent_replay')::boolean,'warm pre-DDL receipt replays');
select public.rm_web_mutate_v1('ef400000-0000-4000-8000-000000000002','plan_cell',(select payload from rc_upgrade_payload where id='ef400000-0000-4000-8000-000000000002'));
reset role;
do $$declare s jsonb;p jsonb;rid uuid:='ef400000-0000-4000-8000-000000000003';begin
 s:=public.rm_web_project_route_cell_snapshot_v1('5f400000-0000-4000-8000-000000000001','6f400000-0000-4000-8000-000000000001',true);
 p:=jsonb_build_object('action','forms','projeto_id','5f400000-0000-4000-8000-000000000001','celula_projeto_id','6f400000-0000-4000-8000-000000000001','expected_project_updated_at',s->'project'->>'updated_at','expected_allocation_updated_at',s->'allocation'->>'updated_at','expected_context_version',s->>'context_version','confirm_change',true,'forms_ids',jsonb_build_array('7f400000-0000-4000-8000-000000000001','7f400000-0000-4000-8000-000000000002'));
 set local role authenticated;
 begin perform public.rm_web_mutate_v1(rid,'manage_project_route_cell',p);raise exception 'FAIL: missing permit accepted';exception when insufficient_privilege then null;end;
 reset role;
 begin perform public.rm_sso_action_permit_v1(repeat('40',32),rid,'manage_project_route_cell',p,'em.projects.manage');raise exception 'FAIL: wrong capability accepted';exception when invalid_parameter_value then null;end;
 perform public.rm_sso_action_permit_v1(repeat('40',32),rid,'manage_project_route_cell',p,'em.planning.manage');
 set local role authenticated;
 perform public.rm_web_mutate_v1(rid,'manage_project_route_cell',p);
 reset role;
 perform pg_temp.rc_upgrade_check((select cardinality(forms_ids)=2 from public.rm_celulas_projeto where id='6f400000-0000-4000-8000-000000000001'),'new operation works through SSO after warm upgrade despite another resource used');
end$$;
rollback;
\i :rm_migration_040_path
select 'PASS: 039 to 040 preserves old data/contracts, warm receipts/permits, seals legacy decision reset and enforces new SSO capability' result;
