-- Local harness only. Warm the public 016 PL/pgSQL plan and then upgrade 017
-- on this SAME database connection, proving cached sessions use the new core.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('17000000-0000-4000-8000-000000000099');
insert into public.rm_users(auth_user_id,nome,perfil) values('17000000-0000-4000-8000-000000000099','Upgrade fixture','administrador');
select set_config('request.jwt.claim.sub','17000000-0000-4000-8000-000000000099',true);
do $$ begin
  begin
    perform public.rm_web_mutate_v1(gen_random_uuid(),'save_catalog',jsonb_build_object('kind','clients','id',gen_random_uuid(),
      'expected_updated_at',null,'changes',jsonb_build_object('nome','Before upgrade fixture')));
    raise exception 'FAIL: 016 unexpectedly accepted a new catalog operation';
  exception when invalid_parameter_value then null; end;
end $$;
rollback;
\ir ../migrations/017_rm_web_catalog_management.sql
begin;
insert into auth.users(id) values('17000000-0000-4000-8000-000000000099');
insert into public.rm_users(auth_user_id,nome,perfil) values('17000000-0000-4000-8000-000000000099','Upgrade fixture','administrador');
select set_config('request.jwt.claim.sub','17000000-0000-4000-8000-000000000099',true);
do $$ declare result jsonb; begin
  result:=public.rm_web_mutate_v1(gen_random_uuid(),'save_catalog',jsonb_build_object('kind','clients','id',gen_random_uuid(),
    'expected_updated_at',null,'changes',jsonb_build_object('nome','After upgrade fixture')));
  if result->>'operation'<>'save_catalog' then raise exception 'FAIL: old core plan retained'; end if;
end $$;
rollback;
select 'PASS: existing-session public wrapper dispatch after 016 to 017 upgrade' as result;
