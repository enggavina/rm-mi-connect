-- Isolated harness only: a warm 022 public session must reach the 023 wrapper.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('12300000-0000-4000-8000-000000000099');
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values('22300000-0000-4000-8000-000000000099','12300000-0000-4000-8000-000000000099','Title upgrade fixture','administrador');
select set_config('request.jwt.claim.sub','12300000-0000-4000-8000-000000000099',true);
do $$ begin
  begin
    set local role authenticated;
    perform public.rm_web_mutate_v1(gen_random_uuid(),'delete_photo_title',jsonb_build_object('id',gen_random_uuid(),
      'expected_updated_at',clock_timestamp()));
    raise exception 'FAIL: 022 accepted deletion before 023';
  exception when invalid_parameter_value then reset role; end;
end $$;
rollback;
\ir ../migrations/023_rm_web_photo_title_deletion.sql
begin;
insert into auth.users(id) values('12300000-0000-4000-8000-000000000099');
insert into public.rm_users(id,auth_user_id,nome,perfil)
 values('22300000-0000-4000-8000-000000000099','12300000-0000-4000-8000-000000000099','Title upgrade fixture','administrador');
select set_config('request.jwt.claim.sub','12300000-0000-4000-8000-000000000099',true);
do $$ declare r jsonb; title_id uuid:=gen_random_uuid(); begin
  set local role authenticated;
  r:=public.rm_web_mutate_v1(gen_random_uuid(),'save_photo_title',jsonb_build_object('id',title_id,'expected_updated_at',null,
    'changes',jsonb_build_object('titulo','Warm title fixture','celula_id',null)));
  r:=public.rm_web_mutate_v1(gen_random_uuid(),'delete_photo_title',jsonb_build_object('id',title_id,'expected_updated_at',r->'updated_at'));
  reset role;
  if r->>'operation'<>'delete_photo_title' or exists(select 1 from public.rm_cadastro_fotos where id=title_id) then
    raise exception 'FAIL: warmed wrapper retained old core'; end if;
end $$;
rollback;
select 'PASS: warm 022 public wrapper reaches existing save and new 023 delete' as result;
