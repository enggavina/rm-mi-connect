begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell'));

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_gantt_workshop_v1(uuid,text,jsonb)'::regprocedure);
 operations text:='not in(''save_gantt_plan'',''save_gantt_settings'')';
 single_project text:='if p_operation=''save_gantt_settings'' then';
 route_guard text:='if exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=project_id and not a.retirada';
 before_write text:=' result:=rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);';
begin
 if array_length(string_to_array(issuer,operations),1) is distinct from 2
  or array_length(string_to_array(writer,operations),1) is distinct from 2
  or array_length(string_to_array(writer,single_project),1) is distinct from 2
  or array_length(string_to_array(writer,route_guard),1) is distinct from 2
  or array_length(string_to_array(writer,before_write),1) is distinct from 2 then
  raise exception 'Unexpected scoped planning mutation';
 end if;
 execute replace(issuer,operations,'not in(''save_gantt_plan'',''save_gantt_settings'',''plan_cell'')');
 writer:=replace(writer,operations,'not in(''save_gantt_plan'',''save_gantt_settings'',''plan_cell'')');
 writer:=replace(writer,single_project,'if p_operation in(''save_gantt_settings'',''plan_cell'') then');
 writer:=replace(writer,route_guard,'if p_operation<>''plan_cell'' and exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=project_id and not a.retirada');
 execute replace(writer,before_write,$scope$
 if p_operation='plan_cell' then
  begin
   perform rm_private.workshop_assert_origin_v1('cell',(p_payload->>'celula_id')::uuid,permit.workshop_id);
   if jsonb_typeof(p_payload#>'{changes,forms_ids}')='array' and exists(
    select 1 from jsonb_array_elements_text(p_payload#>'{changes,forms_ids}') form_id
    where not rm_private.workshop_read_owned_v1('form_model',form_id::uuid,permit.workshop_id)) then
    raise exception 'Formulário de outra oficina ou com origem pendente.' using errcode='42501';
   end if;
  exception when invalid_text_representation then
   raise exception 'Célula ou formulário inválido.' using errcode='22023';
  end;
 end if;$scope$||before_write);
end
$extend$;
notify pgrst,'reload schema';
commit;
