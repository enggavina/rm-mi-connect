\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.deny_web(request_id uuid,operation text,payload jsonb) returns void language plpgsql as $$
begin
  begin perform public.rm_web_mutate_v1(request_id,operation,payload);
  exception when insufficient_privilege then return; end;
  raise exception 'FAIL: SSO write unexpectedly allowed';
end $$;
insert into auth.users(id) values('16000000-0000-4000-8000-000000000001'),('16000000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('26000000-0000-4000-8000-000000000001','16000000-0000-4000-8000-000000000001','Bound fixture','administrador'),
 ('26000000-0000-4000-8000-000000000002','16000000-0000-4000-8000-000000000002','Legacy fixture','administrador');
insert into auth.sessions(id,user_id) values
 ('36000000-0000-4000-8000-000000000001','16000000-0000-4000-8000-000000000001'),
 ('36000000-0000-4000-8000-000000000002','16000000-0000-4000-8000-000000000002');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('46000000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','56000000-0000-4000-8000-000000000001',
 '26000000-0000-4000-8000-000000000001','16000000-0000-4000-8000-000000000001',true,'26000000-0000-4000-8000-000000000002',clock_timestamp());
select set_config('rm.test.sso_payload',jsonb_build_object('id','66000000-0000-4000-8000-000000000001',
  'expected_updated_at',null,'changes',jsonb_build_object('nome','SSO project fixture'))::text,true);
select pg_temp.check(not (select require_sso from rm_private.sso_settings),'staged enforcement defaults false');
set local role service_role;
do $$ declare result jsonb; begin
  result:=public.rm_sso_binding_v1('https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','56000000-0000-4000-8000-000000000001');
  perform pg_temp.check(result->>'auth_user_id'='16000000-0000-4000-8000-000000000001' and result->'profile'->>'perfil'='administrador','explicit binding resolves existing role');
  perform pg_temp.check(public.rm_sso_binding_v1('https://untrusted.invalid','56000000-0000-4000-8000-000000000001') is null,'wrong issuer denied');
  perform public.rm_sso_flow_put_v1(repeat('a',64),'opaque-encrypted-flow-fixture',clock_timestamp()+interval '5 minutes');
  perform pg_temp.check(public.rm_sso_flow_get_v1(repeat('a',64))='opaque-encrypted-flow-fixture','flow read for pending MFA');
  perform pg_temp.check(public.rm_sso_flow_get_v1(repeat('a',64))='opaque-encrypted-flow-fixture','flow read does not consume');
  perform pg_temp.check(public.rm_sso_flow_take_v1(repeat('a',64))='opaque-encrypted-flow-fixture','flow take returns envelope');
  perform pg_temp.check(public.rm_sso_flow_take_v1(repeat('a',64)) is null,'flow single use');
  perform pg_temp.check(public.rm_sso_flow_get_v1(repeat('a',64)) is null,'consumed flow is unreadable');
  begin
    perform public.rm_sso_flow_put_v1(repeat('a',64),'opaque-encrypted-flow-fixture',clock_timestamp()+interval '11 minutes');
    raise exception 'FAIL: long flow TTL'; exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_sso_session_put_v1(repeat('b',64),'46000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000001',
      'opaque-encrypted-session-fixture',clock_timestamp()+interval '61 minutes');
    raise exception 'FAIL: long session TTL'; exception when invalid_parameter_value then null; end;
  begin
    perform public.rm_sso_session_put_v1(repeat('b',64),'46000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000002',
      'opaque-encrypted-session-fixture',clock_timestamp()+interval '45 minutes');
    raise exception 'FAIL: another Auth session linked'; exception when insufficient_privilege then null; end;
  perform public.rm_sso_session_put_v1(repeat('b',64),'46000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000001',
    'opaque-encrypted-session-fixture',clock_timestamp()+interval '45 minutes');
  result:=public.rm_sso_session_get_v1(repeat('b',64));
  perform pg_temp.check(result->>'ciphertext'='opaque-encrypted-session-fixture' and result->>'subject'='56000000-0000-4000-8000-000000000001','session loads explicit identity and opaque envelope');
  begin
    perform public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.forms.review');
    raise exception 'FAIL: mismatched capability accepted'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
insert into rm_private.sso_flows(hash,ciphertext,expires_at) values(repeat('e',64),'opaque-expired-flow-fixture',clock_timestamp()-interval '1 second');
set local role service_role;
select pg_temp.check(public.rm_sso_flow_get_v1(repeat('e',64)) is null,'expired flow hidden from MFA read');
select pg_temp.check(public.rm_sso_flow_take_v1(repeat('e',64)) is null,'expired flow consumed without disclosure');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"session_id":"36000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb);
do $$ begin
  begin
    perform public.rm_sso_session_get_v1(repeat('b',64));
    raise exception 'FAIL: browser read encrypted session'; exception when insufficient_privilege then null; end;
  begin
    perform rm_private.web_mutate_core_v1(gen_random_uuid(),'save_project',current_setting('rm.test.sso_payload')::jsonb);
    raise exception 'FAIL: browser bypassed wrapper'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role service_role;
select public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.projects.manage');
reset role;
select pg_temp.check((select expires_at<=clock_timestamp()+interval '15 seconds' from rm_private.sso_action_permits
  where submission_id='76000000-0000-4000-8000-000000000001'),'permit lifetime bounded');
set local role authenticated;
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','save_project',
  jsonb_set(current_setting('rm.test.sso_payload')::jsonb,'{changes,nome}','"Tampered"'));
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','plan_cell',current_setting('rm.test.sso_payload')::jsonb);
select set_config('request.jwt.claims','{"session_id":"36000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb);
select set_config('request.jwt.claims','{"session_id":"36000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select public.rm_web_mutate_v1('76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb);
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb);
reset role;
select pg_temp.check((select count(*)=0 from rm_private.sso_action_permits),'successful action consumes permit');
set local role service_role;
select public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.projects.manage');
reset role;
set local role authenticated;
select pg_temp.check((public.rm_web_mutate_v1('76000000-0000-4000-8000-000000000001','save_project',
 current_setting('rm.test.sso_payload')::jsonb)->>'idempotent_replay')::boolean,'replay succeeds only with fresh permit');
