\set ON_ERROR_STOP on
\if :{?rm_migration_038_path}
\else
\echo 'Run through isolated runner with rm_migration_038_path.'
\quit 3
\endif
select set_config('rm.test.migration_038_path',:'rm_migration_038_path',false);
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable database required'; end if; end $$;
insert into auth.users(id) values('1ff38000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2ff38000-0000-4000-8000-000000000001','1ff38000-0000-4000-8000-000000000001','Audit upgrade actor fixture','administrador','ativo');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1ff38000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create temporary table audit_upgrade_payload(payload jsonb);
grant select on audit_upgrade_payload to authenticated;
insert into public.rm_projetos(id,nome) values('5ff38000-0000-4000-8000-000000000001','Existing audit upgrade fixture');
insert into public.rm_equipamentos(id,projeto_id,descricao) values('6ff38000-0000-4000-8000-000000000001','5ff38000-0000-4000-8000-000000000001','Existing equipment');
update public.rm_projetos set equipamento_id='6ff38000-0000-4000-8000-000000000001' where id='5ff38000-0000-4000-8000-000000000001';
insert into audit_upgrade_payload select jsonb_build_object('id','5ff38000-0000-4000-8000-000000000001',
 'expected_updated_at',s->'project'->>'updated_at','changes',jsonb_build_object('nome','Audit upgrade warm fixture'),
 'equipment',jsonb_build_object('id','6ff38000-0000-4000-8000-000000000001','expected_updated_at',s->'equipment'->>'updated_at',
  'expected_context_version',s->>'context_version','changes',jsonb_build_object('descricao','Updated existing equipment')))
 from(select public.rm_web_project_equipment_snapshot_v1('5ff38000-0000-4000-8000-000000000001') s) snapshot;
set local role authenticated;
select public.rm_web_mutate_v1('aff38000-0000-4000-8000-000000000001','save_project_with_equipment',(select payload from audit_upgrade_payload));
reset role;
create temporary table audit_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table audit_upgrade_functions(id oid primary key,definition text,acl text,owner oid);
create temporary table audit_upgrade_catalogs(name text,id oid,value jsonb,primary key(name,id));
do $$ declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r'
  and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or(ns.nspname='storage' and c.relname in('buckets','objects'))) loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into audit_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into audit_upgrade_functions select p.oid,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into audit_upgrade_catalogs select 'pg_policy',p.oid,to_jsonb(p) from pg_policy p;
 insert into audit_upgrade_catalogs select 'pg_trigger',p.oid,to_jsonb(p) from pg_trigger p;
 insert into audit_upgrade_catalogs select 'pg_constraint',p.oid,to_jsonb(p) from pg_constraint p;
 insert into audit_upgrade_catalogs select 'pg_class',c.oid,to_jsonb(c)-array['relpages','reltuples','relallvisible','relallfrozen','relfrozenxid','relminmxid','relhasindex']
  from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and(ns.nspname='rm_private' or(ns.nspname='public' and c.relname like 'rm\_%' escape '\'));
end $$;
do $$ declare source text:=pg_read_file(current_setting('rm.test.migration_038_path')); begin
 if (select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or (select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Migration transaction structure mismatch'; end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end $$;
do $$ declare t record;n bigint;h text;v jsonb;begin
 for t in select * from audit_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',t.name) into n,h;
  if n<>t.rows or h<>t.hash then raise exception 'FAIL: audit installation changed rows: %',t.name;end if;
 end loop;
 for t in select * from audit_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=t.id and pg_get_functiondef(p.oid)=t.definition and coalesce(p.proacl::text,'')=t.acl and p.proowner=t.owner)
   then raise exception 'FAIL: old function/ACL changed: %',t.id;end if;
 end loop;
 for t in select * from audit_upgrade_catalogs loop
  if t.name='pg_class' then
   select to_jsonb(c)-array['relpages','reltuples','relallvisible','relallfrozen','relfrozenxid','relminmxid','relhasindex'] into v from pg_class c where c.oid=t.id;
  else execute format('select to_jsonb(c) from pg_catalog.%I c where c.oid=$1',t.name) into v using t.id;end if;
  if v is distinct from t.value then raise exception 'FAIL: existing catalog changed: % %',t.name,t.id;end if;
 end loop;
end $$;
set local role authenticated;
do $$ declare r jsonb;begin
 r:=public.rm_web_mutate_v1('aff38000-0000-4000-8000-000000000001','save_project_with_equipment',(select payload from audit_upgrade_payload));
 if not(r->>'idempotent_replay')::boolean then raise exception 'FAIL: warmed receipt cannot replay after audit upgrade';end if;
 if public.rm_web_project_audit_v1('5ff38000-0000-4000-8000-000000000001','cells')->>'total'<>'0' then raise exception 'FAIL: legacy route audit invented';end if;
end $$;
reset role;
rollback;
\ir ../migrations/038_rm_web_project_audit.sql
\echo Project audit upgrade preserves existing rows, functions, ACLs, policies, triggers, constraints and warmed receipts
