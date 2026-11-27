begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Historical receipts belong to the original office, even after the legacy
-- device is retired. The current portal context still authorizes every read.
create function rm_private.legacy_receiving_protocol_v1(p_protocol uuid,p_office uuid) returns jsonb
language sql stable set search_path='' as $$
 with opening as (
  select * from rm_private.receiving_openings where client_submission_id=p_protocol
 ), receipt as (
  select * from rm_private.mobile_mutation_receipts where client_submission_id=p_protocol
 ), evidence as (
  select coalesce(r.result->>'projeto_id',o.project_id::text) as project_id,
   coalesce(r.result->>'equipamento_id',o.equipment_id::text) as equipment_id,
   coalesce(r.auth_user_id,o.auth_user_id) as auth_user_id,coalesce(r.operator_id,o.operator_id) as operator_id,
   coalesce(r.created_at,o.created_at) as recorded_at,r.client_submission_id is not null as confirmed
  from opening o full join receipt r using(client_submission_id)
  where r.client_submission_id is null or (
   r.rpc_name='rm_submit_recebimento_v1' and nullif(r.params->>'p_projeto_id','') is null
   and r.result->'resource_deleted' is distinct from 'true'::jsonb
   and r.result->>'projeto_id' is not null and r.result->>'equipamento_id' is not null
   and (o.client_submission_id is null or
    (o.project_id::text,o.equipment_id::text,o.auth_user_id,o.operator_id) is not distinct from
    (r.result->>'projeto_id',r.result->>'equipamento_id',r.auth_user_id,r.operator_id)))
 )
 select jsonb_build_object('protocol',p_protocol,'operation','rm_submit_recebimento_v1','project_id',p.id,'project_number',p.numero,
  'phase',case when ev.confirmed then 'confirmed' else 'opened' end,'recorded_at',ev.recorded_at,
  'last_retry_at',null,'form_record_id',null)
 from evidence ev join public.rm_projetos p
  on p.id=case when ev.project_id ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then ev.project_id::uuid end
  and p.created_by_user_id=ev.operator_id
 join public.rm_equipamentos equipment on equipment.id=p.equipamento_id and equipment.projeto_id=p.id and equipment.id::text=ev.equipment_id
 join rm_private.workshop_legacy_catalog_access legacy
  on legacy.singleton and legacy.auth_user_id=ev.auth_user_id and legacy.workshop_id=p_office
 where rm_private.workshop_project_owned_v1(p.id,p_office)
  and not exists(select 1 from rm_private.receiving_workshop_protocols where submission_id=p_protocol)
  and not exists(select 1 from rm_private.workshop_android_receipt_confirmations where submission_id=p_protocol);
$$;
revoke all on function rm_private.legacy_receiving_protocol_v1(uuid,uuid) from public,anon,authenticated,service_role;

do $lookup$
declare
 reader text:=pg_get_functiondef('rm_private.workshop_android_protocol_v1(jsonb,uuid)'::regprocedure);
 marker constant text:=' return result;'||chr(10)||'exception when invalid_text_representation then';
begin
 if array_length(string_to_array(reader,marker),1) is distinct from 2 then raise exception 'Unexpected Android protocol lookup boundary';end if;
 execute replace(reader,marker,$fallback$ if found then return result; end if;
 return rm_private.legacy_receiving_protocol_v1(protocol,p_office);
exception when invalid_text_representation then$fallback$);
end
$lookup$;

notify pgrst,'reload schema';
commit;
