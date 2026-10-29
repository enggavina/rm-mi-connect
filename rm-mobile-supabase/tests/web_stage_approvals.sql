\set ON_ERROR_STOP on
begin;
create function pg_temp.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
create function pg_temp.stage_key(head text,n integer) returns uuid language sql immutable as $$
  select (head||'a000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.stage_actor(n integer,aal text default 'aal1') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub',pg_temp.stage_key('1',n)::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id',pg_temp.stage_key('3',n),'aal',aal)::text,true);
  perform set_config('rm.test.stage.actor',n::text,true);
end $$;
create function pg_temp.stage_payload(n integer,action text default 'liberar',observation text default null) returns jsonb language sql as $$
  select jsonb_build_object('aprovacao_etapa_id',a.id,'expected_updated_at',a.updated_at,
    'expected_cell_updated_at',cp.updated_at,'acao',action,'observacao',observation)
  from public.rm_aprovacoes_etapas a left join public.rm_celulas_projeto cp
    on cp.projeto_id=a.projeto_id and cp.celula_id=a.celula_origem_id where a.id=pg_temp.stage_key('7',n);
$$;
create function pg_temp.call_stage(rid uuid,p jsonb,cap text default 'em.approvals.decide') returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform public.rm_sso_action_permit_v1(lpad(current_setting('rm.test.stage.actor'),64,'a'),rid,'transition_stage_approval',p,cap);
  set local role authenticated; r:=public.rm_web_mutate_v1(rid,'transition_stage_approval',p); reset role; return r;
exception when others then reset role; raise;
end $$;
create function pg_temp.reject_stage(p jsonb,wanted text,cap text default 'em.approvals.decide') returns void language plpgsql as $$
declare actual text; begin
  begin perform pg_temp.call_stage(gen_random_uuid(),p,cap);
  exception when others then get stacked diagnostics actual=returned_sqlstate;
    if actual=wanted then return; end if; raise exception 'FAIL: expected %, got %: %',wanted,actual,sqlerrm;
  end; raise exception 'FAIL: stage decision unexpectedly succeeded (expected %)',wanted;
end $$;
do $$ declare n integer; u uuid; a uuid; binding uuid; session uuid; profile public.rm_perfil_usuario_enum; begin
  for n in 1..9 loop
    a:=pg_temp.stage_key('1',n); u:=pg_temp.stage_key('2',n); binding:=pg_temp.stage_key('8',n); session:=pg_temp.stage_key('3',n);
    profile:=case when n in (1,8,9) then 'administrador' when n=4 then 'auditor' else 'padr_o' end;
    insert into auth.users(id) values(a);
    insert into public.rm_users(id,auth_user_id,nome,perfil,perfil_assinante,status)
      values(u,a,'Stage fixture '||n,profile,case when n=6 then array['aprovador']::public.rm_perfil_assinante_enum[] else '{}' end,
        case when n=9 then 'inativo'::public.rm_status_user_enum else 'ativo'::public.rm_status_user_enum end);
    insert into auth.sessions(id,user_id) values(session,a);
    if n<>9 then
      insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at)
        values(binding,'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1',pg_temp.stage_key('9',n),u,a,true,pg_temp.stage_key('2',1),clock_timestamp());
      perform public.rm_sso_session_put_v1(lpad(n::text,64,'a'),binding,session,'opaque-test-stage-'||n,clock_timestamp()+interval '45 minutes');
    end if;
  end loop;
end $$;
update rm_private.sso_settings set require_sso=true;
insert into public.rm_clientes(id,nome) values(pg_temp.stage_key('b',1),'Cliente da aprovação');
insert into public.rm_projetos(id,numero,nome,cliente_id,cliente_nome_exportacao)
  values(pg_temp.stage_key('5',1),'STAGE-QA-20','Etapas da oficina',pg_temp.stage_key('b',1),'Nome antigo');
insert into public.rm_celulas(id,nome) values
  (pg_temp.stage_key('4',1),'Origem QA'),(pg_temp.stage_key('4',2),'Destino QA'),
  (pg_temp.stage_key('4',3),'Sem alocação QA'),(pg_temp.stage_key('4',4),'Outro vínculo QA');
insert into public.rm_celulas_projeto(id,projeto_id,celula_id,status,visibilidade) values
  (pg_temp.stage_key('6',1),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),'em_dia',true),
  (pg_temp.stage_key('6',2),pg_temp.stage_key('5',1),pg_temp.stage_key('4',2),'pendente',false),
  (pg_temp.stage_key('6',3),pg_temp.stage_key('5',1),pg_temp.stage_key('4',4),'em_dia',true);
