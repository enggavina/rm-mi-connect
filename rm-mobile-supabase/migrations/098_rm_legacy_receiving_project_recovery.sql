begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.receiving_project_recoveries (
 submission_id uuid primary key,
 project_id uuid not null unique,
 workshop_id uuid not null,
 auth_user_id uuid not null,
 operator_id uuid not null,
 basis text not null check(basis in('opening_original','opening_metadata','receipt_exact','receipt_metadata')),
 evidence_sha256 text not null check(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 recovered_at timestamptz not null default clock_timestamp()
);
alter table rm_private.receiving_project_recoveries enable row level security;
revoke all on rm_private.receiving_project_recoveries from public,anon,authenticated,service_role;

-- The scoped caller has verified the live Central context and holds both the
-- submission and project locks. Only evidence from the original intake can
-- classify an existing project. A declined recovery still follows the normal
-- scoped origin assertion and never retries against the unscoped gateway.
create function rm_private.recover_legacy_receiving_project_v1(
 p_submission uuid,p_project uuid,p_phase text,p_params jsonb,p_operator uuid,p_office uuid
) returns void language plpgsql set search_path='' as $$
declare
 opening rm_private.receiving_openings;
 receipt rm_private.mobile_mutation_receipts;
 project public.rm_projetos;
 client uuid;
 equipment uuid;
 normalized jsonb:=p_params-'p_operador_id'-'p_tablet_user_id'-'p_client_submission_id';
 proof text;
 fingerprint text;
begin
 client:=nullif(normalized->>'p_cliente_id','')::uuid;
 if client is null or nullif(normalized->>'p_projeto_id','') is not null
  or rm_private.workshop_catalog_scope_v1('client',client) is distinct from p_office
  or exists(select 1 from rm_private.workshop_project_ownership where id=p_project)
  or rm_private.project_deleted_v1(p_project) then return;end if;

 select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_submission;
 if found and (receipt.rpc_name is distinct from 'rm_submit_recebimento_v1'
  or receipt.auth_user_id is distinct from auth.uid() or receipt.operator_id is distinct from p_operator
  or receipt.result->>'resource_deleted'='true' or receipt.result->>'projeto_id' is distinct from p_project::text) then
  return;
 end if;
 select * into opening from rm_private.receiving_openings where client_submission_id=p_submission;
 if found then
  if opening.auth_user_id is distinct from auth.uid() or opening.operator_id is distinct from p_operator
   or opening.project_id is distinct from p_project then return;end if;
  if p_phase='open' then
   proof:='opening_original';
   fingerprint:=encode(sha256(convert_to(normalized::text,'UTF8')),'hex');
   if fingerprint is distinct from opening.original_sha256 then return;end if;
  elsif p_phase='complete' then
   proof:='opening_metadata';
   fingerprint:=encode(sha256(convert_to(rm_private.receiving_metadata_v1(normalized)::text,'UTF8')),'hex');
   if fingerprint is distinct from opening.metadata_sha256
    or receipt.client_submission_id is not null and receipt.params is distinct from normalized then return;end if;
  end if;
  equipment:=opening.equipment_id;
 elsif receipt.client_submission_id is not null then
  -- A QR update to a pre-existing project does not prove how it was created.
  if nullif(receipt.params->>'p_projeto_id','') is not null or receipt.result->>'updated_existing'='true' then return;end if;
  if p_phase='complete' and receipt.params=normalized then
   proof:='receipt_exact';
   fingerprint:=encode(sha256(convert_to(receipt.params::text,'UTF8')),'hex');
  elsif p_phase='open' and rm_private.receiving_metadata_v1(receipt.params)=rm_private.receiving_metadata_v1(normalized) then
   proof:='receipt_metadata';
   fingerprint:=encode(sha256(convert_to(rm_private.receiving_metadata_v1(receipt.params)::text,'UTF8')),'hex');
  end if;
  equipment:=nullif(receipt.result->>'equipamento_id','')::uuid;
 end if;
 if proof is null or equipment is null then return;end if;

 select * into project from public.rm_projetos where id=p_project for update;
 if not found or project.created_by_user_id is distinct from p_operator or project.cliente_id is distinct from client
  or project.equipamento_id is distinct from equipment
  or not exists(select 1 from public.rm_equipamentos e where e.id=equipment and e.projeto_id=p_project) then return;end if;

 insert into rm_private.workshop_project_ownership(id,workshop_id) values(p_project,p_office)
 on conflict(id) do nothing;
 if not found then return;end if;
 insert into rm_private.receiving_project_recoveries(submission_id,project_id,workshop_id,auth_user_id,operator_id,basis,evidence_sha256)
 values(p_submission,p_project,p_office,auth.uid(),p_operator,proof,fingerprint);
end
$$;
revoke all on function rm_private.recover_legacy_receiving_project_v1(uuid,uuid,text,jsonb,uuid,uuid) from public,anon,authenticated,service_role;

-- Tighten the existing raw-retry protection for recovered projects, including
-- protocols whose earlier client did not save an associated draft.
create or replace function rm_private.require_scoped_receiving_draft_submission_v1(
 p_submission uuid,p_phase text,p_params jsonb,p_operator uuid,p_token text
) returns void language plpgsql set search_path='' as $$
begin
 if exists(select 1 from (
   select workshop_id from rm_private.receiving_draft_workshops where draft_id=p_submission
   union
   select workshop_id from rm_private.receiving_project_recoveries where submission_id=p_submission
  ) expected where not exists(select 1 from rm_private.mobile_receiving_workshop_permits a
   where a.submission_id=p_submission and a.phase=p_phase and a.workshop_id=expected.workshop_id and a.auth_user_id=auth.uid()
    and a.auth_session_id::text=auth.jwt()->>'session_id' and a.operator_id=p_operator
    and a.operator_hash=extensions.digest(p_token,'sha256') and a.payload_hash=extensions.digest(p_params::text,'sha256')
    and a.expires_at>clock_timestamp())) then
  raise exception 'Confirme a oficina do recebimento antes de enviar. O protocolo continua preservado.' using errcode='42501';
 end if;
end
$$;

do $gateway$
declare
 definition text:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 marker constant text:='  perform rm_private.workshop_assert_origin_v1(''project'',project_id,permit.workshop_id);';
begin
 if array_length(string_to_array(definition,marker),1) is distinct from 2 then
  raise exception 'Unexpected receiving project confirmation boundary';
 end if;
 execute replace(definition,marker,$patch$  if linked_project is not null then
   perform rm_private.recover_legacy_receiving_project_v1(p_client_submission_id,project_id,p_phase,p_params,actor.operator_id,permit.workshop_id);
  end if;
$patch$||marker);
end
$gateway$;

notify pgrst,'reload schema';
commit;
