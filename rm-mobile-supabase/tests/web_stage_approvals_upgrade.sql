-- TEST DATABASE ONLY: warm 001-019 sessions and complete old-table snapshots
-- prove the additive 020 installation before the isolated functional suites.
\set ON_ERROR_STOP on
begin;
create schema rm_test_stage_upgrade;
create table rm_test_stage_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1b000000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil)
  values('2b000000-0000-4000-8000-000000000001','1b000000-0000-4000-8000-000000000001','Stage upgrade fixture','administrador');
insert into public.rm_celulas(id,nome) values('4b000000-0000-4000-8000-000000000001','Stage upgrade cell');
insert into public.rm_projetos(id,numero) values('5b000000-0000-4000-8000-000000000001','STAGE-UPGRADE-20');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade)
  values('6b000000-0000-4000-8000-000000000001','5b000000-0000-4000-8000-000000000001','4b000000-0000-4000-8000-000000000001','em_dia',true);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,status_cel_proj)
  values('7b000000-0000-4000-8000-000000000001','5b000000-0000-4000-8000-000000000001','4b000000-0000-4000-8000-000000000001','em_dia');
select set_config('request.jwt.claim.sub','1b000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
-- Calls compile the SSO wrapper and renamed 019 core in this same backend.
set local role authenticated;
select public.rm_web_mutate_v1('fb000000-0000-4000-8000-000000000001','create_form_template',
  '{"id":"cb000000-0000-4000-8000-000000000001","kind":"new","source_form_id":null}');
reset role;
do $$ declare t record; total bigint; digest text; begin
  for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\')
      or (n.nspname='rm_private' and c.relname='web_mutation_receipts')) loop
    execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname)
      into total,digest;
    insert into rm_test_stage_upgrade.snapshots values(t.nspname||'.'||t.relname,total,digest);
  end loop;
end $$;
commit;
\ir ../migrations/020_rm_web_stage_approvals.sql
begin;
do $$ declare t record; total bigint; digest text; begin
  for t in select * from rm_test_stage_upgrade.snapshots loop
    execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name)
      into total,digest;
    if total<>t.rows or digest<>t.hash then raise exception 'FAIL: upgrade changed old rows: %',t.name; end if;
  end loop;
  if exists(select 1 from public.rm_web_stage_decisions) then raise exception 'FAIL: install created synthetic history'; end if;
end $$;
-- Both an older command and the new command work from the already warm wrapper.
set local role authenticated;
select public.rm_web_mutate_v1('fb000000-0000-4000-8000-000000000001','create_form_template',
  '{"id":"cb000000-0000-4000-8000-000000000001","kind":"new","source_form_id":null}');
do $$ declare r jsonb; p jsonb; begin
  select jsonb_build_object('aprovacao_etapa_id',a.id,'expected_updated_at',a.updated_at,
    'expected_cell_updated_at',cp.updated_at,'acao','liberar','observacao',null) into p
    from public.rm_aprovacoes_etapas a join public.rm_celulas_projeto cp
      on cp.projeto_id=a.projeto_id and cp.celula_id=a.celula_origem_id where a.id='7b000000-0000-4000-8000-000000000001';
  r:=public.rm_web_mutate_v1('fb000000-0000-4000-8000-000000000002','transition_stage_approval',p);
  if r->'snapshot'->'stage'->>'status'<>'aprovado' or jsonb_array_length(r->'snapshot'->'history')<>1 then
    raise exception 'FAIL: warm SSO wrapper did not call the new core'; end if;
end $$;
reset role;
rollback;
-- Remove only these explicit local fixtures so older suites retain their
-- original catalog cardinalities. The complete database is still disposable.
begin;
delete from rm_private.web_mutation_receipts where client_submission_id='fb000000-0000-4000-8000-000000000001';
delete from public.rm_form_template_drafts where id='cb000000-0000-4000-8000-000000000001';
delete from public.rm_form_template_families where id='cb000000-0000-4000-8000-000000000001';
delete from public.rm_aprovacoes_etapas where id='7b000000-0000-4000-8000-000000000001';
delete from public.rm_celulas_projeto where id='6b000000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5b000000-0000-4000-8000-000000000001';
delete from public.rm_celulas where id='4b000000-0000-4000-8000-000000000001';
delete from public.rm_users where id='2b000000-0000-4000-8000-000000000001';
delete from auth.users where id='1b000000-0000-4000-8000-000000000001';
commit;
select 'PASS: 020 preserves all 55 old public tables plus web receipts, and warm 019 wrapper remains compatible' as result;
