begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

alter table rm_private.root_creation_permits drop constraint root_creation_permits_operation_check;
alter table rm_private.root_creation_permits add constraint root_creation_permits_operation_check
 check(operation in('save_project','save_project_with_equipment','save_project_equipment','delete_project','save_catalog','delete_catalog'));

create or replace function rm_private.web_root_edit_kind_v1(p_operation text,p_payload jsonb)
returns text language sql immutable set search_path='' as $$
 select case
  when p_operation in('save_project','save_project_equipment','delete_project') then 'project'
  when p_payload->'expected_updated_at' is distinct from 'null'::jsonb then case
   when p_operation='save_project_with_equipment' then 'project'
   when p_operation='save_catalog' and p_payload->>'kind'='cells' then 'cell'
  end
 end;
$$;

create or replace function rm_private.web_root_write_kind_v1(p_operation text,p_payload jsonb)
returns text language sql immutable set search_path='' as $$
 select coalesce(rm_private.web_root_edit_kind_v1(p_operation,p_payload),case
  when p_operation in('save_catalog','delete_catalog') and p_payload->>'kind'='cells' then 'cell'
  when p_operation='save_project_with_equipment' then 'project'
 end);
$$;

do $write$
declare
 definition text:=pg_get_functiondef('rm_private.web_mutate_root_creation_v1(uuid,text,jsonb)'::regprocedure);
 retirement constant text:='retiring boolean:=p_operation=''delete_catalog'';';
 object_id constant text:='root_id:=(p_payload->>''id'')::uuid;';
 ownership constant text:='select workshop_id into office from rm_private.workshop_object_origins where object_kind=''cell'' and object_id=root_id;';
 current_scope constant text:='office:=rm_private.workshop_catalog_scope_v1(kind,root_id);';
begin
 if array_length(string_to_array(definition,retirement),1) is distinct from 2
  or array_length(string_to_array(definition,object_id),1) is distinct from 2
  or array_length(string_to_array(definition,ownership),1) is distinct from 2
  or array_length(string_to_array(definition,current_scope),1) is distinct from 2 then
  raise exception 'Unexpected workshop root edit contract';
 end if;
 definition:=replace(definition,retirement,'retiring boolean:=p_operation in(''delete_catalog'',''delete_project'');');
 definition:=replace(definition,object_id,'root_id:=(p_payload->>case when p_operation=''save_project_equipment'' then ''projeto_id'' else ''id'' end)::uuid;');
 definition:=replace(definition,ownership,'select workshop_id into office from rm_private.workshop_object_origins where object_kind=kind and object_id=root_id;');
 definition:=replace(definition,'Célula fora da oficina confirmada ou com origem pendente.','Registro fora da oficina confirmada ou com origem pendente.');
 execute replace(definition,current_scope,$scope$
  if exists(select 1 from rm_private.workshop_object_origins
   where object_kind=kind and object_id=root_id and workshop_id<>permit.workshop_id) then
   raise exception 'Registro fora da oficina confirmada ou com origem pendente.' using errcode='42501';
  end if;
  office:=rm_private.workshop_catalog_scope_v1(kind,root_id);$scope$);
end
$write$;

create function rm_private.workshop_root_read_v1(p_resource text,p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare project uuid; clients jsonb:='[]'; types jsonb:='[]'; forms jsonb:='[]';
begin
 if p_resource='project_delete_context' and p_args=jsonb_build_object('id',p_args->'id')
  and jsonb_typeof(p_args->'id')='string' then
  project:=(p_args->>'id')::uuid;
  if not rm_private.workshop_project_owned_v1(project,p_office) then return null;end if;
  return public.rm_web_project_delete_snapshot_v1(project);
 end if;
 if p_resource is distinct from 'root_edit_choices' or jsonb_typeof(p_args) is distinct from 'object'
  or not (p_args ? 'scope') or p_args-'scope'<>'{}' or coalesce(p_args->>'scope','') not in('project','planning') then
  raise exception 'Seletores de edição inválidos.' using errcode='22023';
 end if;
 if p_args->>'scope'='project' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.nome,x.id),'[]') into clients from (
   select id,nome from public.rm_clientes where rm_private.workshop_read_visible_v1('client',id,p_office)
   order by nome,id limit 20001) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.nome,x.id),'[]') into types from (
   select id,nome,sigla from public.rm_tipos_equipamento where rm_private.workshop_read_visible_v1('equipment_type',id,p_office)
   order by nome,id limit 20001) x;
 else
  select coalesce(jsonb_agg(to_jsonb(x) order by x.titulo,x.id),'[]') into forms from (
   select id,titulo,ativo from public.rm_forms where rm_private.workshop_read_visible_v1('form_model',id,p_office)
   order by titulo,id limit 20001) x;
 end if;
 if greatest(jsonb_array_length(clients),jsonb_array_length(types),jsonb_array_length(forms))>20000 then
  raise exception 'A consulta excedeu o limite desta tela.' using errcode='PT413';
 end if;
 return jsonb_build_object('clients',clients,'types',types,'forms',forms);
