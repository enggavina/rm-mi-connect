begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_form_record_owned_v1(p_project uuid,p_cell uuid,p_form uuid,p_office uuid)
returns boolean language sql stable set search_path='' as $$
 select rm_private.workshop_project_owned_v1(p_project,p_office)
  and (p_cell is null or rm_private.workshop_cell_owned_v1(p_cell,p_office))
  and rm_private.workshop_read_owned_v1('form_model',p_form,p_office)
$$;
revoke all on function rm_private.workshop_form_record_owned_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function rm_private.workshop_form_record_read_v1(p_resource text,p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare
 keys text[];
 record_id uuid;
 page_number int;
 search text;
 status_filter text;
 project_details boolean;
 result jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' then
  raise exception 'Consulta de formulários inválida.' using errcode='22023';
 end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_args) k;
 if p_resource='form_record_project' and keys=array['id'] and jsonb_typeof(p_args->'id')='string' then
  record_id:=(p_args->>'id')::uuid;
  select jsonb_build_object('project_id',r.projeto_id,'form_id',r.form_id,'cell_id',r.celula_id) into result
  from public.rm_registros_formulario r where r.id=record_id
   and rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office);
  return result;
 end if;

 if p_resource is distinct from 'form_record_list' or keys is distinct from array['page','project_details','q','status']
  or jsonb_typeof(p_args->'page') is distinct from 'number' or p_args->>'page' !~ '^[1-9][0-9]{0,4}$'
  or jsonb_typeof(p_args->'project_details') is distinct from 'boolean'
  or jsonb_typeof(p_args->'q') is distinct from 'string' or length(p_args->>'q')>100
  or jsonb_typeof(p_args->'status') not in ('string','null') or length(p_args->>'status')>64 then
  raise exception 'Consulta de formulários inválida.' using errcode='22023';
 end if;
 page_number:=(p_args->>'page')::int;
 search:=p_args->>'q';
 status_filter:=nullif(p_args->>'status','');
 project_details:=(p_args->>'project_details')::boolean;

 with filtered as materialized (
  select r.id,r.projeto_id,r.numero_projeto_rm,r.form_id,r.codigo,r.codigo_text,r.descricao,r.status,r.created_at,r.updated_at
  from public.rm_registros_formulario r
  where rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,p_office)
   and (status_filter is null or r.status::text=status_filter)
   and (search='' or r.numero_projeto_rm ilike '%'||search||'%' or r.codigo_text ilike '%'||search||'%'
    or r.descricao ilike '%'||search||'%')
 ), selected as materialized (
  select * from filtered order by updated_at desc,id offset (page_number-1)*25 limit 25
 )
 select jsonb_build_object('page',page_number,'pageSize',25,'total',(select count(*) from filtered),
  'rows',coalesce((select jsonb_agg(to_jsonb(s) order by updated_at desc,id) from selected s),'[]'),
  'forms',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'titulo',f.titulo,'title',f.title) order by f.id)
   from public.rm_forms f where f.id in(select form_id from selected)),'[]'),
  'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'numero',p.numero) order by p.id)
   from public.rm_projetos p where project_details and p.id in(select projeto_id from selected)),'[]')) into result;
 return result;
exception when invalid_text_representation then
 raise exception 'Consulta de formulários inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_form_record_read_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list')
);
do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 end_of_resources text:='''project_qr'',''document_link'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,end_of_resources),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,end_of_resources,'''project_qr'',''document_link'',''form_record_project'',''form_record_list'')');
 execute replace(reader,dispatch,'  when ''form_record_project'' then rm_private.workshop_form_record_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''form_record_list'' then rm_private.workshop_form_record_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;
