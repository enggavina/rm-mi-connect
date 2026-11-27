begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.assert_workshop_route_targets_v1(p_operation text,p_payload jsonb,p_office uuid)
returns void language plpgsql stable set search_path='' as $$
declare
 project uuid:=(p_payload->>'projeto_id')::uuid;
 forms jsonb;
begin
 if p_operation='save_project_route' then
  if jsonb_typeof(p_payload->'items') is distinct from 'array' then
   raise exception 'Informe as etapas do roteiro.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_payload->'items') item
   where not exists(select 1 from public.rm_celulas_projeto a where a.id=(item->>'id')::uuid
    and a.projeto_id=project and rm_private.workshop_cell_owned_v1(a.celula_id,p_office))) then
   raise exception 'Etapa fora da oficina ou do roteiro confirmado.' using errcode='42501';
  end if;
  return;
 end if;

 if not exists(select 1 from public.rm_celulas_projeto a where a.id=(p_payload->>'celula_projeto_id')::uuid
  and a.projeto_id=project and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)) then
  raise exception 'Etapa fora da oficina ou do roteiro confirmado.' using errcode='42501';
 end if;
 forms:=case when p_operation='assign_form_reviewer' then jsonb_build_array(p_payload->'form_id')
  when p_payload->>'action'='forms' then p_payload->'forms_ids' end;
 if jsonb_typeof(forms)='array' and exists(select 1 from jsonb_array_elements_text(forms) form_id
  where not rm_private.workshop_read_owned_v1('form_model',form_id::uuid,p_office)) then
  raise exception 'Formulário de outra oficina ou com origem pendente.' using errcode='42501';
 end if;
exception when invalid_text_representation then
 raise exception 'Etapa ou formulário inválido.' using errcode='22023';
end
$$;
revoke all on function rm_private.assert_workshop_route_targets_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell','save_project_route','manage_project_route_cell','assign_form_reviewer'));

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_gantt_workshop_v1(uuid,text,jsonb)'::regprocedure);
 operations text:='not in(''save_gantt_plan'',''save_gantt_settings'',''plan_cell'')';
 route_operations text:='''save_project_route'',''manage_project_route_cell'',''assign_form_reviewer''';
 project_body text:='if p_operation in(''save_gantt_settings'',''plan_cell'') then';
 route_guard text:='if p_operation<>''plan_cell'' and exists(select';
 before_write text:=' result:=rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);';
begin
 if array_length(string_to_array(issuer,operations),1) is distinct from 2
  or array_length(string_to_array(writer,operations),1) is distinct from 2
  or array_length(string_to_array(writer,project_body),1) is distinct from 2
  or array_length(string_to_array(writer,route_guard),1) is distinct from 2
  or array_length(string_to_array(writer,before_write),1) is distinct from 2 then
  raise exception 'Unexpected scoped planning mutation';
 end if;
 execute replace(issuer,operations,'not in(''save_gantt_plan'',''save_gantt_settings'',''plan_cell'','||route_operations||')');
 writer:=replace(writer,operations,'not in(''save_gantt_plan'',''save_gantt_settings'',''plan_cell'','||route_operations||')');
 writer:=replace(writer,project_body,'if p_operation in(''save_gantt_settings'',''plan_cell'','||route_operations||') then');
 writer:=replace(writer,route_guard,'if p_operation in(''save_gantt_plan'',''save_gantt_settings'',''save_project_route'') and exists(select');
 execute replace(writer,before_write,' if p_operation in('||route_operations||') then'||chr(10)||
  '  perform rm_private.assert_workshop_route_targets_v1(p_operation,p_payload,permit.workshop_id);'||chr(10)||
  ' end if;'||chr(10)||before_write);
end
$extend$;
notify pgrst,'reload schema';
commit;
