begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The review history belongs to the project. Choices and edit versions use only
-- eligible memberships in the current, independently verified workshop roster.
do $snapshot$
declare
 definition text:=pg_get_functiondef('public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 header constant text:='public.rm_web_form_reviewer_assignments_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_eligible boolean DEFAULT false)';
 context_end constant text:='where p.id=p_project_id and a.id=p_allocation_id';
 members_end constant text:='where t.celula_id=c.celula_id';
 output_end constant text:='from context c cross join counts n;';
 assignment_warning constant text:='when a.id is not null and not exists(select 1 from eligible e where e.id=a.avaliador_user_id)';
begin
 if array_length(string_to_array(definition,header),1) is distinct from 2
  or array_length(string_to_array(definition,E' STABLE\n'),1) is distinct from 2
  or array_length(string_to_array(definition,context_end),1) is distinct from 2
  or array_length(string_to_array(definition,members_end),1) is distinct from 2
  or array_length(string_to_array(definition,output_end),1) is distinct from 2
  or array_length(string_to_array(definition,assignment_warning),1) is distinct from 2 then
  raise exception 'Unexpected form reviewer snapshot contract';
 end if;
 definition:=replace(definition,header,'rm_private.workshop_form_reviewer_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_eligible boolean, p_office uuid, p_people uuid[])');
 definition:=replace(definition,E' STABLE\n',E' STABLE SECURITY DEFINER\n');
 definition:=replace(definition,context_end,context_end||$scope$
   and p_office is not null and rm_private.can_read_project_dossier_v1()
   and rm_private.workshop_project_owned_v1(p.id,p_office)
   and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)$scope$);
 definition:=replace(definition,members_end,members_end||' and p_include_eligible and t.identidade_id=any(p_people)');
 definition:=replace(definition,output_end,$scope$from context c cross join counts n
  where not exists(select 1 from definitions f where not rm_private.workshop_read_visible_v1('form_model',f.id,p_office));$scope$);
 execute replace(definition,assignment_warning,replace(assignment_warning,'when a.id','when p_include_eligible and a.id'));
end
$snapshot$;

create function rm_private.form_reviewer_snapshot_for_write_v1(p_submission uuid,p_project uuid,p_allocation uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare office uuid; people uuid[];
begin
 -- The assignment writer has already verified and locked the current permit.
 select workshop_id,eligible_ids into office,people from rm_private.workshop_assignment_permits
 where submission_id=p_submission and operation='assign_form_reviewer';
 if found then return rm_private.workshop_form_reviewer_snapshot_v1(p_project,p_allocation,true,office,people);end if;
 return public.rm_web_form_reviewer_assignments_snapshot_v1(p_project,p_allocation,true);
end
$$;
revoke all on function rm_private.workshop_form_reviewer_snapshot_v1(uuid,uuid,boolean,uuid,uuid[]),
 rm_private.form_reviewer_snapshot_for_write_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

do $integrate$
declare
 reader text:=pg_get_functiondef('rm_private.workshop_assignment_read_v1(text,jsonb,uuid,uuid)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_form_reviewer_core_v1(uuid,text,jsonb)'::regprocedure);
 selection_start constant text:=' result:=public.rm_web_form_reviewer_assignments_snapshot_v1(project,allocation,include_choices);';
 selection_end constant text:='exception when invalid_text_representation then';
 legacy_snapshot constant text:='snapshot:=public.rm_web_form_reviewer_assignments_snapshot_v1(project_id,allocation_id,true);';
begin
 if array_length(string_to_array(reader,selection_start),1) is distinct from 2
  or array_length(string_to_array(reader,selection_end),1) is distinct from 2
  or strpos(reader,selection_start)>=strpos(reader,selection_end)
  or array_length(string_to_array(writer,legacy_snapshot),1) is distinct from 3 then
  raise exception 'Unexpected form reviewer assignment integration';
 end if;
 reader:=left(reader,strpos(reader,selection_start)-1)||$select$
 return rm_private.workshop_form_reviewer_snapshot_v1(project,allocation,include_choices,p_office,coalesce(allowed,'{}'));
$select$||substring(reader from strpos(reader,selection_end));
 execute reader;
 execute replace(writer,legacy_snapshot,'snapshot:=rm_private.form_reviewer_snapshot_for_write_v1(p_client_submission_id,project_id,allocation_id);');
end
$integrate$;

create function rm_private.activate_workshop_form_reviewers_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 if not exists(select 1 from rm_private.workshop_assignment_enforcement where singleton)
  or has_function_privilege('authenticated','public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean)','execute') then
  raise exception 'Ative a consulta de avaliadores por oficina.' using errcode='PT409';
 end if;
 revoke select on public.rm_form_reviewer_assignments from authenticated;
 notify pgrst,'reload schema';
end
$$;
revoke all on function rm_private.activate_workshop_form_reviewers_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
