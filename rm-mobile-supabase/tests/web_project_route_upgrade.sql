-- TEST DATABASE ONLY: 023 -> 024 preserves every row and warmed dispatchers.
\set ON_ERROR_STOP on
begin;
create schema rm_test_route_upgrade;
create table rm_test_route_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1a600000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values('2a600000-0000-4000-8000-000000000001','1a600000-0000-4000-8000-000000000001','Route upgrade planner','administrador');
insert into public.rm_projetos(id,numero) values('5a600000-0000-4000-8000-000000000001','ROUTE-UPGRADE-24');
insert into public.rm_celulas(id,nome) values('4a600000-0000-4000-8000-000000000001','Route upgrade first'),('4a600000-0000-4000-8000-000000000002','Route upgrade second');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,indice,posicao,prioridade,visibilidade)
 values('6a600000-0000-4000-8000-000000000001','5a600000-0000-4000-8000-000000000001','4a600000-0000-4000-8000-000000000001',81,17,'alta',false),
 ('6a600000-0000-4000-8000-000000000002','5a600000-0000-4000-8000-000000000001','4a600000-0000-4000-8000-000000000002',null,7,'baixa',true);
insert into public.rm_cadastro_fotos(id,titulo) values('ca600000-0000-4000-8000-000000000001','Route warm title');
select set_config('request.jwt.claim.sub','1a600000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
do $$ declare p jsonb; begin
 select jsonb_build_object('id',id,'expected_updated_at',updated_at) into p from public.rm_cadastro_fotos where id='ca600000-0000-4000-8000-000000000001';
 set local role authenticated; perform public.rm_web_mutate_v1('fa600000-0000-4000-8000-000000000001','delete_photo_title',p); reset role;
end $$;
do $$ declare t record; total bigint; digest text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname) into total,digest;
  insert into rm_test_route_upgrade.snapshots values(t.nspname||'.'||t.relname,total,digest);
 end loop;
 if (select count(*) from rm_test_route_upgrade.snapshots where split_part(name,'.',1)='public')<>56
  or (select count(*) from rm_test_route_upgrade.snapshots where split_part(name,'.',1)='rm_private')<>11
  or (select count(*) from rm_test_route_upgrade.snapshots)<>67 then raise exception 'FAIL: expected all 67 RM/private snapshots'; end if;
 if to_regprocedure('rm_private.web_mutate_photo_title_core_v1(uuid,text,jsonb)') is not null then raise exception 'FAIL: predecessor name unavailable'; end if;
end $$;
commit;
\ir ../migrations/024_rm_web_project_route.sql
begin;
do $$ declare t record; total bigint; digest text; p jsonb; r jsonb; s jsonb; before_rows jsonb; after_rows jsonb; begin
 for t in select * from rm_test_route_upgrade.snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name) into total,digest;
  if total<>t.rows or digest<>t.hash then raise exception 'FAIL: route installation changed old rows: %',t.name; end if;
 end loop;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fa600000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fa600000-0000-4000-8000-000000000001','delete_photo_title',p); reset role;
 if not (r->>'idempotent_replay')::boolean then raise exception 'FAIL: warm 023 replay'; end if;
 s:=public.rm_web_project_route_snapshot_v1('5a600000-0000-4000-8000-000000000001');
 if (s->'items'->0->>'indice')::int<>81 or s->'items'->1->'indice'<>'null' then raise exception 'FAIL: read normalized legacy indices'; end if;
 select jsonb_build_object('projeto_id',s->'project'->>'id','expected_project_updated_at',s->'project'->>'updated_at',
  'expected_route_version',s->>'route_version','items',jsonb_agg(jsonb_build_object('id',i->>'id','expected_updated_at',i->>'updated_at') order by ordinality))
  into p from jsonb_array_elements(s->'items') with ordinality x(i,ordinality);
 select jsonb_agg(to_jsonb(a) order by id) into before_rows from public.rm_celulas_projeto a where projeto_id='5a600000-0000-4000-8000-000000000001';
 set local role authenticated; r:=public.rm_web_mutate_v1('fa600000-0000-4000-8000-000000000002','save_project_route',p); reset role;
 if r->>'operation'<>'save_project_route' or jsonb_array_length(r->'record'->'changed_ids')<>2 then raise exception 'FAIL: warm wrapper missed route dispatcher'; end if;
 select jsonb_agg(to_jsonb(a) order by id) into after_rows from public.rm_celulas_projeto a where projeto_id='5a600000-0000-4000-8000-000000000001';
 if (select array_agg(indice order by id) from public.rm_celulas_projeto where projeto_id='5a600000-0000-4000-8000-000000000001')<>array[1,2]
  or (select array_agg(posicao order by id) from public.rm_celulas_projeto where projeto_id='5a600000-0000-4000-8000-000000000001')<>array[17,7] then raise exception 'FAIL: route order mixed with queue'; end if;
 set local role authenticated; r:=public.rm_web_mutate_v1('fa600000-0000-4000-8000-000000000002','save_project_route',p); reset role;
 if not (r->>'idempotent_replay')::boolean or after_rows is distinct from (select jsonb_agg(to_jsonb(a) order by id) from public.rm_celulas_projeto a where projeto_id='5a600000-0000-4000-8000-000000000001') then raise exception 'FAIL: warm route replay changes rows'; end if;
end $$;
rollback;
begin;
delete from rm_private.web_mutation_receipts where client_submission_id='fa600000-0000-4000-8000-000000000001';
delete from public.rm_celulas_projeto where projeto_id='5a600000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5a600000-0000-4000-8000-000000000001';
delete from public.rm_celulas where id in('4a600000-0000-4000-8000-000000000001','4a600000-0000-4000-8000-000000000002');
delete from public.rm_users where id='2a600000-0000-4000-8000-000000000001';
delete from auth.users where id='1a600000-0000-4000-8000-000000000001';
commit;
select 'PASS: 024 preserves 67 complete snapshots; warmed 023 wrapper reaches old/new commands and exact replay without changing queue order' as result;
