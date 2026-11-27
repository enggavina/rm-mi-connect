begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- A verified replay can recover an old project. It cannot prove how the
-- project was created. Keep prior protocols intact and leave that fact unknown.
alter table rm_private.receiving_workshop_protocols add column creation_phase text;
alter table rm_private.receiving_workshop_protocols add constraint receiving_protocol_creation_phase_check check (
 creation_phase is null or (creation_phase='open' and opened_at is not null)
 or (creation_phase='complete' and completed_at is not null));

create function rm_private.workshop_receiving_creation_evidence_v1()
returns table(submission_id uuid, workshop_id uuid, creation_phase text, completed boolean)
language sql stable set search_path='' as $$
 select protocol.submission_id,protocol.workshop_id,protocol.creation_phase,
  protocol.completed_at is not null and (protocol.creation_phase='complete' or protocol.completed_at>=protocol.opened_at)
   and receipt.client_submission_id is not null
 from rm_private.receiving_workshop_protocols protocol
 join rm_private.workshop_project_ownership ownership
  on ownership.id=protocol.project_id and ownership.workshop_id=protocol.workshop_id
 join rm_private.workshop_object_origins origin
  on origin.object_kind='project' and origin.object_id=protocol.project_id and origin.workshop_id=protocol.workshop_id
 join public.rm_projetos project
  on project.id=protocol.project_id and project.equipamento_id=protocol.equipment_id
   and project.created_by_user_id=protocol.operator_id
 join public.rm_equipamentos equipment on equipment.id=protocol.equipment_id and equipment.projeto_id=protocol.project_id
 left join rm_private.receiving_openings opening on opening.client_submission_id=protocol.submission_id
 left join rm_private.mobile_mutation_receipts receipt
  on receipt.client_submission_id=protocol.submission_id and receipt.rpc_name='rm_submit_recebimento_v1'
   and receipt.auth_user_id=protocol.auth_user_id and receipt.operator_id=protocol.operator_id
   and receipt.result->>'projeto_id'=protocol.project_id::text and receipt.result->>'equipamento_id'=protocol.equipment_id::text
   and receipt.result->>'resource_deleted' is distinct from 'true'
 where not exists(select 1 from rm_private.workshop_origin_retirements retired
   where retired.object_kind='project' and retired.object_id=protocol.project_id)
  and ((protocol.creation_phase='open' and
    (opening.project_id,opening.equipment_id,opening.auth_user_id,opening.operator_id) is not distinct from
    (protocol.project_id,protocol.equipment_id,protocol.auth_user_id,protocol.operator_id))
   or (protocol.creation_phase='complete' and opening.client_submission_id is null));
$$;

create function rm_private.workshop_receiving_pilot_ready_v1() returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from rm_private.workshop_receiving_creation_evidence_v1() proof
  join rm_private.workshop_legacy_adoption adoption on adoption.singleton and adoption.legacy_workshop_id=proof.workshop_id
  where proof.creation_phase='open' and proof.completed);
$$;

revoke all on function rm_private.workshop_receiving_creation_evidence_v1(),rm_private.workshop_receiving_pilot_ready_v1()
 from public,anon,authenticated,service_role;

do $integrate$
declare
 gateway text:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 activate text:=pg_get_functiondef('rm_private.activate_workshop_root_enforcement_v1()'::regprocedure);
 columns_marker constant text:='(submission_id,project_id,equipment_id,auth_user_id,operator_id,workshop_id,opened_at,completed_at)';
 values_marker constant text:='permit.workshop_id,case when p_phase=''open'' then clock_timestamp() end,case when p_phase=''complete'' then clock_timestamp() end)';
 activation_marker constant text:=' alter table public.rm_projetos enable trigger workshop_new_project_origin;';
begin
 if array_length(string_to_array(gateway,columns_marker),1) is distinct from 2
  or array_length(string_to_array(gateway,values_marker),1) is distinct from 2
  or array_length(string_to_array(activate,activation_marker),1) is distinct from 2 then
  raise exception 'Unexpected receiving provenance contract';
 end if;
 gateway:=replace(gateway,columns_marker,left(columns_marker,-1)||',creation_phase)');
 -- project_id is null only on the gateway's new-root path. This branch has
 -- inserted the ownership above. Conflict updates never promote a replay.
 execute replace(gateway,values_marker,left(values_marker,-1)||',case when project_id is null then p_phase end)');
 execute replace(activate,activation_marker,$gate$
 if not rm_private.workshop_receiving_pilot_ready_v1() then
  raise exception 'Conclua um recebimento da oficina piloto com abertura e envio pelo mesmo protocolo autorizado.' using errcode='PT409';
 end if;
$gate$||activation_marker);
end
$integrate$;

notify pgrst,'reload schema';
commit;
