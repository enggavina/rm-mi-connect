begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Preserve the existing projections and apply ownership before limits,
-- aggregation and lookup of related catalog fields.
do $build$
declare
 twin text:=pg_get_functiondef('public.rm_web_workshop_snapshot_v1()'::regprocedure);
 export_data text:=pg_get_functiondef('public.rm_web_planning_export_snapshot_v1(uuid[],text[])'::regprocedure);
begin
 if strpos(twin,'where p.data_real_de_entrega is null')=0
  or strpos(twin,'join cohort p on p.id=a.projeto_id where not a.retirada')=0
  or strpos(twin,'(select count(*) from public.rm_celulas) cells')=0
  or strpos(twin,'from public.rm_celulas c)')=0
  or strpos(export_data,'from public.rm_celulas where id=any(p_cell_ids)')=0
  or strpos(export_data,'and not a.retirada and p.id is null')=0 then
  raise exception 'Unexpected workshop output projections';
 end if;
 twin:=replace(twin,'FUNCTION public.rm_web_workshop_snapshot_v1()','FUNCTION rm_private.workshop_twin_snapshot_v1(p_office uuid)');
 twin:=replace(twin,'where p.data_real_de_entrega is null','where rm_private.workshop_project_owned_v1(p.id,p_office) and p.data_real_de_entrega is null');
 twin:=replace(twin,'join cohort p on p.id=a.projeto_id where not a.retirada',
  'join cohort p on p.id=a.projeto_id where not a.retirada and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)');
 twin:=replace(twin,'(select count(*) from public.rm_celulas) cells',
  '(select count(*) from public.rm_celulas c where rm_private.workshop_cell_owned_v1(c.id,p_office)) cells');
 twin:=replace(twin,'from public.rm_celulas c)',
  'from public.rm_celulas c where rm_private.workshop_cell_owned_v1(c.id,p_office))');
 twin:=replace(twin,'on c.id=p.cliente_id','on c.id=p.cliente_id and rm_private.workshop_read_owned_v1(''client'',c.id,p_office)');
 twin:=replace(twin,'on t.id=rm_private.effective_project_type_v1(p)',
  'on t.id=rm_private.effective_project_type_v1(p) and rm_private.workshop_read_owned_v1(''equipment_type'',t.id,p_office)');
 execute twin;

 export_data:=replace(export_data,'FUNCTION public.rm_web_planning_export_snapshot_v1(p_cell_ids ',
  'FUNCTION rm_private.workshop_planning_export_v1(p_office uuid, p_cell_ids ');
 export_data:=replace(export_data,'from public.rm_celulas where id=any(p_cell_ids)',
  'from public.rm_celulas where id=any(p_cell_ids) and rm_private.workshop_cell_owned_v1(id,p_office)');
 export_data:=replace(export_data,'and not a.retirada and p.id is null',
  'and not a.retirada and (p.id is null or not rm_private.workshop_project_owned_v1(p.id,p_office))');
 export_data:=replace(export_data,'cl.id=p.cliente_id','cl.id=p.cliente_id and rm_private.workshop_read_owned_v1(''client'',cl.id,p_office)');
 export_data:=replace(export_data,'t.id=e.tipo_equipamento_id',
  't.id=e.tipo_equipamento_id and rm_private.workshop_read_owned_v1(''equipment_type'',t.id,p_office)');
 execute export_data;
end
$build$;
revoke all on function rm_private.workshop_twin_snapshot_v1(uuid),rm_private.workshop_planning_export_v1(uuid,uuid[],text[])
 from public,anon,authenticated,service_role;

create function rm_private.workshop_outputs_read_v1(p_resource text,p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare keys text[];
begin
 if p_resource='workshop_twin' and p_args='{}'::jsonb then
  return rm_private.workshop_twin_snapshot_v1(p_office)||jsonb_build_object('layout',
   case when exists(select 1 from rm_private.workshop_references where id=p_office and code='BMA') then 'bma' else 'management' end);
 end if;
 if p_resource='planning_export' and jsonb_typeof(p_args)='object' then
  select array_agg(k order by k) into keys from jsonb_object_keys(p_args) k;
  if keys=array['cell_ids','fields'] and jsonb_typeof(p_args->'cell_ids')='array' and jsonb_typeof(p_args->'fields')='array' then
   return rm_private.workshop_planning_export_v1(p_office,
    array(select cell_id::uuid from jsonb_array_elements_text(p_args->'cell_ids') as ids(cell_id)),
    array(select field from jsonb_array_elements_text(p_args->'fields') as names(field)));
  end if;
 end if;
 raise exception 'Consulta de oficina inválida.' using errcode='22023';
exception when invalid_text_representation then
 raise exception 'Consulta de oficina inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_outputs_read_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export')
);
do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 tail text:='''form_record_project'',''form_record_list'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,tail),1) is distinct from 2 or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,tail,'''form_record_project'',''form_record_list'',''workshop_twin'',''planning_export'')');
 execute replace(reader,dispatch,'  when ''workshop_twin'' then rm_private.workshop_outputs_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''planning_export'' then rm_private.workshop_outputs_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;
