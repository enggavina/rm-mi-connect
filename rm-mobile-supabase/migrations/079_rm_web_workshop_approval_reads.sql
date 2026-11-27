begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_stage_owned_v1(p_id uuid,p_office uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from public.rm_aprovacoes_etapas s where s.id=p_id
  and rm_private.workshop_project_owned_v1(s.projeto_id,p_office)
  and rm_private.workshop_cell_owned_v1(s.celula_origem_id,p_office)
  and (s.celula_destino_id is null or rm_private.workshop_cell_owned_v1(s.celula_destino_id,p_office))
  and (s.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a
   where a.id=s.celula_projeto_id and a.projeto_id=s.projeto_id and a.celula_id=s.celula_origem_id)))
$$;
revoke all on function rm_private.workshop_stage_owned_v1(uuid,uuid) from public,anon,authenticated,service_role;

do $build$
declare
 list_def text:=pg_get_functiondef('public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer)'::regprocedure);
 detail_def text:=pg_get_functiondef('public.rm_web_stage_approval_snapshot_v1(uuid)'::regprocedure);
begin
 if strpos(list_def,'where v.ativo and (p_project_id is null')=0 or strpos(detail_def,'where v.id=p_id;')=0 then
  raise exception 'Unexpected stage approval projection';
 end if;
 list_def:=replace(list_def,'FUNCTION public.rm_web_stage_approvals_v1(p_project_id ',
  'FUNCTION rm_private.workshop_stage_approval_list_v1(p_office uuid, p_project_id ');
 execute replace(list_def,'where v.ativo and (p_project_id is null',
  'where v.ativo and rm_private.workshop_stage_owned_v1(v.id,p_office) and (p_project_id is null');
 detail_def:=replace(detail_def,'FUNCTION public.rm_web_stage_approval_snapshot_v1(p_id ',
  'FUNCTION rm_private.workshop_stage_approval_detail_v1(p_office uuid, p_id ');
 execute replace(detail_def,'where v.id=p_id;','where v.id=p_id and rm_private.workshop_stage_owned_v1(v.id,p_office);');
end
$build$;
revoke all on function rm_private.workshop_stage_approval_list_v1(uuid,uuid,uuid,text,boolean,text,integer,integer),
 rm_private.workshop_stage_approval_detail_v1(uuid,uuid) from public,anon,authenticated,service_role;

create function rm_private.workshop_stage_read_v1(p_resource text,p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare keys text[]; result jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' then
  raise exception 'Consulta de aprovações inválida.' using errcode='22023';
 end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_args) k;
 if p_resource='approval_entry' and keys=array['id'] and jsonb_typeof(p_args->'id')='string' then
  return rm_private.workshop_stage_approval_detail_v1(p_office,(p_args->>'id')::uuid);
 elsif p_resource='approval_list' and keys=array['cell','mine','page','project','q','state']
  and jsonb_typeof(p_args->'q')='string' and jsonb_typeof(p_args->'state')='string' and jsonb_typeof(p_args->'mine')='boolean'
  and jsonb_typeof(p_args->'page')='number' and p_args->>'page' ~ '^[1-9][0-9]{0,4}$'
  and jsonb_typeof(p_args->'cell') in ('null','string') and jsonb_typeof(p_args->'project') in ('null','string') then
  return rm_private.workshop_stage_approval_list_v1(p_office,(p_args->>'project')::uuid,(p_args->>'cell')::uuid,
   p_args->>'state',(p_args->>'mine')::boolean,p_args->>'q',(p_args->>'page')::int,25);
 elsif p_resource='approval_choices' and p_args='{}'::jsonb then
  return (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome) order by c.nome,c.id),'[]')
   from public.rm_celulas c where rm_private.workshop_cell_owned_v1(c.id,p_office));
 elsif p_resource='approval_allocation' and keys=array['id','project_id']
  and jsonb_typeof(p_args->'id')='string' and jsonb_typeof(p_args->'project_id')='string' then
  select jsonb_build_object('id',a.id,'projeto_id',a.projeto_id,'celula_id',a.celula_id) into result
  from public.rm_celulas_projeto a where a.id=(p_args->>'id')::uuid and a.projeto_id=(p_args->>'project_id')::uuid
   and rm_private.workshop_project_owned_v1(a.projeto_id,p_office) and rm_private.workshop_cell_owned_v1(a.celula_id,p_office);
  return result;
 end if;
 raise exception 'Consulta de aprovações inválida.' using errcode='22023';
exception when invalid_text_representation then
 raise exception 'Consulta de aprovações inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_stage_read_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation')
);
do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 tail text:='''media_reference'',''overview'')';
 dispatch text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
 if array_length(string_to_array(issuer,tail),1) is distinct from 2 or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop read permit contract';
 end if;
 execute replace(issuer,tail,'''media_reference'',''overview'',''approval_list'',''approval_entry'',''approval_choices'',''approval_allocation'')');
 execute replace(reader,dispatch,'  when ''approval_list'' then rm_private.workshop_stage_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''approval_entry'' then rm_private.workshop_stage_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''approval_choices'' then rm_private.workshop_stage_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''approval_allocation'' then rm_private.workshop_stage_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||dispatch);
end
$extend$;
notify pgrst,'reload schema';
commit;