insert into public.rm_tablet_celula_users(celula_id,identidade_id)
  select c.id,pg_temp.stage_key('2',n) from public.rm_celulas c cross join generate_series(2,7) n
  where c.id in(pg_temp.stage_key('4',1),pg_temp.stage_key('4',2)) and n<>5;
-- A shared-account association must not confer the identified operator's ACL.
insert into public.rm_tablet_celula_users(celula_id,usuario_id) values(pg_temp.stage_key('4',1),pg_temp.stage_key('2',5));
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids)
values(pg_temp.stage_key('7',1),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),pg_temp.stage_key('4',2),'em_dia',true,
  array[pg_temp.stage_key('2',2),pg_temp.stage_key('2',4),pg_temp.stage_key('2',5)],array[pg_temp.stage_key('2',3)]),
 (pg_temp.stage_key('7',2),pg_temp.stage_key('5',1),pg_temp.stage_key('4',2),pg_temp.stage_key('4',1),'retornado',false,
  array[pg_temp.stage_key('2',2)],array[pg_temp.stage_key('2',3)]);
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,status_cel_proj) values
  (pg_temp.stage_key('7',3),pg_temp.stage_key('5',1),pg_temp.stage_key('4',3),'em_dia'),
  (pg_temp.stage_key('7',4),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),'em_dia'),
  (pg_temp.stage_key('7',5),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),'em_dia'),
  (pg_temp.stage_key('7',6),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),null),
  (pg_temp.stage_key('7',7),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),'em_dia'),
  (pg_temp.stage_key('7',9),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),'pendente');
update public.rm_aprovacoes_etapas set celula_projeto_id=pg_temp.stage_key('6',3) where id=pg_temp.stage_key('7',4);
update public.rm_aprovacoes_etapas set status='aprovado' where id=pg_temp.stage_key('7',7);
insert into public.rm_aprovacoes_etapas(id,celula_origem_id,status_cel_proj) values(pg_temp.stage_key('7',8),pg_temp.stage_key('4',1),'em_dia');
insert into public.rm_logs_aprovacao(id,projeto_id,celula_id,aprovador_id,status_aprovacao)
  values(pg_temp.stage_key('a',1),pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),pg_temp.stage_key('2',2),'aprovado');
select pg_temp.stage_actor(1);

-- Atomic read DTOs include legacy null links without repairing or guessing them.
set local role authenticated;
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1))->'available_actions'='["liberar"]','administrator follows existing mobile permission without invented ACL');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',2))->'available_actions'='["aprovar"]','return stage approves even before Retornado, never liberates');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',3))->'allocation'='null'::jsonb
  and public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',3))->'available_actions'='[]','missing allocation remains read-only');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',4))->'available_actions'='[]','explicit mismatched allocation stays read-only');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1))->'project'->>'cliente_nome'='Cliente da aprovação','current client and historical fallback are distinct');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1))->'legacy_history'->0->>'id'=pg_temp.stage_key('a',1)::text,'unlinked history stays cell-only');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',8)) is null,'template is not a project approval');
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(gen_random_uuid()) is null,'absent detail is null');
select pg_temp.check((public.rm_web_stage_approvals_v1(pg_temp.stage_key('5',1),null,'all',false,'',1,2)->>'total')::int=8
  and jsonb_array_length(public.rm_web_stage_approvals_v1(pg_temp.stage_key('5',1),null,'all',false,'',1,2)->'items')=2,'stable paginated total excludes templates');
