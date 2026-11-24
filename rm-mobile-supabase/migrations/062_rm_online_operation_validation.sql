-- Read-only validation for the approved corporate identity and its existing operator grants.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';

-- The projection is shared by the password-based and corporate readers. The
-- corporate reader always supplies the operator's explicit cells, even if its
-- web profile is an administrator. The password reader keeps its 061 policy.
create function rm_private.online_operation_projection_v1(
  p_operator_id uuid, p_office_id uuid, p_cell_id uuid, p_project_id uuid,
  p_page integer, p_explicit_cells uuid[]
) returns jsonb language plpgsql stable set search_path = '' as $$
declare
  cell jsonb;
  result jsonb;
begin
  if p_operator_id is null or p_office_id is null or p_page is null or p_page not between 1 and 10000
    or (p_project_id is not null and p_cell_id is null) then
    return null;
  end if;

  if p_cell_id is null then
    select jsonb_build_object('kind','cells','items',coalesce(
      jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome) order by coalesce(c.indice,c.ordem,0),c.nome,c.id),
      '[]'::jsonb
    )) into result
    from public.rm_celulas c join rm_private.workshop_cell_ownership o on o.cell_id = c.id and o.workshop_id = p_office_id
    where case when p_explicit_cells is null then rm_private.operator_can_access_cell(p_operator_id,c.id)
      else c.id = any(p_explicit_cells) end;
    return result;
  end if;

  select jsonb_build_object('id',c.id,'nome',c.nome) into cell
  from public.rm_celulas c
  where c.id = p_cell_id and rm_private.workshop_cell_owned_v1(c.id,p_office_id)
    and (case when p_explicit_cells is null then rm_private.operator_can_access_cell(p_operator_id,c.id)
      else c.id = any(p_explicit_cells) end);
  if cell is null then return null; end if;

  with visible as materialized (
    select p.id, a.status = 'retornado' as returned, coalesce(a.posicao,a.indice,0) as position,
      a.forms_ids,
      jsonb_build_object('id',p.id,'numero',coalesce(nullif(p.numero,''),nullif(a.numero_projeto,'')),
        'nome',p.nome,'cliente',c.nome,'descricao',coalesce(nullif(p.descricao_equipamento,''),e.descricao),
        'status',a.status) as project
    from public.rm_celulas_projeto a
    join public.rm_projetos p on p.id = a.projeto_id
    join rm_private.workshop_project_ownership o on o.id = p.id and o.workshop_id = p_office_id
    left join public.rm_equipamentos e on e.projeto_id = p.id and e.id = p.equipamento_id
    left join public.rm_clientes c on c.id = p.cliente_id and rm_private.workshop_read_owned_v1('client',c.id,p_office_id)
    where a.celula_id = p_cell_id and a.visibilidade and not a.retirada
      and p.data_real_de_entrega is null
      and p.status_pcp is distinct from 'cancelado' and p.status_pcp is distinct from 'finalizando_para_faturar'
      and (p_project_id is null or p.id = p_project_id)
  ), page_rows as (
    select * from visible order by returned desc,position,id limit 25 offset (p_page-1)*25
  )
  select case when p_project_id is null then
    jsonb_build_object('kind','projects','cell',cell,'items',coalesce(
      (select jsonb_agg(project order by returned desc,position,id) from page_rows),'[]'::jsonb),
      'page',p_page,'page_size',25,'total',(select count(*) from visible))
  else (
    select jsonb_build_object('kind','project','cell',cell,'project',v.project,'forms',coalesce(
      (select jsonb_agg(jsonb_build_object('id',f.id,'titulo',f.titulo) order by array_position(v.forms_ids,f.id),f.id)
        from public.rm_forms f where f.id = any(v.forms_ids) and f.ativo
          and rm_private.workshop_read_visible_v1('form_model',f.id,p_office_id)), '[]'::jsonb))
    from visible v
  ) end into result;
  return result;
end;
$$;

create function rm_private.online_operation_validation_actor_v1(
  p_subject uuid, p_binding_id uuid, p_rm_user_id uuid, p_office_id uuid
) returns uuid language sql stable set search_path = '' as $$
  select operator_user.id
  from public.rm_users operator_user
  where p_subject = 'a9e45880-1924-4b2d-a2b1-dc12fd029bff'::uuid
    and p_binding_id = 'ae29e9a9-9c50-4d25-81eb-6a01202bc20a'::uuid
    and p_rm_user_id = '2e70c7e9-3ed2-47fa-9860-9501aeac96cc'::uuid
    and operator_user.id = '23c4787b-eb5b-44ed-abbc-547e358e2f6f'::uuid
    and operator_user.matricula = '05' and operator_user.status = 'ativo'
    and exists(select 1 from public.rm_users web_user where web_user.id = p_rm_user_id
      and web_user.matricula = 'WEB-SOFTDEV05' and web_user.status = 'ativo' and web_user.perfil = 'administrador')
    and exists(select 1 from rm_private.workshop_references office where office.id = p_office_id and office.code = 'BMA');
