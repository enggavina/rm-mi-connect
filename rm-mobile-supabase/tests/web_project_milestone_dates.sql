-- Fixtures only in a disposable isolated database; nothing is committed.
\set ON_ERROR_STOP on
begin;
do $$ begin if current_database()<>'rmmi_test' then raise exception 'Disposable local database required'; end if; end $$;
create function pg_temp.check_milestone(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values ('1fe35000-0000-4000-8000-000000000001'), ('1fe35000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil,status) values
 ('2fe35000-0000-4000-8000-000000000001','1fe35000-0000-4000-8000-000000000001','Milestone admin fixture','administrador','ativo'),
 ('2fe35000-0000-4000-8000-000000000002','1fe35000-0000-4000-8000-000000000002','Milestone mobile fixture','mobile','ativo');
update rm_private.sso_settings set require_sso=false;
select set_config('request.jwt.claim.sub','1fe35000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
-- Frozen legacy creation receipt: verify 035's old create/date contract and
-- current public replay without reopening fresh untyped web creation.
select rm_private.web_mutate_before_route_instance_v1('afe35000-0000-4000-8000-000000000001','save_project',jsonb_build_object(
 'id','5fe35000-0000-4000-8000-000000000001','expected_updated_at',null,'changes',jsonb_build_object('nome','Milestone fixture',
 'data_inicio_peritagem','2026-11-01','data_fim_peritagem','2026-11-02','data_inicio_reparo','2026-10-01','data_fim_reparo','2026-10-02')));
set local role authenticated;
do $$
declare payload jsonb; result jsonb; initial_result jsonb; project_id uuid:='5fe35000-0000-4000-8000-000000000001';
begin
 payload:=jsonb_build_object('id',project_id,'expected_updated_at',null,'changes',jsonb_build_object(
   'nome','Milestone fixture','data_inicio_peritagem','2026-11-01','data_fim_peritagem','2026-11-02',
   'data_inicio_reparo','2026-10-01','data_fim_reparo','2026-10-02'));
 initial_result:=public.rm_web_mutate_v1('afe35000-0000-4000-8000-000000000001','save_project',payload);
 perform pg_temp.check_milestone(initial_result->'record'->>'data_inicio_peritagem'='2026-11-01','create stores first date');
 perform pg_temp.check_milestone(initial_result->'record'->>'data_fim_reparo'='2026-10-02','independent stages may overlap or be reversed');
 result:=public.rm_web_mutate_v1('afe35000-0000-4000-8000-000000000001','save_project',payload);
 perform pg_temp.check_milestone((result->>'idempotent_replay')::boolean,'same create protocol replays');

 -- Old clients omit the fields; their full save must not clear dates.
 payload:=jsonb_build_object('id',project_id,'expected_updated_at',initial_result->>'updated_at','changes',jsonb_build_object('nome','Legacy client'));
 result:=public.rm_web_mutate_v1('afe35000-0000-4000-8000-000000000002','save_project',payload);
 perform pg_temp.check_milestone(result->'record'->>'data_inicio_peritagem'='2026-11-01' and result->'record'->>'data_fim_reparo'='2026-10-02','older payload preserves dates');
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_set(payload,'{changes}',jsonb_build_object('data_inicio_peritagem','2026-12-01')));
  raise exception 'FAIL: stale edit succeeded';
 exception when sqlstate 'PT409' or serialization_failure then null; end;
 payload:=jsonb_set(payload,'{expected_updated_at}',result->'updated_at');
 for result in select jsonb_build_object('data_inicio_reparo',bad.value) from (values
  ('"today"'::jsonb),('"infinity"'::jsonb),('"0000-01-01"'::jsonb),('"2026-01-01T00:00:00Z"'::jsonb),('3'::jsonb),('[]'::jsonb)) bad(value) loop
  begin
   perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_set(payload,'{changes}',result));
   raise exception 'FAIL: invalid calendar value accepted';
  exception when invalid_parameter_value then null; end;
 end loop;
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_set(payload,'{changes}',jsonb_build_object('data_inicio_peritagem','2026-12-01')));
  raise exception 'FAIL: invalid partial inspection pair accepted';
 exception when check_violation then null; end;
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_set(payload,'{changes}',jsonb_build_object('data_fim_reparo','2026-09-01')));
  raise exception 'FAIL: invalid partial repair pair accepted';
 exception when check_violation then null; end;
 result:=public.rm_web_mutate_v1('afe35000-0000-4000-8000-000000000003','save_project',jsonb_set(payload,'{changes}',jsonb_build_object('data_fim_peritagem',null,'data_inicio_reparo',null)));
 perform pg_temp.check_milestone(result->'record'->'data_fim_peritagem'='null'::jsonb and result->'record'->'data_inicio_reparo'='null'::jsonb,'individual fields may be removed');
 perform pg_temp.check_milestone(result->'record'->>'data_inicio_peritagem'='2026-11-01' and result->'record'->>'data_fim_reparo'='2026-10-02','other fields remain');
end $$;
select set_config('request.jwt.claim.sub','1fe35000-0000-4000-8000-000000000002',true);
do $$ begin
 begin
  perform public.rm_web_mutate_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',gen_random_uuid(),'expected_updated_at',null,'changes',jsonb_build_object('nome','Unauthorised','data_inicio_reparo','2026-01-01')));
  raise exception 'FAIL: mobile role bypassed web access';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