select pg_temp.check((public.rm_web_stage_approvals_v1(pg_temp.stage_key('5',1),null,'pending',true,'',1,25)->>'total')::int=3,'mine means executable now');
select pg_temp.check((public.rm_web_stage_approvals_v1(pg_temp.stage_key('5',1),pg_temp.stage_key('4',1),'approved',false,'',1,25)->>'total')::int=1,'state and cell filters');
select pg_temp.check((public.rm_web_stage_approvals_v1(pg_temp.stage_key('5',1),null,'all',false,'cliente da aprovação',1,25)->>'total')::int=8,'literal search includes current client');
select pg_temp.check((public.rm_web_stage_approvals_v1(pg_temp.stage_key('5',1),null,'all',false,'%',1,25)->>'total')::int=0,'search is literal, not wildcard');
reset role;
do $$ declare snapshot jsonb; begin
  snapshot:=public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1));
  perform pg_temp.check(snapshot::text !~ 'auth_user|bubble_id|sync_source|email|token|url','DTO never exposes sensitive identity/sync/media');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1),'22023','em.planning.manage');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1)||'{"p_operador_id":"2a000000-0000-4000-8000-000000000008"}','22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1,'finalizar'),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1,'aprovar'),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(2,'liberar'),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(2,'retornar','motivo'),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(2,'retornar','  '),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1,'liberar',repeat('x',10001)),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1)||'{"expected_updated_at":"2000-01-01T00:00:00Z"}','PT409');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1)||'{"expected_cell_updated_at":"2000-01-01T00:00:00Z"}','PT409');
  perform pg_temp.reject_stage(pg_temp.stage_payload(1)||'{"expected_updated_at":"infinity"}','22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(4),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(3)||jsonb_build_object('expected_cell_updated_at',clock_timestamp()),'P0002');
  perform pg_temp.reject_stage(pg_temp.stage_payload(8)||jsonb_build_object('expected_cell_updated_at',clock_timestamp()),'P0002');
  perform pg_temp.reject_stage(pg_temp.stage_payload(9),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(6),'22023');
  perform pg_temp.reject_stage(pg_temp.stage_payload(7),'22023');
end $$;

-- Current profile, actor-cell association and action-specific approvers are
-- independent of the central capability and are never taken from browser input.
do $$ declare r jsonb; p jsonb; begin
  perform pg_temp.stage_actor(2);
  set local role authenticated;
  perform pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1))->'available_actions'='["liberar"]','named standard approver with own ACL');
  reset role;
  begin
    perform pg_temp.call_stage(gen_random_uuid(),pg_temp.stage_payload(1));
    raise exception 'rollback positive fixture' using errcode='ZX000';
  exception when sqlstate 'ZX000' then null; end;
  perform pg_temp.stage_actor(5);
  set local role authenticated;
  perform pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1))->'available_actions'='[]','shared user link does not grant operator ACL');
  reset role; perform pg_temp.reject_stage(pg_temp.stage_payload(1),'42501');
  perform pg_temp.stage_actor(7); perform pg_temp.reject_stage(pg_temp.stage_payload(1),'42501');
  perform pg_temp.stage_actor(4);
  set local role authenticated;
  perform pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1))->'available_actions'='[]','auditor cannot decide despite named approval');
  reset role; perform pg_temp.reject_stage(pg_temp.stage_payload(1),'42501');
  perform pg_temp.stage_actor(6);
  begin
    perform pg_temp.call_stage(gen_random_uuid(),pg_temp.stage_payload(5));
    raise exception 'rollback positive fixture' using errcode='ZX000';
  exception when sqlstate 'ZX000' then null; end;
  perform pg_temp.reject_stage(pg_temp.stage_payload(1),'42501');
  perform pg_temp.stage_actor(3);
  set local role authenticated;
  perform pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',2))->'available_actions'='[]','return-only approver cannot approve before returned');
  reset role; perform pg_temp.reject_stage(pg_temp.stage_payload(2,'aprovar'),'42501');
  update public.rm_celulas_projeto set status='retornado' where id=pg_temp.stage_key('6',2);
  set local role authenticated;
  perform pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',2))->'available_actions'='["retornar"]','return-only approver gets no approve button');
  reset role;
  begin
    perform pg_temp.call_stage(gen_random_uuid(),pg_temp.stage_payload(2,'retornar','Return-only reason'));
    raise exception 'rollback positive fixture' using errcode='ZX000';
  exception when sqlstate 'ZX000' then null; end;
  update public.rm_celulas_projeto set status='pendente' where id=pg_temp.stage_key('6',2);
  perform pg_temp.stage_actor(1);
end $$;

