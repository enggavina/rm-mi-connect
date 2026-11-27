begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The existing permit is minted in a separate request. Only the gateway can
-- bind it to the transaction that runs the original receiving mutation.
alter table rm_private.mobile_receiving_workshop_permits add column gateway_xid xid8;

-- A permit expires after one request. Retain the workshop originally verified
-- for a protocol so that a later retry cannot drop back to a legacy route.
create table rm_private.receiving_workshop_protocols (
 submission_id uuid primary key,
 project_id uuid not null,
 equipment_id uuid not null,
 auth_user_id uuid not null,
 operator_id uuid not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 opened_at timestamptz,
 completed_at timestamptz,
 check(opened_at is not null or completed_at is not null)
);
alter table rm_private.receiving_workshop_protocols enable row level security;
revoke all on rm_private.receiving_workshop_protocols from public,anon,authenticated,service_role;

create or replace function rm_private.require_scoped_receiving_draft_submission_v1(
 p_submission uuid,p_phase text,p_params jsonb,p_operator uuid,p_token text
) returns void language plpgsql set search_path='' as $$
declare
 permit_office uuid;
 legacy_office uuid;
 protocol_offices uuid[];
 target_offices uuid[];
 enforced boolean;
begin
 select activated_at is not null into strict enforced from rm_private.workshop_root_enforcement where singleton;
 select legacy_workshop_id into legacy_office from rm_private.workshop_legacy_adoption where singleton;
 select array(select workshop_id from rm_private.receiving_draft_workshops where draft_id=p_submission
  union select workshop_id from rm_private.receiving_project_recoveries where submission_id=p_submission
  union select workshop_id from rm_private.receiving_workshop_protocols where submission_id=p_submission) into protocol_offices;
 select array(
  select o.workshop_id from rm_private.workshop_object_origins o
  where o.object_kind='project' and o.object_id in(
   select nullif(p_params->>'p_projeto_id','')::uuid
   union select project_id from rm_private.receiving_openings where client_submission_id=p_submission
   union select nullif(result->>'projeto_id','')::uuid from rm_private.mobile_mutation_receipts
    where client_submission_id=p_submission and rpc_name='rm_submit_recebimento_v1'
  )
  union select scope from (values
   (rm_private.workshop_catalog_scope_v1('client',nullif(p_params->>'p_cliente_id','')::uuid)),
   (rm_private.workshop_catalog_scope_v1('equipment_type',nullif(p_params->>'p_tipo_equipamento_id','')::uuid))
  ) catalog(scope) where scope is not null
 ) into target_offices;
 if not enforced and cardinality(protocol_offices)=0
  and not exists(select 1 from rm_private.mobile_receiving_workshop_permits where submission_id=p_submission)
  and not exists(select 1 from unnest(target_offices) office where office is distinct from legacy_office) then
  return;
 end if;
 select a.workshop_id into permit_office from rm_private.mobile_receiving_workshop_permits a
 where a.submission_id=p_submission and a.phase=p_phase and a.auth_user_id=auth.uid()
  and a.auth_session_id::text=auth.jwt()->>'session_id' and a.operator_id=p_operator
  and a.operator_hash=extensions.digest(p_token,'sha256') and a.payload_hash=extensions.digest(p_params::text,'sha256')
  and a.gateway_xid=pg_current_xact_id_if_assigned() and a.expires_at>clock_timestamp();
 if permit_office is null or not ((protocol_offices||target_offices) <@ array[permit_office]) then
  raise exception 'Confirme a oficina do recebimento antes de enviar. O protocolo continua preservado.' using errcode='42501';
 end if;
end
$$;

do $integrate$
declare
 gateway text:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 opener text:=pg_get_functiondef('public.rm_mobile_open_receiving_v1(uuid,jsonb,text)'::regprocedure);
 completer text:=pg_get_functiondef('rm_private.mobile_mutate_before_execution_v1(uuid,text,jsonb,text)'::regprocedure);
 cutover text:=pg_get_functiondef('rm_private.activate_workshop_root_enforcement_v1()'::regprocedure);
 submission_lock constant text:='perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));';
 shared_lock constant text:='perform pg_advisory_xact_lock_shared(hashtextextended(''workshop-receiving-cutover'',109));';
 execute_point constant text:=' if p_phase=''open'' then';
 consume_point constant text:=' delete from rm_private.mobile_receiving_workshop_permits where submission_id=p_client_submission_id and phase=p_phase;';
 activation_lock constant text:=' lock table public.rm_celulas,public.rm_projetos in share row exclusive mode;';
begin
 if array_length(string_to_array(gateway,submission_lock),1) is distinct from 2
  or array_length(string_to_array(opener,submission_lock),1) is distinct from 2
  or array_length(string_to_array(completer,submission_lock),1) is distinct from 2
  or array_length(string_to_array(gateway,execute_point),1) is distinct from 2
  or array_length(string_to_array(gateway,consume_point),1) is distinct from 2
  or array_length(string_to_array(cutover,activation_lock),1) is distinct from 2 then
  raise exception 'Unexpected receiving protocol boundary';
 end if;
 gateway:=replace(gateway,submission_lock,shared_lock||chr(10)||' '||submission_lock);
 execute replace(opener,submission_lock,shared_lock||chr(10)||' '||submission_lock);
 execute replace(completer,submission_lock,
  'if p_rpc_name=''rm_submit_recebimento_v1'' then '||shared_lock||'end if;'||chr(10)||'  '||submission_lock);
 gateway:=replace(gateway,execute_point,$patch$
 update rm_private.mobile_receiving_workshop_permits set gateway_xid=pg_current_xact_id()
  where submission_id=p_client_submission_id and phase=p_phase;
$patch$||execute_point);
 execute replace(gateway,consume_point,$patch$
 insert into rm_private.receiving_workshop_protocols as binding
  (submission_id,project_id,equipment_id,auth_user_id,operator_id,workshop_id,opened_at,completed_at)
 values(p_client_submission_id,(result->>'projeto_id')::uuid,(result->>'equipamento_id')::uuid,auth.uid(),actor.operator_id,
  permit.workshop_id,case when p_phase='open' then clock_timestamp() end,case when p_phase='complete' then clock_timestamp() end)
 on conflict(submission_id) do update set opened_at=coalesce(binding.opened_at,excluded.opened_at),
  completed_at=coalesce(binding.completed_at,excluded.completed_at)
 where binding.project_id=excluded.project_id and binding.equipment_id=excluded.equipment_id
  and binding.auth_user_id=excluded.auth_user_id and binding.operator_id=excluded.operator_id
  and binding.workshop_id=excluded.workshop_id;
 if not found then
  raise exception 'O protocolo pertence a outro recebimento. Preserve o envio original.' using errcode='PT409';
 end if;
$patch$||consume_point);
 execute replace(cutover,activation_lock,$patch$
 perform pg_advisory_xact_lock(hashtextextended('workshop-receiving-cutover',109));
$patch$||activation_lock);
end
$integrate$;

notify pgrst,'reload schema';
commit;
