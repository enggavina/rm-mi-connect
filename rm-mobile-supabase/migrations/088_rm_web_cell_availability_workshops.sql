begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.cell_availability_workshop_enforcement(
 singleton boolean primary key check(singleton),
 activated_at timestamptz not null
);
alter table rm_private.cell_availability_workshop_enforcement enable row level security;
revoke all on rm_private.cell_availability_workshop_enforcement from public,anon,authenticated,service_role;

create function rm_private.activate_cell_availability_workshops_v1() returns void
language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('cell-availability-workshop-cutover',28));
 if exists(select 1 from public.rm_celulas_projeto a
  left join rm_private.workshop_project_ownership p on p.id=a.projeto_id
  left join rm_private.workshop_cell_ownership c on c.cell_id=a.celula_id
  where p.workshop_id is null or p.workshop_id is distinct from c.workshop_id) then
  raise exception 'Há alocações com origem pendente ou divergente.' using errcode='PT409';
 end if;
 insert into rm_private.cell_availability_workshop_enforcement values(true,clock_timestamp()) on conflict(singleton) do nothing;
 -- All supported portal reads now go through the request-bound office check.
 revoke execute on function public.rm_web_cell_availability_snapshot_v1(uuid,uuid) from authenticated;
 revoke execute on function rm_private.cell_availability_metadata_v1(uuid) from authenticated;
 perform pg_notify('pgrst','reload schema');
end
$$;
revoke all on function rm_private.activate_cell_availability_workshops_v1() from public,anon,authenticated,service_role;

create function rm_private.workshop_cell_availability_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare project uuid; allocation uuid;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object'
  or jsonb_typeof(p_args->'project_id') is distinct from 'string'
  or jsonb_typeof(p_args->'allocation_id') is distinct from 'string'
  or p_args-array['project_id','allocation_id']<>'{}'::jsonb then
  raise exception 'Projeto ou alocação inválida.' using errcode='22023';
 end if;
 project:=(p_args->>'project_id')::uuid; allocation:=(p_args->>'allocation_id')::uuid;
 if not rm_private.workshop_project_owned_v1(project,p_office) or not exists(
  select 1 from public.rm_celulas_projeto a where a.id=allocation and a.projeto_id=project
   and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)
 ) then return null;end if;
 return public.rm_web_cell_availability_snapshot_v1(project,allocation);
exception when invalid_text_representation then
 raise exception 'Projeto ou alocação inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_cell_availability_v1(jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell','save_project_route','manage_project_route_cell','assign_form_reviewer',
  'save_capacity_resource','save_capacity_bookings','manage_cell_availability'));
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot','cell_availability'));

-- Keep the version, lifecycle checks, locks, and replay in their existing writer.
-- The route removal command can also retire an allocation, so it uses this same cutover.
do $availability$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_gantt_workshop_v1(uuid,text,jsonb)'::regprocedure);
 read_issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 last_issue_operation constant text:='''save_capacity_bookings'')';
 last_target_operation constant text:='''assign_form_reviewer'')';
 last_resource constant text:='''capacity_snapshot'')';
 read_dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 select_permit constant text:=' select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id;';
 allow_legacy constant text:=' if not found then';
begin
 if array_length(string_to_array(issuer,last_issue_operation),1) is distinct from 2
  or array_length(string_to_array(writer,last_target_operation),1) is distinct from 4
  or array_length(string_to_array(writer,select_permit),1) is distinct from 2
  or array_length(string_to_array(writer,allow_legacy),1) is distinct from 2
  or array_length(string_to_array(read_issuer,last_resource),1) is distinct from 2
  or array_length(string_to_array(reader,read_dispatch),1) is distinct from 2 then raise exception 'Unexpected scoped cell availability contract';end if;
 execute replace(issuer,last_issue_operation,'''save_capacity_bookings'',''manage_cell_availability'')');
 execute replace(read_issuer,last_resource,'''capacity_snapshot'',''cell_availability'')');
 execute replace(reader,read_dispatch,'  when ''cell_availability'' then rm_private.workshop_cell_availability_v1(p_args,permit.workshop_id)'||chr(10)||read_dispatch);
 writer:=replace(writer,last_target_operation,'''assign_form_reviewer'',''manage_cell_availability'')');
 writer:=replace(writer,select_permit,$guard$
 if p_operation in('manage_cell_availability','manage_project_route_cell') then
  perform pg_advisory_xact_lock_shared(hashtextextended('cell-availability-workshop-cutover',28));
 end if;$guard$||chr(10)||select_permit);
 execute replace(writer,allow_legacy,allow_legacy||$guard$
  if p_operation in('manage_cell_availability','manage_project_route_cell')
   and exists(select 1 from rm_private.cell_availability_workshop_enforcement where singleton) then
   raise exception 'Confirme a oficina antes de alterar esta alocação.' using errcode='42501';
  end if;$guard$);
end
$availability$;
notify pgrst,'reload schema';
commit;
