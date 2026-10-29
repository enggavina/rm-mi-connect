-- TEST DATABASE ONLY: prove additive installation and an already warm wrapper.
\set ON_ERROR_STOP on
begin;
create schema rm_test_pcp_upgrade;
create table rm_test_pcp_upgrade.snapshots(name text primary key,rows bigint,hash text);
insert into auth.users(id) values('1e000000-0000-4000-8000-000000000001');
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values('2e000000-0000-4000-8000-000000000001','1e000000-0000-4000-8000-000000000001','PCP upgrade fixture','administrador');
insert into public.rm_celulas(id,nome) values('4e000000-0000-4000-8000-000000000001','PCP upgrade cell');
insert into public.rm_projetos(id,numero) values('5e000000-0000-4000-8000-000000000001','PCP-UPGRADE-21');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade,posicao,indice)
 values('6e000000-0000-4000-8000-000000000001','5e000000-0000-4000-8000-000000000001','4e000000-0000-4000-8000-000000000001','em_dia',false,17,66);
select set_config('request.jwt.claim.sub','1e000000-0000-4000-8000-000000000001',false);
select set_config('request.jwt.claims','{"aal":"aal1"}',false);
do $$ declare p jsonb; begin
 select jsonb_build_object('projeto_id',projeto_id,'celula_id',celula_id,'expected_updated_at',updated_at,
   'changes',jsonb_build_object('observacao','Warm PCP planning')) into p
   from public.rm_celulas_projeto where id='6e000000-0000-4000-8000-000000000001';
 set local role authenticated;
 perform public.rm_web_mutate_v1('fe000000-0000-4000-8000-000000000001','plan_cell',p);
 reset role;
end $$;
do $$ declare t record; total bigint; digest text; begin
 for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and ((n.nspname='public' and c.relname like 'rm\_%' escape '\') or n.nspname='rm_private') loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %I.%I t',t.nspname,t.relname)
   into total,digest;
  insert into rm_test_pcp_upgrade.snapshots values(t.nspname||'.'||t.relname,total,digest);
 end loop;
 if (select count(*) from rm_test_pcp_upgrade.snapshots where split_part(name,'.',1)='public')<>56
  or (select count(*) from rm_test_pcp_upgrade.snapshots where split_part(name,'.',1)='rm_private')<>11
  or (select count(*) from rm_test_pcp_upgrade.snapshots)<>67 then
  raise exception 'FAIL: expected complete snapshots of 56 public and 11 private tables'; end if;
end $$;
commit;
\ir ../migrations/021_rm_web_pcp_queues.sql
begin;
do $$ declare t record; total bigint; digest text; p jsonb; r jsonb; q jsonb;
 old_queue_version text; priority_row jsonb; begin
 for t in select * from rm_test_pcp_upgrade.snapshots loop
  execute format('select count(*),md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text)::text,''[]'')) from %s t',t.name)
   into total,digest;
  if total<>t.rows or digest<>t.hash then raise exception 'FAIL: PCP upgrade changed old rows: %',t.name; end if;
 end loop;
 select payload into p from rm_private.web_mutation_receipts where client_submission_id='fe000000-0000-4000-8000-000000000001';
 set local role authenticated;
 r:=public.rm_web_mutate_v1('fe000000-0000-4000-8000-000000000001','plan_cell',p);
 if not (r->>'idempotent_replay')::boolean then raise exception 'FAIL: warm old operation did not replay'; end if;
 r:=public.rm_web_cell_queue_snapshot_v1('4e000000-0000-4000-8000-000000000001');
 if (r->>'total')::integer<>1 or not (r->>'complete')::boolean
  or r->>'queue_version'!~'^[0-9a-f]{64}$'
  or (r->'items'->0->>'posicao')::integer<>17 or (r->'items'->0->>'indice')::integer<>66 then
  raise exception 'FAIL: additive install did not preserve the existing sparse queue order'; end if;
 old_queue_version:=r->>'queue_version';
 p:=jsonb_build_object('celula_id','4e000000-0000-4000-8000-000000000001','expected_queue_version',r->>'queue_version',
  'apply_order',false,'items',jsonb_build_array(jsonb_build_object('id',r->'items'->0->>'id',
   'expected_updated_at',r->'items'->0->>'updated_at','prioridade','alta')));
 r:=public.rm_web_mutate_v1('fe000000-0000-4000-8000-000000000002','save_cell_queue',p);
 if r->'record'->>'queue_version' is not distinct from old_queue_version then
  raise exception 'FAIL: priority mutation did not advance the queue revision'; end if;
 select to_jsonb(a) into priority_row from public.rm_celulas_projeto a
  where id='6e000000-0000-4000-8000-000000000001';
 r:=public.rm_web_mutate_v1('fe000000-0000-4000-8000-000000000002','save_cell_queue',p);
 if not (r->>'idempotent_replay')::boolean or priority_row is distinct from
  (select to_jsonb(a) from public.rm_celulas_projeto a where id='6e000000-0000-4000-8000-000000000001') then
  raise exception 'FAIL: warm new-command retry changed the allocation or lost its protocol'; end if;
 reset role;
 if r->>'operation'<>'save_cell_queue' or not exists(select 1 from public.rm_celulas_projeto
  where id='6e000000-0000-4000-8000-000000000001' and posicao=17 and indice=66 and prioridade='alta' and not visibilidade)
 then raise exception 'FAIL: warm wrapper did not reach the new queue core'; end if;
 -- Explicit order application uses a fresh revision; priority-only save above
 -- must not normalize the legacy position as a side effect.
 set local role authenticated;
 q:=public.rm_web_cell_queue_snapshot_v1('4e000000-0000-4000-8000-000000000001');
 if q->>'queue_version' is distinct from r->'record'->>'queue_version' then
  raise exception 'FAIL: stored result and fresh queue revisions disagree'; end if;
 p:=jsonb_build_object('celula_id','4e000000-0000-4000-8000-000000000001','expected_queue_version',q->>'queue_version',
  'apply_order',true,'items',jsonb_build_array(jsonb_build_object('id',q->'items'->0->>'id',
   'expected_updated_at',q->'items'->0->>'updated_at','prioridade',q->'items'->0->'prioridade')));
 perform public.rm_web_mutate_v1('fe000000-0000-4000-8000-000000000003','save_cell_queue',p);
 reset role;
 if not exists(select 1 from public.rm_celulas_projeto where id='6e000000-0000-4000-8000-000000000001'
  and posicao=1 and indice=66 and prioridade='alta' and not visibilidade) then
  raise exception 'FAIL: explicit warm order application changed priority/index/visibility'; end if;
end $$;
rollback;
begin;
delete from rm_private.web_mutation_receipts where client_submission_id='fe000000-0000-4000-8000-000000000001';
delete from public.rm_celulas_projeto where id='6e000000-0000-4000-8000-000000000001';
delete from public.rm_projetos where id='5e000000-0000-4000-8000-000000000001';
delete from public.rm_celulas where id='4e000000-0000-4000-8000-000000000001';
delete from public.rm_users where id='2e000000-0000-4000-8000-000000000001';
delete from auth.users where id='1e000000-0000-4000-8000-000000000001';
commit;
select 'PASS: 021 preserves all 56 public and 11 private tables, and warm 020 wrapper reaches old/new operations' as result;
