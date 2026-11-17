\set ON_ERROR_STOP on
\if :{?rm_migration_052_path}
\else
\echo 'Isolated runner must supply migration052 path.'
\quit 3
\endif
select set_config('rm.test.migration_052_path',:'rm_migration_052_path',false);
begin;
do $$begin if current_database()<>'rmmi_test' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback database required';end if;end$$;
insert into auth.users(id) values('1b052000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values('2b052000-0000-4000-8000-000000000001','1b052000-0000-4000-8000-000000000001','Receiving upgrade actor','administrador','ativo');
insert into public.rm_clientes(id,nome) values('4b052000-0000-4000-8000-000000000001','Receiving upgrade client');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values
 (extensions.digest('receiving-upgrade-token','sha256'),'1b052000-0000-4000-8000-000000000001','2b052000-0000-4000-8000-000000000001','2b052000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day');
select set_config('request.jwt.claim.sub','1b052000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
create function pg_temp.receiving_warmed_mobile(id uuid,p jsonb) returns jsonb language plpgsql as $$begin return public.rm_mobile_mutate_v1(id,'rm_submit_recebimento_v1',p,'receiving-upgrade-token');end$$;
create function pg_temp.receiving_upgrade_params(id uuid) returns jsonb language sql as $$select jsonb_build_object('p_cliente_id','4b052000-0000-4000-8000-000000000001','p_fotos_recebimento','[]'::jsonb,
 'p_receiving_draft_id',id,'p_receiving_draft_revision',0,'p_receiving_draft_snapshot',jsonb_build_object('id',id,'version',2,'submitted',false));$$;
set local role authenticated;
select pg_temp.receiving_warmed_mobile('7b052000-0000-4000-8000-000000000001',pg_temp.receiving_upgrade_params('7b052000-0000-4000-8000-000000000001'));
reset role;
create temporary table receiving_upgrade_rows(name text primary key,rows bigint,hash text);
create temporary table receiving_upgrade_functions(id oid primary key,name text,definition text,acl text,owner oid);
create temporary table receiving_upgrade_policies(id oid primary key,value jsonb);
do $$declare t record;n bigint;h text;begin
 for t in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace where c.relkind='r' and((ns.nspname='public' and c.relname like 'rm\_%' escape '\') or ns.nspname='rm_private' or ns.nspname='storage') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %I.%I r',t.nspname,t.relname) into n,h;
  insert into receiving_upgrade_rows values(format('%I.%I',t.nspname,t.relname),n,h);
 end loop;
 insert into receiving_upgrade_functions select p.oid,p.proname,pg_get_functiondef(p.oid),coalesce(p.proacl::text,''),p.proowner from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='rm_private' or(ns.nspname='public' and p.proname like 'rm\_%' escape '\');
 insert into receiving_upgrade_policies select p.oid,to_jsonb(p) from pg_policy p;
end$$;
do $$declare source text:=pg_read_file(current_setting('rm.test.migration_052_path'));begin
 if(select count(*) from regexp_matches(source,'(?m)^begin;\s*\r?\n','g'))<>1 or(select count(*) from regexp_matches(source,'(?m)^commit;\s*$','g'))<>1 then raise exception 'Unexpected052 wrappers';end if;
 source:=regexp_replace(source,'(?m)^begin;\s*\r?\n','');source:=regexp_replace(source,'(?m)^commit;\s*$','');execute source;
end$$;
do $$declare item record;n bigint;h text;begin
 for item in select * from receiving_upgrade_rows loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,''[]'')) from %s r',item.name) into n,h;
  if n<>item.rows or h<>item.hash then raise exception 'FAIL: receiving upgrade changed old rows: %',item.name;end if;
 end loop;
 if exists(select 1 from receiving_upgrade_policies x where not exists(select 1 from pg_policy p where p.oid=x.id and to_jsonb(p)=x.value)) then raise exception 'FAIL: receiving upgrade changed old RLS';end if;
 for item in select * from receiving_upgrade_functions loop
  if not exists(select 1 from pg_proc p where p.oid=item.id and coalesce(p.proacl::text,'')=item.acl and p.proowner=item.owner) then raise exception 'FAIL: receiving upgrade changed OID/ACL/owner: %',item.name;end if;
  if item.name not in('mobile_mutate_before_execution_v1','rm_mobile_mutate_v1','rm_receiving_draft_v1','project_route_state_v1') and pg_get_functiondef(item.id)<>item.definition then raise exception 'FAIL: unrelated function changed: %',item.name;end if;
 end loop;
 if exists(select 1 from rm_private.receiving_openings) then raise exception 'FAIL: opening install generated effective rows';end if;
end$$;
set local role authenticated;
do $$declare p jsonb;r jsonb;early jsonb;begin
 p:=pg_temp.receiving_upgrade_params('7b052000-0000-4000-8000-000000000001');
 r:=pg_temp.receiving_warmed_mobile('7b052000-0000-4000-8000-000000000001',p);
 if r->>'idempotent_replay'<>'true' then raise exception 'FAIL: warmed legacy receipt lost';end if;
 p:=pg_temp.receiving_upgrade_params('7b052000-0000-4000-8000-000000000002');
 early:=public.rm_mobile_open_receiving_v1('7b052000-0000-4000-8000-000000000002',p,'receiving-upgrade-token');
 r:=pg_temp.receiving_warmed_mobile('7b052000-0000-4000-8000-000000000002',p);
 if r->>'projeto_id'<>early->>'projeto_id' then raise exception 'FAIL: warmed gateway failed binding';end if;
end$$;
reset role;
rollback;
\i :rm_migration_052_path
select 'PASS: 052 preserves old rows/OIDs/ACLs/owners/RLS and warmed legacy/mobile receiving protocols without install DML' result;
