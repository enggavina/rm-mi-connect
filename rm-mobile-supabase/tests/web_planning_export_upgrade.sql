\set ON_ERROR_STOP on
\if :{?rm_migration_043_path}
\else
\echo 'Run isolated suite with rm_migration_043_path.'
\quit 3
\endif
select set_config('rm.test.migration_043_path',:'rm_migration_043_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;
 if to_regprocedure('public.rm_web_planning_export_snapshot_v1(uuid[],text[])') is not null then raise exception '043 must not already be installed';end if;end$$;
insert into auth.users(id) values('ef430000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('ef430000-0000-4000-8000-000000000002','ef430000-0000-4000-8000-000000000001','Export upgrade administrator','administrador','ativo');
insert into public.rm_celulas(id,nome) values('ef430000-0000-4000-8000-000000000010','Existing upgrade cell');
insert into public.rm_projetos(id,numero,nome) values('ef430000-0000-4000-8000-000000000100','EXPORT-UPGRADE','Existing upgrade project');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,observacao) values('ef430000-0000-4000-8000-000000000500','ef430000-0000-4000-8000-000000000100','ef430000-0000-4000-8000-000000000010','coletado','Existing allocation data');
update rm_private.sso_settings set require_sso=false where singleton;
select set_config('request.jwt.claim.sub','ef430000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"ef430000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
create temporary table exu_payload(payload jsonb);
grant select on exu_payload to authenticated;
insert into exu_payload select jsonb_build_object('id',id,'expected_updated_at',updated_at,'changes',jsonb_build_object('nome','Warm project before043')) from public.rm_projetos where id='ef430000-0000-4000-8000-000000000100';
set local role authenticated;
select public.rm_web_mutate_v1('ef430000-0000-4000-8000-000000000900','save_project',(select payload from exu_payload));
select public.rm_web_project_route_snapshot_v1('ef430000-0000-4000-8000-000000000100');
reset role;
create temporary table exu_rows(identity text primary key,projection text,row_count bigint,state_hash text);
create temporary table exu_functions(id oid primary key,definition text,acl text,owner_id oid);
create temporary table exu_catalog(kind text,id text,value jsonb,primary key(kind,id));
do $$declare t record;cols text;n bigint;h text;begin
 for t in select ns.nspname,c.relname,c.oid from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and(ns.nspname in('rm_private','storage','auth') or(ns.nspname='public' and c.relname like 'rm\_%' escape '\')) loop
  select string_agg(quote_ident(attname),',' order by attnum) into cols from pg_attribute where attrelid=t.oid and attnum>0 and not attisdropped;
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %I.%I)r',cols,t.nspname,t.relname) into n,h;
  insert into exu_rows values(format('%I.%I',t.nspname,t.relname),cols,n,h);
  insert into exu_catalog select 'attribute',a.attrelid::text||':'||a.attnum,to_jsonb(a) from pg_attribute a where a.attrelid=t.oid and a.attnum>0;
  insert into exu_catalog select 'default',a.oid::text,to_jsonb(a) from pg_attrdef a where a.adrelid=t.oid;
  insert into exu_catalog select 'class',c.oid::text,to_jsonb(c)-array['relpages','reltuples','relallvisible','relallfrozen','relfrozenxid','relminmxid','relhasindex'] from pg_class c where c.oid=t.oid;
  insert into exu_catalog select 'index',i.indexrelid::text,to_jsonb(i) from pg_index i where i.indrelid=t.oid;
 end loop;
 insert into exu_functions select p.oid,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='rm_private' or(n.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into exu_catalog select 'policy',p.oid::text,to_jsonb(p) from pg_policy p;
 insert into exu_catalog select 'trigger',p.oid::text,to_jsonb(p) from pg_trigger p;
 insert into exu_catalog select 'constraint',p.oid::text,to_jsonb(p) from pg_constraint p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_043_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected043 transaction boundary';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare t record;n bigint;h text;v jsonb;begin
 for t in select * from exu_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %s)r',t.projection,t.identity) into n,h;
  if n<>t.row_count or h<>t.state_hash then raise exception 'FAIL: export migration changed old rows: %',t.identity;end if;
 end loop;
 for t in select * from exu_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and pg_get_functiondef(p.oid)=t.definition and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner_id) then raise exception 'FAIL: old function/owner/ACL changed: %',t.id;end if;
 end loop;
 for t in select * from exu_catalog loop
  case t.kind
   when 'policy' then select to_jsonb(x) into v from pg_policy x where x.oid=t.id::oid;
   when 'trigger' then select to_jsonb(x) into v from pg_trigger x where x.oid=t.id::oid;
   when 'constraint' then select to_jsonb(x) into v from pg_constraint x where x.oid=t.id::oid;
   when 'default' then select to_jsonb(x) into v from pg_attrdef x where x.oid=t.id::oid;
   when 'index' then select to_jsonb(x) into v from pg_index x where x.indexrelid=t.id::oid;
   when 'class' then select to_jsonb(x)-array['relpages','reltuples','relallvisible','relallfrozen','relfrozenxid','relminmxid','relhasindex'] into v from pg_class x where x.oid=t.id::oid;
   when 'attribute' then select to_jsonb(x) into v from pg_attribute x where x.attrelid=split_part(t.id,':',1)::oid and x.attnum=split_part(t.id,':',2)::smallint;
  end case;
  if v is distinct from t.value then raise exception 'FAIL: old catalog tuple changed: % %',t.kind,t.id;end if;
 end loop;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where(n.nspname='rm_private' or(n.nspname='public' and p.proname like 'rm\_%' escape '\')) and not exists(select 1 from exu_functions f where f.id=p.oid))<>3 then raise exception 'FAIL: expected only three new export functions';end if;
 if(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where(n.nspname='rm_private' or(n.nspname='public' and p.proname like 'rm\_%' escape '\')) and not exists(select 1 from exu_functions f where f.id=p.oid) and p.proname not in('web_planning_export_allowed_v1','web_export_shared_equipment_v1','rm_web_planning_export_snapshot_v1'))<>0 then raise exception 'FAIL: unexpected export function';end if;
end$$;
set local role authenticated;
do $$declare result jsonb;begin
 result:=public.rm_web_mutate_v1('ef430000-0000-4000-8000-000000000900','save_project',(select payload from exu_payload));
 if result->>'idempotent_replay'<>'true' then raise exception 'FAIL: pre043 receipt cannot replay';end if;
 result:=public.rm_web_planning_export_snapshot_v1(array['ef430000-0000-4000-8000-000000000010']::uuid[],array['project_number','allocation_status']);
 if result->>'row_count'<>'1' or result->'cells'->0->'rows'->0->'values'->>'allocation_status'<>'Coletado' then raise exception 'FAIL: export unavailable after warmed upgrade';end if;
end$$;
reset role;
do $$declare t record;n bigint;h text;begin
 for t in select * from exu_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from(select %s from %s)r',t.projection,t.identity) into n,h;
  if n<>t.row_count or h<>t.state_hash then raise exception 'FAIL: read-only export or warm replay changed old data: %',t.identity;end if;
 end loop;
end$$;
rollback;
\i :rm_migration_043_path
select 'PASS: 043 preserves all pre-existing RM/private/auth/Storage rows, functions/OIDs/owners/ACLs, catalogs, policies, triggers, defaults, indices and warm receipt replay' result;