-- Web release and mobile return/approval observe the same project lock and
-- shared transaction. Exact audit belongs only to decisions actually made web.
do $$ declare p jsonb:=pg_temp.stage_payload(1,'liberar','  Oficina liberada  '); rid uuid:=gen_random_uuid(); r jsonb;
  original_stage timestamptz; original_cell timestamptz; logs integer; outbox integer; mobile_params jsonb; begin
  select count(*) into logs from public.rm_logs_aprovacao;
  select count(*) into outbox from public.rm_sync_outbox;
  r:=pg_temp.call_stage(rid,p);
  perform pg_temp.check(r->'snapshot'->'stage'->>'status'='aprovado','web release uses existing approved state');
  perform pg_temp.check((select status='para_execu__o' and visibilidade from public.rm_celulas_projeto where id=pg_temp.stage_key('6',2)),'web release advances destination');
  perform pg_temp.check((select count(*)=logs+1 from public.rm_logs_aprovacao),'one shared log');
  perform pg_temp.check((select count(*)=outbox+2 from public.rm_sync_outbox),'same queued effects, no external worker');
  perform pg_temp.check((select count(*)=1 from public.rm_web_stage_decisions where client_submission_id=rid
    and actor_id=pg_temp.stage_key('2',1) and acao='liberar' and observacao='Oficina liberada'),'exact web audit and derived actor');
  perform pg_temp.check(jsonb_array_length(r->'snapshot'->'history')=1 and jsonb_array_length(r->'snapshot'->'legacy_history')=1,'no duplicate exact log in unlinked cell history');
  perform pg_temp.check((pg_temp.call_stage(rid,p)->>'idempotent_replay')::boolean,'replay precedes stale versions/state validation');
  perform pg_temp.check((select count(*)=logs+1 from public.rm_logs_aprovacao),'replay emits no duplicate shared log');
  begin set local role authenticated; perform public.rm_web_mutate_v1(rid,'transition_stage_approval',p); raise exception 'FAIL: permitless replay';
  exception when insufficient_privilege then reset role; end;
  begin perform pg_temp.call_stage(rid,p||'{"observacao":"Changed body"}'); raise exception 'FAIL: changed replay';
  exception when unique_violation then null; end;
  perform pg_temp.stage_actor(8);
  begin perform pg_temp.call_stage(rid,p); raise exception 'FAIL: actor changed replay'; exception when unique_violation then null; end;
  perform pg_temp.stage_actor(1);
  insert into auth.mfa_factors(user_id,factor_type,status) values(auth.uid(),'totp','verified');
  begin perform pg_temp.call_stage(rid,p); raise exception 'FAIL: AAL1 replay'; exception when insufficient_privilege then null; end;
  perform pg_temp.stage_actor(1,'aal2');
  perform pg_temp.check((pg_temp.call_stage(rid,p)->>'idempotent_replay')::boolean,'MFA enforced for replay');
  update rm_private.sso_identity_bindings set enabled=false where auth_user_id=auth.uid();
  begin perform pg_temp.call_stage(rid,p); raise exception 'FAIL: disabled binding replay'; exception when insufficient_privilege then null; end;
  update rm_private.sso_identity_bindings set enabled=true where auth_user_id=auth.uid();
  insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at)
    values(extensions.digest('stage-mobile-fixture','sha256'),auth.uid(),pg_temp.stage_key('2',1),pg_temp.stage_key('2',1),clock_timestamp()+interval '1 day');
  set local role authenticated;
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.stage_key('6',2),'p_status','retornado'),'stage-mobile-fixture');
  reset role;
  p:=pg_temp.stage_payload(2,'aprovar');
  mobile_params:=jsonb_build_object('p_aprovacao_etapa_id',pg_temp.stage_key('7',2),'p_acao','retornar','p_observacao','Mobile returned');
  set local role authenticated;
  r:=public.rm_mobile_mutate_v1('fa000000-0000-4000-8000-000000000001','rm_transition_stage_approval_v1',mobile_params,'stage-mobile-fixture');
  perform pg_temp.check((public.rm_mobile_mutate_v1('fa000000-0000-4000-8000-000000000001','rm_transition_stage_approval_v1',mobile_params,'stage-mobile-fixture')->>'idempotent_replay')::boolean,'old mobile payload replay preserved');
  reset role;
  perform pg_temp.reject_stage(p,'PT409');
  perform pg_temp.check((select status='nulo' from public.rm_aprovacoes_etapas where id=pg_temp.stage_key('7',1)),'mobile return reopens web release');
  perform pg_temp.check((select count(*)=1 from public.rm_web_stage_decisions),'mobile history not assigned invented web action');
  set local role authenticated;
  perform public.rm_mobile_mutate_v1(gen_random_uuid(),'rm_update_cell_status_v1',jsonb_build_object('p_celula_projeto_id',pg_temp.stage_key('6',1),'p_status','em_dia'),'stage-mobile-fixture');
  reset role;
  perform pg_temp.call_stage(gen_random_uuid(),pg_temp.stage_payload(1));
  perform pg_temp.call_stage(gen_random_uuid(),pg_temp.stage_payload(2,'aprovar'));
  perform pg_temp.check((select count(*)=3 from public.rm_web_stage_decisions),'release-return-release-approve web audits append');
  perform pg_temp.check((select celula_projeto_id is null from public.rm_aprovacoes_etapas where id=pg_temp.stage_key('7',1)),'legacy null allocation linkage never rewritten');