end
$$;
revoke all on function rm_private.workshop_root_read_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

do $read$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 catalog text:=pg_get_functiondef('rm_private.workshop_read_data_v1(text,jsonb,uuid)'::regprocedure);
 tail constant text:='''operational_stage_rules'')';
 fallback constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 kinds constant text:='kind not in(''clients'',''types'',''forms'')';
 union_types constant text:='   union all select t.id,null,t.created_at';
 entry_type constant text:='  else select jsonb_build_object(''id'',t.id';
 allowed_resources text:=substring(issuer from 'p_resource not in[(][^)]*[)]');
 check_definition text;
begin
 select pg_get_constraintdef(oid) into strict check_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 if right(allowed_resources,length(tail)) is distinct from tail
  or array_length(string_to_array(issuer,allowed_resources),1) is distinct from 2
  or array_length(string_to_array(reader,fallback),1) is distinct from 2
  or array_length(string_to_array(catalog,kinds),1) is distinct from 2
  or array_length(string_to_array(catalog,union_types),1) is distinct from 2
  or array_length(string_to_array(catalog,entry_type),1) is distinct from 2 then
  raise exception 'Unexpected workshop root read contract';
 end if;
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(check_definition from 8 for char_length(check_definition)-8)||') or resource in(''root_edit_choices'',''project_delete_context''))';
 execute replace(issuer,allowed_resources,left(allowed_resources,-1)||',''root_edit_choices'',''project_delete_context'')');
 execute replace(reader,fallback,$dispatch$  when 'root_edit_choices' then rm_private.workshop_root_read_v1(p_resource,p_args,permit.workshop_id)
  when 'project_delete_context' then rm_private.workshop_root_read_v1(p_resource,p_args,permit.workshop_id)
$dispatch$||fallback);
 catalog:=replace(catalog,kinds,'kind not in(''clients'',''types'',''forms'',''cells'')');
 catalog:=replace(catalog,union_types,$list$   union all select c.id,c.nome,null,jsonb_build_object('id',c.id,'codigo',c.codigo,'nome',c.nome,
    'indice',c.indice,'ordem',c.ordem,'updated_at',c.updated_at)
    from public.rm_celulas c where kind='cells' and rm_private.workshop_cell_owned_v1(c.id,p_office)
    and(term='' or strpos(lower(coalesce(c.nome,'')),term)>0 or strpos(lower(coalesce(c.codigo,'')),term)>0)
$list$||union_types);
 execute replace(catalog,entry_type,$entry$  elsif kind='cells' then
   select jsonb_build_object('id',c.id,'codigo',c.codigo,'nome',c.nome,'indice',c.indice,'ordem',c.ordem,'updated_at',c.updated_at)
    into result from public.rm_celulas c where c.id=ident and rm_private.workshop_cell_owned_v1(c.id,p_office);
$entry$||entry_type);
end
$read$;

-- Portal edits already require an identified root. This activation leaves the
-- legacy mobile creation and recovery gateways available during the pilot.
create or replace function rm_private.activate_root_workshop_edits_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 lock table public.rm_projetos,public.rm_celulas in share mode;
 lock table rm_private.workshop_project_ownership,rm_private.workshop_cell_ownership in share mode;
 if not exists(select 1 from rm_private.root_creation_settings where singleton and activated_at is not null)
  or not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or exists(select 1 from public.rm_projetos p where not exists(
   select 1 from rm_private.workshop_project_ownership o where o.id=p.id))
  or exists(select 1 from public.rm_celulas c where not exists(
   select 1 from rm_private.workshop_cell_ownership o where o.cell_id=c.id)) then
  raise exception 'Confirme o SSO e a origem dos projetos e das células antes de ativar as edições.' using errcode='PT409';
 end if;
 update rm_private.root_creation_settings set edits_enforced=true where singleton and not edits_enforced;
 revoke execute on function public.rm_web_project_delete_snapshot_v1(uuid) from authenticated;
 notify pgrst,'reload schema';
end
$$;

commit;