reset role;
set local role service_role;
select public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.projects.manage');
reset role;
update rm_private.sso_action_permits set expires_at=clock_timestamp()-interval '1 second';
set local role authenticated;
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb);
reset role;
-- Enrolling MFA after SSO does not let a valid permit bypass AAL2, including replay.
insert into auth.mfa_factors(user_id,factor_type,status) values('16000000-0000-4000-8000-000000000001','totp','verified');
set local role service_role;
select public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.projects.manage');
reset role;
set local role authenticated;
select pg_temp.deny_web('76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb);
select set_config('request.jwt.claims','{"session_id":"36000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select pg_temp.check((public.rm_web_mutate_v1('76000000-0000-4000-8000-000000000001','save_project',
 current_setting('rm.test.sso_payload')::jsonb)->>'idempotent_replay')::boolean,'MFA AAL2 retains replay');
reset role;
update rm_private.sso_identity_bindings set enabled=false;
set local role service_role;
select pg_temp.check(public.rm_sso_session_get_v1(repeat('b',64)) is null,'disabled binding hides session');
select pg_temp.check(public.rm_sso_binding_v1('https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','56000000-0000-4000-8000-000000000001') is null,'disabled binding lookup denied');
reset role;
set local role authenticated;
select pg_temp.deny_web(gen_random_uuid(),'save_project',jsonb_set(current_setting('rm.test.sso_payload')::jsonb,'{id}',to_jsonb(gen_random_uuid())));
-- Native accounts without ANY binding retain staging access, not bound/disabled users.
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000002',true);
select public.rm_web_mutate_v1('76000000-0000-4000-8000-000000000002','save_project',
  jsonb_build_object('id','66000000-0000-4000-8000-000000000002','expected_updated_at',null,'changes',jsonb_build_object('nome','Legacy fixture project')));
reset role;
update rm_private.sso_settings set require_sso=true;
set local role authenticated;
select pg_temp.deny_web(gen_random_uuid(),'save_project',jsonb_set(current_setting('rm.test.sso_payload')::jsonb,'{id}',to_jsonb(gen_random_uuid())));
reset role;
-- Global SSO enforcement does not touch mobile operator context or read RLS.
set local role authenticated;
select pg_temp.check((select count(*)=2 from public.rm_projetos),'mobile-compatible authenticated read remains');
reset role;
update rm_private.sso_identity_bindings set enabled=true;
-- Changing a RM Auth link cannot accidentally restore legacy access in staging.
update rm_private.sso_settings set require_sso=false;
insert into auth.users(id) values('16000000-0000-4000-8000-000000000003');
update public.rm_users set auth_user_id='16000000-0000-4000-8000-000000000003' where id='26000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','16000000-0000-4000-8000-000000000003',true);
select pg_temp.deny_web(gen_random_uuid(),'save_project',current_setting('rm.test.sso_payload')::jsonb);
reset role;
update public.rm_users set auth_user_id='16000000-0000-4000-8000-000000000001' where id='26000000-0000-4000-8000-000000000001';
update rm_private.sso_sessions set expires_at=clock_timestamp()-interval '1 second';
set local role service_role;
select pg_temp.check(public.rm_sso_session_get_v1(repeat('b',64)) is null,'expired session unavailable');
do $$ begin
  begin
    perform public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.projects.manage');
    raise exception 'FAIL: expired session minted permit'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update rm_private.sso_sessions set expires_at=clock_timestamp()+interval '30 minutes';
set local role service_role;
select public.rm_sso_action_permit_v1(repeat('b',64),'76000000-0000-4000-8000-000000000001','save_project',current_setting('rm.test.sso_payload')::jsonb,'em.projects.manage');
select public.rm_sso_session_delete_v1(repeat('b',64));
select pg_temp.check(public.rm_sso_session_get_v1(repeat('b',64)) is null,'deleted session unavailable');
reset role;
select pg_temp.check((select count(*)=0 from rm_private.sso_action_permits),'deleting session cascades permits');
select pg_temp.check(not has_table_privilege('service_role','rm_private.sso_sessions','select'),'service accesses envelopes only through RPC');
select pg_temp.check(not has_function_privilege('authenticated','public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)','execute'),'browser cannot mint permits');
select pg_temp.check(not has_function_privilege('anon','public.rm_sso_flow_take_v1(text)','execute'),'anonymous flow read denied');
select pg_temp.check(not has_function_privilege('authenticated','public.rm_sso_flow_get_v1(text)','execute'),'browser pending MFA read denied');
select pg_temp.check((select count(*)=2 from rm_private.web_mutation_receipts),'only two unique business mutations');
select 'PASS: explicit SSO binding, TTLs, single-use flows/permits, identity/body/session checks, replay, MFA and staging boundaries' as result;
rollback;