end $$;

-- RLS and direct-write/execute permissions are explicit for every new surface.
set local role authenticated;
select set_config('request.jwt.claim.sub',pg_temp.stage_key('1',9)::text,true);
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1)) is null,'inactive user cannot read snapshot');
select pg_temp.check((public.rm_web_stage_approvals_v1()->>'total')::int=0,'inactive user list is empty');
select pg_temp.check((select count(*)=0 from public.rm_web_stage_decisions),'inactive exact-history RLS');
select set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
select pg_temp.check(public.rm_web_stage_approval_snapshot_v1(pg_temp.stage_key('7',1)) is null,'unbound user cannot read snapshot');
reset role;
select pg_temp.check((select bool_and(not prosecdef and provolatile='s') from pg_proc where oid in
 ('public.rm_web_stage_approval_snapshot_v1(uuid)'::regprocedure,
 'public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer)'::regprocedure)),'read RPCs stable invoker');
select pg_temp.check(not has_function_privilege('anon','public.rm_web_stage_approval_snapshot_v1(uuid)','execute')
 and not has_function_privilege('service_role','public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer)','execute'),'read RPC ACL');
select pg_temp.check(not has_function_privilege('authenticated','public.rm_transition_stage_approval_v1(uuid,uuid,text,text)','execute')
 and not has_function_privilege('service_role','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute'),'no legacy/private mutation bypass');
select pg_temp.check(not has_table_privilege('authenticated','public.rm_web_stage_decisions','insert')
 and not has_table_privilege('service_role','public.rm_web_stage_decisions','update'),'direct exact-history writes denied');
rollback;

