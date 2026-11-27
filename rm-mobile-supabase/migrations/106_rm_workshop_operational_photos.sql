begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Keep the established photo lifecycle and DTO. The new reader replaces the
-- legacy name match with the official workshop and cell binding of each title.
do $snapshot$
declare
 definition text:=pg_get_functiondef('public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 context_end constant text:='where p.id=p_project_id and a.id=p_allocation_id';
 title_start constant text:='  select t.* from public.rm_cadastro_fotos t cross join context c where ';
 title_end constant text:=' ), photo_rows as (';
 header constant text:='public.rm_web_operational_photos_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_titles boolean DEFAULT false)';
 title_id constant text:='''celula_projeto_id'',f.celula_projeto_id,''cadastro_foto_id'',f.cadastro_foto_id';
begin
 if array_length(string_to_array(definition,header),1) is distinct from 2
  or array_length(string_to_array(definition,context_end),1) is distinct from 2
  or array_length(string_to_array(definition,title_start),1) is distinct from 2
  or array_length(string_to_array(definition,title_end),1) is distinct from 2
  or array_length(string_to_array(definition,title_id),1) is distinct from 2 then
  raise exception 'Unexpected operational photo snapshot contract';
 end if;
 definition:=replace(definition,header,'rm_private.workshop_operational_photo_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_titles boolean, p_office uuid)');
 definition:=replace(definition,E' STABLE\n',E' STABLE SECURITY DEFINER\n');
 definition:=replace(definition,context_end,context_end||$scope$
   and p_office is not null and rm_private.can_read_project_dossier_v1()
   and rm_private.workshop_project_owned_v1(p.id,p_office) and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)$scope$);
 definition:=left(definition,strpos(definition,title_start)-1)||$titles$
  select t.* from context c join rm_private.engineering_photo_title_scope s
   on s.workshop_id=p_office and (s.cell_id is null or s.cell_id=c.celula_id)
  join public.rm_cadastro_fotos t on t.id=s.title_id
  where nullif(rm_private.catalog_name_key(t.titulo),'') is not null
$titles$||substring(definition from strpos(definition,title_end));
 execute replace(definition,title_id,$dto$'celula_projeto_id',f.celula_projeto_id,'cadastro_foto_id',
   case when rm_private.workshop_engineering_title_v1(f.cadastro_foto_id,p_office) then f.cadastro_foto_id end$dto$);
end
$snapshot$;

create function rm_private.workshop_operational_photo_read_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
begin
 if p_office is null or jsonb_typeof(p_args->'project') is distinct from 'string'
  or jsonb_typeof(p_args->'allocation') is distinct from 'string' or jsonb_typeof(p_args->'include') is distinct from 'boolean' then
  raise exception 'Consulta de fotos previstas inválida.' using errcode='22023';
 end if;
 return rm_private.workshop_operational_photo_snapshot_v1((p_args->>'project')::uuid,(p_args->>'allocation')::uuid,(p_args->>'include')::boolean,p_office);
end
$$;

create function rm_private.operational_photo_snapshot_for_write_v1(p_submission uuid,p_project uuid,p_allocation uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare office uuid;
begin
 -- The enclosing planning writer has already validated and locked this permit.
 select workshop_id into office from rm_private.gantt_workshop_write_permits
 where submission_id=p_submission and operation='manage_operational_photos';
 if found then return rm_private.workshop_operational_photo_snapshot_v1(p_project,p_allocation,true,office);end if;
 return public.rm_web_operational_photos_snapshot_v1(p_project,p_allocation,true);
end
$$;
revoke all on function rm_private.workshop_operational_photo_snapshot_v1(uuid,uuid,boolean,uuid),
 rm_private.workshop_operational_photo_read_v1(jsonb,uuid),rm_private.operational_photo_snapshot_for_write_v1(uuid,uuid,uuid)
 from public,anon,authenticated,service_role;

do $install$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 planning_issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 planner text:=pg_get_functiondef('rm_private.web_mutate_gantt_workshop_v1(uuid,text,jsonb)'::regprocedure);
 photo_writer text:=pg_get_functiondef('rm_private.web_mutate_operational_photos_core_v1(uuid,text,jsonb)'::regprocedure);
 replacement_writer text:=pg_get_functiondef('rm_private.web_mutate_before_document_folders_v1(uuid,text,jsonb)'::regprocedure);
 allowed constant text:='''project_route'',''project_route_cell'')';
 dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 photo_call constant text:='snapshot:=public.rm_web_operational_photos_snapshot_v1(project_id,allocation_id,true);';
 replacement_call constant text:='snapshot:=public.rm_web_operational_photos_snapshot_v1(p.id,a.id,true);';
 bind_permit constant text:=' select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id;';
 missing_permit constant text:=' if not found then';
 constraint_definition text;
 planning_operations text:=substring(planning_issuer from 'p_operation not in[(][^)]*[)]');
 planner_scope constant text:='''manage_project_route_cell'',''assign_form_reviewer'',''manage_cell_availability'')';
begin
 if array_length(string_to_array(issuer,allowed),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2
  or array_length(string_to_array(planning_issuer,planning_operations),1) is distinct from 2
  or array_length(string_to_array(planner,planner_scope),1) is distinct from 4
  or array_length(string_to_array(planner,missing_permit),1) is distinct from 2
  or array_length(string_to_array(planner,bind_permit),1) is distinct from 2
  or array_length(string_to_array(photo_writer,photo_call),1) is distinct from 3
  or array_length(string_to_array(replacement_writer,replacement_call),1) is distinct from 3 then
  raise exception 'Unexpected workshop operational photo contract';
 end if;
 select pg_get_constraintdef(oid) into strict constraint_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(constraint_definition from 8 for char_length(constraint_definition)-8)||') or resource=''operational_photos'')';
 select pg_get_constraintdef(oid) into strict constraint_definition from pg_constraint
 where conrelid='rm_private.gantt_workshop_write_permits'::regclass and conname='gantt_workshop_write_permits_operation_check';
 alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
 execute 'alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check check (('||
  substring(constraint_definition from 8 for char_length(constraint_definition)-8)||') or operation=''manage_operational_photos'')';

 execute replace(issuer,allowed,'''project_route'',''project_route_cell'',''operational_photos'')');
 execute replace(reader,dispatch,'  when ''operational_photos'' then rm_private.workshop_operational_photo_read_v1(p_args,permit.workshop_id)'||chr(10)||dispatch);
 execute replace(planning_issuer,planning_operations,left(planning_operations,-1)||',''manage_operational_photos'')');
 planner:=replace(planner,planner_scope,left(planner_scope,-1)||',''manage_operational_photos'')');
 planner:=replace(planner,bind_permit,$gate$
 if p_operation='manage_operational_photos' then
  perform pg_advisory_xact_lock_shared(hashtextextended('operational-photo-workshop-cutover',106));
 end if;$gate$||chr(10)||bind_permit);
 execute replace(planner,missing_permit,missing_permit||$gate$
  if p_operation='manage_operational_photos' then
   if has_function_privilege('authenticated','public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean)','execute') then
    return rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);
   end if;
   raise exception 'Confirme a oficina antes de alterar as fotos previstas.' using errcode='42501';
  end if;$gate$);
 execute replace(photo_writer,photo_call,'snapshot:=rm_private.operational_photo_snapshot_for_write_v1(p_client_submission_id,project_id,allocation_id);');
 execute replace(replacement_writer,replacement_call,'snapshot:=rm_private.operational_photo_snapshot_for_write_v1(p_client_submission_id,p.id,a.id);');
end
$install$;

create function rm_private.activate_operational_photo_workshop_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('operational-photo-workshop-cutover',106));
 if not exists(select 1 from rm_private.engineering_workshop_enforcement)
  or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced)
  or has_function_privilege('authenticated','public.rm_web_project_route_cell_snapshot_v1(uuid,uuid,boolean)','execute') then
  raise exception 'Confirme os controles de Engenharia, Planejamento e Roteiro por oficina.' using errcode='PT409';
 end if;
 revoke execute on function public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean) from authenticated;
 notify pgrst,'reload schema';
end
$$;
revoke all on function rm_private.activate_operational_photo_workshop_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
