begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_media_reference_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare
 keys text[];
 media_id uuid;
 source text;
 photo_index int;
 result jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object'
  or jsonb_typeof(p_args->'id') is distinct from 'string' or jsonb_typeof(p_args->'source') is distinct from 'string' then
  raise exception 'Identificação da mídia inválida.' using errcode='22023';
 end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_args) k;
 media_id:=(p_args->>'id')::uuid;
 source:=p_args->>'source';
 if source='project_photo' and keys=array['id','source'] then
  select jsonb_build_object('id',p.id,'file',p.foto_url) into result
  from public.rm_fotos p where p.id=media_id and not p.lixeira
   and rm_private.workshop_project_owned_v1(p.projeto_id,p_office)
   and (p.celula_id is null or rm_private.workshop_cell_owned_v1(p.celula_id,p_office))
   and (p.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a
    where a.id=p.celula_projeto_id and a.projeto_id=p.projeto_id and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)
     and (p.celula_id is null or p.celula_id=a.celula_id)));
 elsif source='answer_signature' and keys=array['id','source'] then
  select jsonb_build_object('id',a.id,'file',a.assinatura_url) into result
  from public.rm_respostas a join public.rm_registros_formulario r on r.id=a.registro_formulario_id
  where a.id=media_id and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office);
 elsif source='answer_photo' and keys=array['id','index','source'] and jsonb_typeof(p_args->'index')='number'
  and p_args->>'index' ~ '^(0|[1-9][0-9]{0,5})$' then
  photo_index:=(p_args->>'index')::int;
  select jsonb_build_object('id',a.id,'file',a.fotos_urls[photo_index+array_lower(a.fotos_urls,1)]) into result
  from public.rm_respostas a join public.rm_registros_formulario r on r.id=a.registro_formulario_id
  where a.id=media_id and photo_index<cardinality(a.fotos_urls)
   and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office);
 else
  raise exception 'Identificação da mídia inválida.' using errcode='22023';
 end if;
 return result;
exception when invalid_text_representation then
 raise exception 'Identificação da mídia inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_media_reference_v1(jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference')
);
do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 tail text:='''workshop_twin'',''planning_export'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,tail),1) is distinct from 2 or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,tail,'''workshop_twin'',''planning_export'',''media_reference'')');
 execute replace(reader,dispatch,'  when ''media_reference'' then rm_private.workshop_media_reference_v1(p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;