-- Committed fixtures are ONLY for the disposable local database. Two actual
-- connections race web versus mobile in both directions on the same project.
begin;
create extension if not exists dblink with schema public;
create schema rm_test_stage;
create function rm_test_stage.check(v boolean,msg text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAIL: %',msg; end if; end $$;
insert into auth.users(id) values('1c000000-0000-4000-8000-000000000001'),('1c000000-0000-4000-8000-000000000002');
insert into public.rm_users(id,auth_user_id,nome,perfil) values
 ('2c000000-0000-4000-8000-000000000001','1c000000-0000-4000-8000-000000000001','Concurrent stage A','administrador'),
 ('2c000000-0000-4000-8000-000000000002','1c000000-0000-4000-8000-000000000002','Concurrent stage B','administrador');
insert into auth.sessions(id,user_id) values
 ('3c000000-0000-4000-8000-000000000001','1c000000-0000-4000-8000-000000000001'),
 ('3c000000-0000-4000-8000-000000000002','1c000000-0000-4000-8000-000000000002');
insert into rm_private.sso_identity_bindings(id,issuer,subject,rm_user_id,auth_user_id,enabled,approved_by,approved_at) values
 ('8c000000-0000-4000-8000-000000000001','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9c000000-0000-4000-8000-000000000001',
  '2c000000-0000-4000-8000-000000000001','1c000000-0000-4000-8000-000000000001',true,'2c000000-0000-4000-8000-000000000001',clock_timestamp()),
 ('8c000000-0000-4000-8000-000000000002','https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1','9c000000-0000-4000-8000-000000000002',
  '2c000000-0000-4000-8000-000000000002','1c000000-0000-4000-8000-000000000002',true,'2c000000-0000-4000-8000-000000000001',clock_timestamp());
select public.rm_sso_session_put_v1(repeat('c',64),'8c000000-0000-4000-8000-000000000001','3c000000-0000-4000-8000-000000000001','opaque-fixture-stage-a',clock_timestamp()+interval '45 minutes');
select public.rm_sso_session_put_v1(repeat('d',64),'8c000000-0000-4000-8000-000000000002','3c000000-0000-4000-8000-000000000002','opaque-fixture-stage-b',clock_timestamp()+interval '45 minutes');
insert into rm_private.operator_delegations(token_hash,auth_user_id,tablet_user_id,operator_id,expires_at) values
 (extensions.digest('concurrent-stage-a','sha256'),'1c000000-0000-4000-8000-000000000001','2c000000-0000-4000-8000-000000000001','2c000000-0000-4000-8000-000000000001',clock_timestamp()+interval '1 day'),
 (extensions.digest('concurrent-stage-b','sha256'),'1c000000-0000-4000-8000-000000000002','2c000000-0000-4000-8000-000000000002','2c000000-0000-4000-8000-000000000002',clock_timestamp()+interval '1 day');
update rm_private.sso_settings set require_sso=true;
insert into public.rm_celulas(id,nome) values
 ('4c000000-0000-4000-8000-000000000001','Stage race origin'),('4c000000-0000-4000-8000-000000000002','Stage race destination');
insert into public.rm_projetos(id,numero) values
 ('5c000000-0000-4000-8000-000000000001','STAGE-RACE-WEB'),('5c000000-0000-4000-8000-000000000002','STAGE-RACE-MOBILE'),
 ('5c000000-0000-4000-8000-000000000003','STAGE-RACE-REPLAY');
insert into public.rm_celulas_projeto(projeto_id,celula_id,status,visibilidade)
  select p.id,c.id,case when c.id='4c000000-0000-4000-8000-000000000001' then 'em_dia'::public.rm_status_cel_proj_enum
    else 'pendente'::public.rm_status_cel_proj_enum end,c.id='4c000000-0000-4000-8000-000000000001'
  from public.rm_projetos p cross join public.rm_celulas c
  where p.id in('5c000000-0000-4000-8000-000000000001','5c000000-0000-4000-8000-000000000002','5c000000-0000-4000-8000-000000000003')
    and c.id in('4c000000-0000-4000-8000-000000000001','4c000000-0000-4000-8000-000000000002');
insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_origem_id,celula_destino_id,status_cel_proj,bloquear_avanco_sem_aprov) values
 ('7c000000-0000-4000-8000-000000000001','5c000000-0000-4000-8000-000000000001','4c000000-0000-4000-8000-000000000001','4c000000-0000-4000-8000-000000000002','em_dia',true),
 ('7c000000-0000-4000-8000-000000000002','5c000000-0000-4000-8000-000000000002','4c000000-0000-4000-8000-000000000001','4c000000-0000-4000-8000-000000000002','em_dia',true),
 ('7c000000-0000-4000-8000-000000000003','5c000000-0000-4000-8000-000000000003','4c000000-0000-4000-8000-000000000001','4c000000-0000-4000-8000-000000000002','em_dia',true);
create function rm_test_stage.run(p_actor integer,p_mode text,p_submission uuid,p_payload jsonb,p_hold real default 0)
returns jsonb language plpgsql as $$
declare result jsonb; state text; begin
  perform set_config('request.jwt.claim.sub','1c000000-0000-4000-8000-'||lpad(p_actor::text,12,'0'),true);
  perform set_config('request.jwt.claims',jsonb_build_object('session_id','3c000000-0000-4000-8000-'||lpad(p_actor::text,12,'0'),'aal','aal1')::text,true);
  if p_mode='web' then
    perform public.rm_sso_action_permit_v1(repeat(case p_actor when 1 then 'c' else 'd' end,64),p_submission,'transition_stage_approval',p_payload,'em.approvals.decide');
    set local role authenticated; result:=public.rm_web_mutate_v1(p_submission,'transition_stage_approval',p_payload); reset role;
  elsif p_mode='mobile' then
    set local role authenticated;
    result:=public.rm_mobile_mutate_v1(p_submission,'rm_transition_stage_approval_v1',p_payload,'concurrent-stage-'||case p_actor when 1 then 'a' else 'b' end);
    reset role;
  end if;
  perform pg_sleep(p_hold);
  return jsonb_build_object('sqlstate','00000','result',result);
exception when others then reset role; get stacked diagnostics state=returned_sqlstate;
  return jsonb_build_object('sqlstate',state);
end $$;
commit;
do $$ declare a jsonb; b jsonb; web_payload jsonb; mobile_payload jsonb; stage_id uuid; project_id uuid;
  pid_a integer; pid_b integer; waited integer; scenario integer; rid_a uuid; rid_b uuid; mode_a text; mode_b text;
