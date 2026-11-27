begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Keep historical configurations and evidence intact. Only the current
-- roster can contribute cell memberships, choices or optimistic versions.
do $snapshot$
declare
 definition text:=pg_get_functiondef('public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 header constant text:='public.rm_web_stage_rules_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_choices boolean DEFAULT false)';
 context_end constant text:='where p.id=p_project_id and a.id=p_allocation_id';
 members_end constant text:='where t.celula_id in(select celula_id from allocations)';
 restore_check constant text:='''can_restore'',not r.protected and not r.ativo';
begin
 if array_length(string_to_array(definition,header),1) is distinct from 2
  or array_length(string_to_array(definition,E' STABLE\n'),1) is distinct from 2
  or array_length(string_to_array(definition,context_end),1) is distinct from 2
  or array_length(string_to_array(definition,members_end),1) is distinct from 2
  or array_length(string_to_array(definition,restore_check),1) is distinct from 2 then
  raise exception 'Unexpected workshop stage rules snapshot contract';
 end if;
 definition:=replace(definition,header,'rm_private.workshop_stage_rules_snapshot_v1(p_project_id uuid, p_allocation_id uuid, p_include_choices boolean, p_office uuid, p_people uuid[])');
 definition:=replace(definition,E' STABLE\n',E' STABLE SECURITY DEFINER\n');
 definition:=replace(definition,context_end,context_end||$scope$
   and p_office is not null and rm_private.can_read_project_dossier_v1() and rm_private.workshop_project_owned_v1(p.id,p_office)
   and not exists(select 1 from public.rm_celulas_projeto route where route.projeto_id=p.id
    and not rm_private.workshop_cell_owned_v1(route.celula_id,p_office))
   and not exists(select 1 from public.rm_aprovacoes_etapas rule where rule.projeto_id=p.id and (
    not rm_private.workshop_cell_owned_v1(rule.celula_origem_id,p_office)
    or (rule.celula_destino_id is not null and not rm_private.workshop_cell_owned_v1(rule.celula_destino_id,p_office))))$scope$);
 definition:=replace(definition,members_end,members_end||' and t.identidade_id=any(p_people)');
 execute replace(definition,restore_check,restore_check||$restore$
    and coalesce(array_remove(array[r.aprovador_id]||r.aprovadores_ids||r.aprovadores_retorno_ids,null),'{}')<@p_people$restore$);
end
$snapshot$;

create function rm_private.stage_rules_snapshot_for_write_v1(p_submission uuid,p_project uuid,p_allocation uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare office uuid; people uuid[];
begin
 -- The enclosing assignment writer has already validated and locked this permit.
 select workshop_id,eligible_ids into office,people from rm_private.workshop_assignment_permits
 where submission_id=p_submission and operation='manage_stage_rules';
 if found then return rm_private.workshop_stage_rules_snapshot_v1(p_project,p_allocation,true,office,people);end if;
 return public.rm_web_stage_rules_snapshot_v1(p_project,p_allocation,true);
end
$$;
revoke all on function rm_private.workshop_stage_rules_snapshot_v1(uuid,uuid,boolean,uuid,uuid[]),
 rm_private.stage_rules_snapshot_for_write_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

do $integrate$
declare
 reader text:=pg_get_functiondef('rm_private.workshop_assignment_read_v1(text,jsonb,uuid,uuid)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_stage_rules_core_v1(uuid,text,jsonb)'::regprocedure);
 selection_start constant text:=$mark$ if p_resource='operational_reviewers' then
  result:=public.rm_web_form_reviewer_assignments_snapshot_v1$mark$;
 selection_end constant text:='exception when invalid_text_representation then';
 legacy_snapshot constant text:='snapshot:=public.rm_web_stage_rules_snapshot_v1(project_id,allocation_id,true);';
begin
 if array_length(string_to_array(reader,selection_start),1) is distinct from 2
  or array_length(string_to_array(reader,selection_end),1) is distinct from 2
  or array_length(string_to_array(writer,legacy_snapshot),1) is distinct from 3 then
  raise exception 'Unexpected stage rules assignment integration';
 end if;
 reader:=left(reader,strpos(reader,selection_start)-1)||$select$
 if p_resource='operational_stage_rules' then
  return rm_private.workshop_stage_rules_snapshot_v1(project,allocation,include_choices,p_office,coalesce(allowed,'{}'));
 end if;
 result:=public.rm_web_form_reviewer_assignments_snapshot_v1(project,allocation,include_choices);
 if exists(select 1 from jsonb_array_elements(result->'forms') f
  where not rm_private.workshop_read_visible_v1('form_model',(f->>'id')::uuid,p_office)) then return null;end if;
 if result is null or not include_choices or not (result->>'eligible_complete')::boolean then return result;end if;
 select coalesce(jsonb_agg(person order by ord),'[]') into choices from jsonb_array_elements(result->'eligible_users') with ordinality e(person,ord)
  where (person->>'id')::uuid=any(allowed);
 result:=result||jsonb_build_object('eligible_users',choices,'eligible_total',jsonb_array_length(choices));
 select coalesce(jsonb_agg(case when jsonb_typeof(f->'assignment')='object' then
   jsonb_set(f,'{assignment,eligible}',to_jsonb(exists(select 1 from jsonb_array_elements(choices) c
    where c->>'id'=f->'assignment'->>'avaliador_user_id'))) else f end order by ord),'[]') into rows
  from jsonb_array_elements(result->'forms') with ordinality e(f,ord);
 return jsonb_set(result,'{forms}',rows);
$select$||substring(reader from strpos(reader,selection_end));
 execute reader;
 execute replace(writer,legacy_snapshot,'snapshot:=rm_private.stage_rules_snapshot_for_write_v1(p_client_submission_id,project_id,allocation_id);');
end
$integrate$;

create function rm_private.activate_workshop_stage_proof_v1() returns void
language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 if not exists(select 1 from rm_private.workshop_assignment_enforcement where singleton)
  or has_function_privilege('authenticated','public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean)','execute')
  or has_function_privilege('authenticated','public.rm_web_project_route_snapshot_v1(uuid)','execute')
  or has_function_privilege('authenticated','public.rm_web_cell_availability_snapshot_v1(uuid,uuid)','execute') then
  raise exception 'Ative as consultas de atribuições, roteiro e disponibilidade por oficina.' using errcode='PT409';
 end if;
 revoke execute on function rm_private.stage_rule_metadata_v1(uuid) from authenticated;
 notify pgrst,'reload schema';
end
$$;
revoke all on function rm_private.activate_workshop_stage_proof_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
