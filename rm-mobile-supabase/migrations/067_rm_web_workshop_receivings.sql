begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Work with the same receiving contract and canonical equipment type as the
-- portal. Filter office ownership before search, summary, pagination or totals.
do $build$
declare
 definition text:=pg_get_functiondef('public.rm_web_receivings_v1(text,text,integer,integer)'::regprocedure);
 signature text:='FUNCTION public.rm_web_receivings_v1(p_reason ';
 base_scope text:='where p.data_real_de_entrega is null';
 allocation_source text:='from public.rm_celulas_projeto group by projeto_id';
 client_join text:='left join public.rm_clientes c on c.id=p.cliente_id';
 type_join text:='left join public.rm_tipos_equipamento t on t.id=rm_private.effective_project_type_v1(p)';
 type_projection text:='rm_private.effective_project_type_v1(p) effective_type_id';
 client_projection text:='''cliente_id'',p.cliente_id';
begin
 if strpos(definition,signature)=0 or strpos(definition,base_scope)=0
   or strpos(definition,allocation_source)=0 or strpos(definition,client_join)=0
   or strpos(definition,type_join)=0 or strpos(definition,type_projection)=0 or strpos(definition,client_projection)=0 then
  raise exception 'Unexpected receiving list projection';
 end if;
 definition:=replace(definition,signature,'FUNCTION rm_private.workshop_receivings_v1(p_office uuid, p_reason ');
 definition:=replace(definition,base_scope,base_scope||' and rm_private.workshop_project_owned_v1(p.id,p_office)');
 definition:=replace(definition,allocation_source,$scope$from public.rm_celulas_projeto
      where rm_private.workshop_project_owned_v1(projeto_id,p_office)
        and rm_private.workshop_cell_owned_v1(celula_id,p_office)
      group by projeto_id$scope$);
 definition:=replace(definition,client_join,client_join||' and rm_private.workshop_read_owned_v1(''client'',c.id,p_office)');
 definition:=replace(definition,type_join,type_join||' and rm_private.workshop_read_owned_v1(''equipment_type'',t.id,p_office)');
 definition:=replace(definition,type_projection,'t.id effective_type_id,c.id scoped_client_id');
 definition:=replace(definition,'rm_private.effective_project_type_v1(p) is null','t.id is null');
 definition:=replace(definition,client_projection,'''cliente_id'',p.scoped_client_id');
 execute definition;
end
$build$;
revoke all on function rm_private.workshop_receivings_v1(uuid,text,text,integer,integer) from public,anon,authenticated,service_role;

create function rm_private.workshop_receiving_read_v1(p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
begin
 if jsonb_typeof(p_args) is distinct from 'object' or
  (select array_agg(k order by k) from jsonb_object_keys(p_args) k) is distinct from array['page','q','reason']
  or jsonb_typeof(p_args->'page') is distinct from 'number' or p_args->>'page' !~ '^[1-9][0-9]{0,4}$'
  or jsonb_typeof(p_args->'q') is distinct from 'string' or jsonb_typeof(p_args->'reason') is distinct from 'string' then
  raise exception 'Filtros de recebimento inválidos.' using errcode='22023';
 end if;
 return rm_private.workshop_receivings_v1(p_office,p_args->>'reason',p_args->>'q',(p_args->>'page')::integer,25);
end
$$;
revoke all on function rm_private.workshop_receiving_read_v1(jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list')
);

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 end_of_resources text:='''gantt_cells'',''operation_validation'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,end_of_resources),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,end_of_resources,'''gantt_cells'',''operation_validation'',''receiving_list'')');
 execute replace(reader,dispatch,'  when ''receiving_list'' then rm_private.workshop_receiving_read_v1(p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;
