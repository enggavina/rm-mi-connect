begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_android_receipt_confirmations (
 submission_id uuid primary key references rm_private.mobile_mutation_receipts(client_submission_id) on delete cascade,
 workshop_id uuid not null references rm_private.workshop_references(id),
 project_id uuid not null,
 last_retry_at timestamptz
);
alter table rm_private.workshop_android_receipt_confirmations enable row level security;
revoke all on rm_private.workshop_android_receipt_confirmations from public,anon,authenticated,service_role;

-- Only the scoped Android gateway can attach a workshop to a durable receipt.
-- The original write and its payload remain intact when a retry is observed.
do $record$
declare
 gateway text:=pg_get_functiondef('public.rm_mobile_workshop_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 marker constant text:=' return mutation_result||jsonb_build_object(''confirmacao'',confirmation);';
begin
 if array_length(string_to_array(gateway,marker),1) is distinct from 2 then raise exception 'Unexpected Android receipt writer';end if;
 execute replace(gateway,marker,$confirm$ insert into rm_private.workshop_android_receipt_confirmations as a
  (submission_id,workshop_id,project_id,last_retry_at)
 values(p_client_submission_id,permit.workshop_id,project,
  case when mutation_result->'idempotent_replay'='true'::jsonb then clock_timestamp() end)
 on conflict(submission_id) do update set last_retry_at=greatest(a.last_retry_at,excluded.last_retry_at)
 where a.workshop_id=excluded.workshop_id and a.project_id=excluded.project_id;
 if not found then raise exception 'O recibo pertence a outro contexto. Preserve o protocolo.' using errcode='PT409';end if;
$confirm$||marker);
end
$record$;

create function rm_private.workshop_android_protocol_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare protocol uuid; result jsonb;
begin
 if jsonb_typeof(p_args) is distinct from 'object' or (p_args-'protocol'-'forms'-'photos'-'approvals'-'planning')<>'{}'::jsonb
  or jsonb_typeof(p_args->'protocol') is distinct from 'string'
  or jsonb_typeof(p_args->'forms') is distinct from 'boolean' or jsonb_typeof(p_args->'photos') is distinct from 'boolean'
  or jsonb_typeof(p_args->'approvals') is distinct from 'boolean' or jsonb_typeof(p_args->'planning') is distinct from 'boolean' then
  raise exception 'Consulta de protocolo inválida.' using errcode='22023';end if;
 protocol:=(p_args->>'protocol')::uuid;

 select jsonb_build_object('protocol',protocol,'operation','rm_submit_recebimento_v1','project_id',s.project_id,'project_number',p.numero,
  'phase',case when r.created_at is not null then 'confirmed' else 'opened' end,
  'recorded_at',coalesce(r.created_at,o.created_at),'last_retry_at',null,'form_record_id',null) into result
 from rm_private.receiving_workshop_protocols s join public.rm_projetos p on p.id=s.project_id and p.equipamento_id=s.equipment_id
 left join rm_private.receiving_openings o on o.client_submission_id=s.submission_id and o.project_id=s.project_id
  and o.equipment_id=s.equipment_id and o.auth_user_id=s.auth_user_id and o.operator_id=s.operator_id and s.opened_at is not null
 left join rm_private.mobile_mutation_receipts r on r.client_submission_id=s.submission_id and r.rpc_name='rm_submit_recebimento_v1'
  and r.auth_user_id=s.auth_user_id and r.operator_id=s.operator_id and s.completed_at is not null
  and r.result->>'projeto_id'=s.project_id::text and r.result->>'equipamento_id'=s.equipment_id::text
  and r.result->'resource_deleted' is distinct from 'true'::jsonb
 where s.submission_id=protocol and s.workshop_id=p_office and rm_private.workshop_project_owned_v1(s.project_id,p_office)
  and (r.created_at is not null or o.created_at is not null);
 if found then return result;end if;

 select jsonb_build_object('protocol',protocol,'operation',r.rpc_name,'project_id',a.project_id,'project_number',p.numero,
  'phase','confirmed','recorded_at',r.created_at,'last_retry_at',a.last_retry_at,'form_record_id',f.id) into result
 from rm_private.workshop_android_receipt_confirmations a
 join rm_private.mobile_mutation_receipts r on r.client_submission_id=a.submission_id
 join public.rm_projetos p on p.id=a.project_id
 left join public.rm_registros_formulario f on r.rpc_name in('rm_submit_form_inspection_v1','rm_submit_form_revision_v1')
  and f.id=case when r.result->>'registro_formulario_id' ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    then (r.result->>'registro_formulario_id')::uuid end and f.projeto_id=a.project_id
  and rm_private.workshop_form_record_owned_v1(f.projeto_id,f.celula_id,f.form_id,p_office)
 where a.submission_id=protocol and a.workshop_id=p_office and rm_private.workshop_project_owned_v1(a.project_id,p_office)
  and jsonb_typeof(r.result)='object' and r.result->'resource_deleted' is distinct from 'true'::jsonb
  and case r.rpc_name
   when 'rm_submit_form_inspection_v1' then p_args->'forms'='true'::jsonb
   when 'rm_submit_form_revision_v1' then p_args->'forms'='true'::jsonb
   when 'rm_record_cell_photo_v1' then p_args->'photos'='true'::jsonb
   when 'rm_transition_stage_approval_v1' then p_args->'approvals'='true'::jsonb
   when 'rm_update_cell_status_v1' then p_args->'planning'='true'::jsonb
   when 'rm_record_execution_event_v1' then p_args->'planning'='true'::jsonb
   when 'rm_add_cell_comment_v1' then true else false end;
 return result;
exception when invalid_text_representation then
 raise exception 'Consulta de protocolo inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_android_protocol_v1(jsonb,uuid) from public,anon,authenticated,service_role;

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 allowed constant text:='''form_record_detail'',''project_equipment_type'')';
 dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 constraint_definition text;
begin
 if array_length(string_to_array(issuer,allowed),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then raise exception 'Unexpected protocol read contract';end if;
 select pg_get_constraintdef(oid) into strict constraint_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(constraint_definition from 8 for char_length(constraint_definition)-8)||') or resource=''android_protocol'')';
 execute replace(issuer,allowed,left(allowed,-1)||',''android_protocol'')');
 execute replace(reader,dispatch,$query$  when 'android_protocol' then rm_private.workshop_android_protocol_v1(p_args,permit.workshop_id)
$query$||dispatch);
end
$extend$;

notify pgrst,'reload schema';
commit;
