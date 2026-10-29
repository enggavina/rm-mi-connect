-- TEST DATABASE ONLY: additive 021 -> 022 upgrade with a warmed public wrapper.
\set ON_ERROR_STOP on
begin;
create schema rm_test_photo_upgrade;
create table rm_test_photo_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1a300000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values('2a300000-0000-4000-8000-000000000001','1a300000-0000-4000-8000-000000000001','Photo upgrade fixture','administrador');
insert into public.rm_projetos(id,numero) values('5a300000-0000-4000-8000-000000000001','PHOTO-UPGRADE-22');
insert into public.rm_fotos(id,projeto_id,foto_url,numero,tag,sync_source)
 values('6a300000-0000-4000-8000-000000000001','5a300000-0000-4000-8000-000000000001',
  'https://example.invalid/upgrade.jpg',48,'UPGRADE','bubble');
select set_config('request.jwt.claim.sub','1a300000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
do $$ declare p jsonb; begin
 select jsonb_build_object('id',id,'expected_updated_at',updated_at,'changes',jsonb_build_object('nome','Warm photo project'))
  into p from public.rm_projetos where id='5a300000-0000-4000-8000-000000000001';
 set local role authenticated;
 perform public.rm_web_mutate_v1('fa300000-0000-4000-8000-000000000001','save_project',p);
 reset role;
end $$;
do $$ declare t record; total bigint; digest text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname)
   into total,digest;
  insert into rm_test_photo_upgrade.snapshots values(t.nspname||'.'||t.relname,total,digest);
 end loop;
 if (select count(*) from rm_test_photo_upgrade.snapshots where split_part(name,'.',1)='public')<>56
  or (select count(*) from rm_test_photo_upgrade.snapshots where split_part(name,'.',1)='rm_private')<>11
  or (select count(*) from rm_test_photo_upgrade.snapshots)<>67 then
  raise exception 'FAIL: expected snapshots of all 56 public and 11 private tables'; end if;
 if to_regprocedure('rm_private.web_mutate_pcp_core_v1(uuid,text,jsonb)') is not null then
  raise exception 'FAIL: reserved predecessor name already exists before 022'; end if;
end $$;
commit;
\ir ../migrations/022_rm_web_project_photo_selection.sql
begin;
do $$ declare t record; total bigint; digest text; p jsonb; r jsonb; before_row jsonb; after_row jsonb; begin
 for t in select * from rm_test_photo_upgrade.snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name)
   into total,digest;
  if total<>t.rows or digest<>t.hash then raise exception 'FAIL: 022 changed existing rows: %',t.name; end if;
 end loop;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fa300000-0000-4000-8000-000000000001';
 set local role authenticated;
 r:=public.rm_web_mutate_v1('fa300000-0000-4000-8000-000000000001','save_project',p);
 reset role;
 if not (r->>'idempotent_replay')::boolean then raise exception 'FAIL: warm old operation did not replay'; end if;
 select to_jsonb(f),jsonb_build_object('projeto_id',projeto_id,'foto_id',id,'expected_updated_at',updated_at,'selected',true)
  into before_row,p from public.rm_fotos f where id='6a300000-0000-4000-8000-000000000001';
 set local role authenticated;
 r:=public.rm_web_mutate_v1('fa300000-0000-4000-8000-000000000002','set_project_photo_selection',p);
 reset role;
 select to_jsonb(f) into after_row from public.rm_fotos f where id='6a300000-0000-4000-8000-000000000001';
 if r->>'operation'<>'set_project_photo_selection' or not (r->'record'->>'selecao_relatorio')::boolean
  or (before_row-array['selecao_relatorio','modified_by_id','sync_source','updated_at']) is distinct from
   (after_row-array['selecao_relatorio','modified_by_id','sync_source','updated_at']) then
  raise exception 'FAIL: warm wrapper did not route new operation or changed original photo fields'; end if;
 set local role authenticated;
 r:=public.rm_web_mutate_v1('fa300000-0000-4000-8000-000000000002','set_project_photo_selection',p);
 reset role;
 if not (r->>'idempotent_replay')::boolean or after_row is distinct from
  (select to_jsonb(f) from public.rm_fotos f where id='6a300000-0000-4000-8000-000000000001') then
  raise exception 'FAIL: warm new-command replay changed row or lost protocol'; end if;
 p:=jsonb_build_object('projeto_id','5a300000-0000-4000-8000-000000000001','foto_id','6a300000-0000-4000-8000-000000000001',
  'expected_updated_at',after_row->'updated_at','selected',true);
 set local role authenticated;
 r:=public.rm_web_mutate_v1('fa300000-0000-4000-8000-000000000003','set_project_photo_selection',p);
 reset role;
 if after_row is distinct from (select to_jsonb(f) from public.rm_fotos f where id='6a300000-0000-4000-8000-000000000001') then
  raise exception 'FAIL: warm no-op changed exact revision or metadata'; end if;
end $$;
rollback;
begin;
delete from rm_private.web_mutation_receipts where client_submission_id='fa300000-0000-4000-8000-000000000001';
delete from public.rm_fotos where id='6a300000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5a300000-0000-4000-8000-000000000001';
delete from public.rm_users where id='2a300000-0000-4000-8000-000000000001';
delete from auth.users where id='1a300000-0000-4000-8000-000000000001';
commit;
select 'PASS: 022 preserves all 56 public and 11 private tables; warm 021 wrapper reaches old/new commands and exact replay/no-op' as result;