begin
  perform dblink_connect('stage_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
  perform dblink_connect('stage_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres');
  select pid into pid_a from dblink('stage_a','select pg_backend_pid()') as t(pid integer);
  select pid into pid_b from dblink('stage_b','select pg_backend_pid()') as t(pid integer);
  for scenario in 1..3 loop
    stage_id:=('7c000000-0000-4000-8000-'||lpad(scenario::text,12,'0'))::uuid;
    project_id:=('5c000000-0000-4000-8000-'||lpad(scenario::text,12,'0'))::uuid;
    select jsonb_build_object('aprovacao_etapa_id',s.id,'expected_updated_at',s.updated_at,
      'expected_cell_updated_at',cp.updated_at,'acao','liberar','observacao',null) into web_payload
      from public.rm_aprovacoes_etapas s join public.rm_celulas_projeto cp on cp.projeto_id=s.projeto_id and cp.celula_id=s.celula_origem_id where s.id=stage_id;
    mobile_payload:=jsonb_build_object('p_aprovacao_etapa_id',stage_id,'p_acao','liberar');
    rid_a:=gen_random_uuid(); rid_b:=case when scenario=3 then rid_a else gen_random_uuid() end;
    mode_a:=case when scenario=2 then 'mobile' else 'web' end;
    mode_b:=case when scenario=1 then 'mobile' else 'web' end;
    perform dblink_send_query('stage_a',format('select rm_test_stage.run(1,%L,%L,%L::jsonb,1.0)',mode_a,rid_a,
      case when mode_a='web' then web_payload::text else mobile_payload::text end));
    waited:=0;
    loop
      perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_a and wait_event='PgSleep');
      waited:=waited+1; if waited>200 then raise exception 'FAIL: stage A did not hold transaction'; end if; perform pg_sleep(0.01);
    end loop;
    perform dblink_send_query('stage_b',format('select rm_test_stage.run(%s,%L,%L,%L::jsonb,0)',case when scenario=3 then 1 else 2 end,
      mode_b,rid_b,case when mode_b='web' then web_payload::text else mobile_payload::text end));
    waited:=0;
    loop
      perform pg_stat_clear_snapshot(); exit when exists(select 1 from pg_stat_activity where pid=pid_b and wait_event_type='Lock');
      waited:=waited+1; if waited>100 then raise exception 'FAIL: stage B did not contend on the shared transaction'; end if; perform pg_sleep(0.005);
    end loop;
    select r into a from dblink_get_result('stage_a') as t(r jsonb); perform r from dblink_get_result('stage_a') as t(r jsonb);
    select r into b from dblink_get_result('stage_b') as t(r jsonb); perform r from dblink_get_result('stage_b') as t(r jsonb);
    perform rm_test_stage.check(a->>'sqlstate'='00000','first concurrent actor succeeds');
    perform rm_test_stage.check(b->>'sqlstate'=case scenario when 1 then '22023' when 2 then 'PT409' else '00000' end,'loser sees new state or exact retry');
    if scenario=3 then perform rm_test_stage.check((b->'result'->>'idempotent_replay')::boolean,'concurrent same UUID replay'); end if;
    perform rm_test_stage.check((select count(*)=1 from public.rm_logs_aprovacao where projeto_id=project_id),'one log despite concurrent callers');
    perform rm_test_stage.check((select count(*)=case when scenario=2 then 0 else 1 end from public.rm_web_stage_decisions where projeto_id=project_id),'exact audit follows actual winning channel');
    perform rm_test_stage.check((select count(*)=1 from public.rm_aprovacoes_etapas where projeto_id=project_id and status_cel_proj='retornado'),'one return path despite concurrent callers');
    perform rm_test_stage.check((select status='para_execu__o' and visibilidade from public.rm_celulas_projeto
      where projeto_id=project_id and celula_id='4c000000-0000-4000-8000-000000000002'),'shared destination advances exactly once');
  end loop;
  perform dblink_disconnect('stage_a'); perform dblink_disconnect('stage_b');
exception when others then
  if 'stage_a'=any(dblink_get_connections()) then perform dblink_disconnect('stage_a'); end if;
  if 'stage_b'=any(dblink_get_connections()) then perform dblink_disconnect('stage_b'); end if; raise;
end $$;
select 'PASS: stage list/snapshot, operational authorization, exclusive actions, SSO/MFA/replay, exact audit, real concurrent web/mobile and simultaneous retry' as result;