$$;

create function rm_private.online_operation_validation_v1(
  p_subject uuid, p_binding_id uuid, p_rm_user_id uuid, p_office_id uuid, p_args jsonb
) returns jsonb language plpgsql stable set search_path = '' as $$
declare
  operator_id uuid;
  cells uuid[];
  cell_id uuid;
  project_id uuid;
  page_no integer;
begin
  operator_id := rm_private.online_operation_validation_actor_v1(p_subject,p_binding_id,p_rm_user_id,p_office_id);
  if operator_id is null then
    raise exception using errcode = '42501', message = 'Validação operacional indisponível para esta identidade.';
  end if;
  if jsonb_typeof(p_args) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(p_args) k) is distinct from array['cell_id','page','project_id']
    or jsonb_typeof(p_args->'cell_id') not in ('null','string')
    or jsonb_typeof(p_args->'project_id') not in ('null','string')
    or jsonb_typeof(p_args->'page') is distinct from 'number' or p_args->>'page' !~ '^[0-9]{1,5}$' then
    raise exception using errcode = '22023', message = 'Seleção operacional inválida.';
  end if;
  cell_id := (p_args->>'cell_id')::uuid;
  project_id := (p_args->>'project_id')::uuid;
  page_no := (p_args->>'page')::integer;
  if page_no not between 1 and 10000 or (project_id is not null and cell_id is null) then
    raise exception using errcode = '22023', message = 'Seleção operacional inválida.';
  end if;
  select coalesce(array_agg(distinct grant_row.celula_id),'{}'::uuid[]) into cells
  from public.rm_tablet_celula_users grant_row where grant_row.identidade_id = operator_id;

  return rm_private.online_operation_projection_v1(operator_id,p_office_id,cell_id,project_id,page_no,cells);
end;
$$;

revoke all on function rm_private.online_operation_projection_v1(uuid,uuid,uuid,uuid,integer,uuid[]),
  rm_private.online_operation_validation_actor_v1(uuid,uuid,uuid,uuid),
  rm_private.online_operation_validation_v1(uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated,service_role;

create or replace function public.rm_online_operation_read_v1(
  p_auth_user_id uuid, p_session_id uuid, p_operator_token text,
  p_workshop_context jsonb, p_cell_id uuid, p_project_id uuid, p_page integer
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  operator_id uuid;
  office_id uuid;
begin
  select i.operator_subject into operator_id
  from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
  if operator_id is null or p_page is null or p_page not between 1 and 10000
    or (p_project_id is not null and p_cell_id is null) then
    return null;
  end if;
  office_id := rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,operator_id);
  return rm_private.online_operation_projection_v1(operator_id,office_id,p_cell_id,p_project_id,p_page,null);
end;
$$;

-- Keep the issuer/consumer OIDs and grants and patch only the 060 anchors.
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
  resource in ('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
    'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation')
);

do $extend$
declare
  issuer text := pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
  consumer text := pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
  issuer_guard text := $s$p_resource not in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices','project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells')$s$;
  issuer_extension text := $s$p_resource not in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices','project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation')$s$;
  issuer_insert text := ' insert into rm_private.workshop_read_permits(read_id,session_hash,resource,args_hash,workshop_id,subject,expires_at)';
  consumer_dispatch text := '  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
begin
  if array_length(string_to_array(issuer,issuer_guard),1) is distinct from 2
    or array_length(string_to_array(issuer,issuer_insert),1) is distinct from 2
    or array_length(string_to_array(consumer,consumer_dispatch),1) is distinct from 2 then
    raise exception 'Unexpected workshop permit source from 060.';
  end if;
  issuer := replace(issuer,issuer_guard,issuer_extension);
  execute replace(issuer,issuer_insert,$gate$ if p_resource='operation_validation'
  and rm_private.online_operation_validation_actor_v1(binding.subject,binding.id,binding.rm_user_id,office) is null then
  raise exception using errcode='42501',message='Validação operacional indisponível para esta identidade.';end if;
$gate$ || issuer_insert);
  execute replace(consumer,consumer_dispatch,$dispatch$  when 'operation_validation' then rm_private.online_operation_validation_v1(binding.subject,binding.id,actor.id,permit.workshop_id,p_args)
$dispatch$ || consumer_dispatch);
end
$extend$;

notify pgrst,'reload schema';
commit;
