begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

alter table rm_private.form_review_workshop_permits drop constraint form_review_workshop_permits_operation_check;
alter table rm_private.form_review_workshop_permits add constraint form_review_workshop_permits_operation_check
 check(operation in('review_form','transition_stage_approval'));

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_form_review_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_form_review_workshop_v1(uuid,text,jsonb)'::regprocedure);
 issuer_op text:='p_operation <> ''review_form''';
 capability text:='''em.forms.review''';
 wrapper_op text:='if p_operation is distinct from ''review_form'' then';
 form_arg text:='target_id:=(p_payload->>''registro_formulario_id'')::uuid;';
 project_lookup text:='select projeto_id into project_id from public.rm_registros_formulario where id=target_id;';
 registration_lookup text:=' select * into registration from public.rm_registros_formulario where id=target_id for update;';
 before_write text:=' result:=rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id,p_operation,p_payload);';
begin
 if array_length(string_to_array(issuer,issuer_op),1) is distinct from 2
  or array_length(string_to_array(issuer,capability),1) is distinct from 2
  or array_length(string_to_array(writer,wrapper_op),1) is distinct from 2
  or array_length(string_to_array(writer,form_arg),1) is distinct from 2
  or array_length(string_to_array(writer,project_lookup),1) is distinct from 2
  or array_length(string_to_array(writer,registration_lookup),1) is distinct from 2
  or array_length(string_to_array(writer,before_write),1) is distinct from 2 then
  raise exception 'Unexpected scoped review mutation';
 end if;
 issuer:=replace(issuer,issuer_op,'p_operation not in(''review_form'',''transition_stage_approval'')');
 execute replace(issuer,capability,$cap$case when p_operation='review_form' then 'em.forms.review' else 'em.approvals.decide' end$cap$);
 writer:=replace(writer,wrapper_op,'if p_operation is null or p_operation not in(''review_form'',''transition_stage_approval'') then');
 writer:=replace(writer,form_arg,$id$target_id:=(p_payload->>case when p_operation='review_form' then 'registro_formulario_id' else 'aprovacao_etapa_id' end)::uuid;$id$);
 writer:=replace(writer,project_lookup,$project$if p_operation='review_form' then
  select projeto_id into project_id from public.rm_registros_formulario where id=target_id;
 else
  select projeto_id into project_id from public.rm_aprovacoes_etapas where id=target_id;
 end if;$project$);
 writer:=replace(writer,registration_lookup,' if p_operation=''review_form'' then'||chr(10)||registration_lookup);
 execute replace(writer,before_write,$stage$
 else
  perform 1 from public.rm_aprovacoes_etapas where id=target_id and projeto_id=project_id for update;
  if not found or not rm_private.workshop_stage_owned_v1(target_id,permit.workshop_id) then
   raise exception 'Aprovação indisponível nesta oficina.' using errcode='42501';
  end if;
 end if;$stage$||before_write);
end
$extend$;
notify pgrst,'reload schema';
commit;
