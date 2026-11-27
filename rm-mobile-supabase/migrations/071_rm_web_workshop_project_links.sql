begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_project_link_v1(p_resource text,p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare
 keys text[];
 record_id uuid;
 result jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object'
  or jsonb_typeof(p_args->'id') is distinct from 'string' then
  raise exception 'Identificação inválida.' using errcode='22023';
 end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_args) k;
 record_id:=(p_args->>'id')::uuid;

 if p_resource='project_qr' and keys=array['id'] then
  select jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,
   'descricao_equipamento',p.descricao_equipamento,'updated_at',p.updated_at) into result
  from public.rm_projetos p where p.id=record_id and rm_private.workshop_project_owned_v1(p.id,p_office);
 elsif p_resource='document_link' and keys=array['id','source'] and jsonb_typeof(p_args->'source')='string' then
  case p_args->>'source'
   when 'invoice' then
    select jsonb_build_object('id',p.id,'file',p.arquivo_nota_fiscal_url) into result
    from public.rm_projetos p where p.id=record_id and rm_private.workshop_project_owned_v1(p.id,p_office);
   when 'documentos' then
    select jsonb_build_object('id',d.id,'file',d.arquivo_url) into result
    from public.rm_documentos d where d.id=record_id and rm_private.workshop_project_owned_v1(d.projeto_id,p_office);
   when 'docs' then
    select jsonb_build_object('id',d.id,'file',d.arquivo_url) into result
    from public.rm_docs d where d.id=record_id and rm_private.workshop_project_owned_v1(d.projeto_id,p_office);
   else raise exception 'Origem do documento inválida.' using errcode='22023';
  end case;
 else
  raise exception 'Identificação inválida.' using errcode='22023';
 end if;
 return result;
exception when invalid_text_representation then
 raise exception 'Identificação inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_project_link_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link')
);
do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 end_of_resources text:='''operation_validation'',''receiving_list'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,end_of_resources),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,end_of_resources,'''operation_validation'',''receiving_list'',''project_qr'',''document_link'')');
 execute replace(reader,dispatch,'  when ''project_qr'' then rm_private.workshop_project_link_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''document_link'' then rm_private.workshop_project_link_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;
