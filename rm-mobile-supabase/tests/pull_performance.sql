\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('13000000-0000-4000-8000-000000000001'),('13000000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 ('23000000-0000-4000-8000-000000000001','13000000-0000-4000-8000-000000000001','Read fixture','mobile','ativo');
insert into public.rm_clientes(id,nome) values('43000000-0000-4000-8000-000000000001','Pull fixture');
set local role authenticated;
select set_config('request.jwt.claim.sub','13000000-0000-4000-8000-000000000001',true);
select pg_temp.check((select count(*)=1 from public.rm_clientes where id='43000000-0000-4000-8000-000000000001'),'linked active account retains read access');
select set_config('request.jwt.claim.sub','13000000-0000-4000-8000-000000000002',true);
select pg_temp.check((select count(*)=0 from public.rm_clientes where id='43000000-0000-4000-8000-000000000001'),'unlinked Auth account remains denied');
reset role;
update public.rm_users set status='inativo' where id='23000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','13000000-0000-4000-8000-000000000001',true);
select pg_temp.check((select count(*)=0 from public.rm_clientes where id='43000000-0000-4000-8000-000000000001'),'inactive account denied on next statement, not cached across requests');
reset role;
update public.rm_users set status='ativo' where id='23000000-0000-4000-8000-000000000001';
set local role authenticated;
-- Assert the planner uses an InitPlan and the cursor index on first/late pages.
-- Force index planning only in this empty local fixture; remote timings use the
-- production planner with the full real data, without this setting.
set local enable_seqscan=off;
do $$ declare plan json; begin
  execute 'explain (format json) select * from public.rm_respostas order by updated_at,id limit 250' into plan;
  perform pg_temp.check(plan::text like '%InitPlan%','RLS identity evaluated once per statement');
  perform pg_temp.check(plan::text like '%idx_rm_respostas_mobile_cursor%','first page supports cursor index');
  execute 'explain (format json) select * from public.rm_respostas where updated_at>''2026-10-28T00:00:00Z'' or (updated_at=''2026-10-28T00:00:00Z'' and id>''00000000-0000-0000-0000-000000000000'') order by updated_at,id limit 250' into plan;
  perform pg_temp.check(plan::text like '%idx_rm_respostas_mobile_cursor%','incremental predicate supports cursor index');
end $$;
reset role;
select pg_temp.check(not has_table_privilege('anon','public.rm_respostas','SELECT'),'anonymous remains denied');
select pg_temp.check(not has_table_privilege('authenticated','public.rm_respostas','INSERT'),'direct client writes remain denied');
select pg_temp.check(not has_table_privilege('authenticated','rm_private.user_credentials','SELECT'),'private credentials remain denied');
select 'PASS: indexed pull, statement-scoped identity and unchanged read/write permissions' as result;
rollback;
