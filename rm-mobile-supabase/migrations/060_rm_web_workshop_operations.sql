-- Prepared operational readers for the corporate workshop rollout.
-- Existing policies, mobile and other portal consumers retain their contracts.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';

create function rm_private.workshop_project_owned_v1(p_id uuid, p_office uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from rm_private.workshop_project_ownership
    where id = p_id and workshop_id = p_office
  );
$$;

create function rm_private.workshop_cell_owned_v1(p_id uuid, p_office uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (
    select 1 from rm_private.workshop_cell_ownership
    where cell_id = p_id and workshop_id = p_office
  );
$$;
-- Migration 054 makes an active ownership row incompatible with retirement.
revoke all on function rm_private.workshop_project_owned_v1(uuid,uuid),
  rm_private.workshop_cell_owned_v1(uuid,uuid) from public,anon,authenticated,service_role;


-- Project and planning list projections. Call only after the one-use read permit
-- checks its session, resource and exact arguments. A pending owner grants no read.
create function rm_private.workshop_project_read_data_v1(p_resource text,p_args jsonb,p_office uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare
  required text[];
  term text;
  status_filter text;
  cell_filter uuid;
  client_filter uuid;
  project_id uuid;
  page_no integer;
  start_at integer;
  show_cells boolean;
  show_project boolean;
  show_documents boolean;
  result jsonb;
begin
  required := case p_resource
    when 'project_list' then array['q','status','client','cell','page','planning']
    when 'project_entry' then array['id','documents','cells']
    when 'planning_list' then array['q','status','cell','page','project_details']
  end;
  if required is null or p_office is null or jsonb_typeof(p_args) is distinct from 'object'
    or not (p_args ?& required)
    or (select count(*) from jsonb_object_keys(p_args)) <> cardinality(required) then
    raise exception using errcode='22023',message='Consulta de projetos inválida.';
  end if;

  if p_resource='project_entry' then
    if jsonb_typeof(p_args->'id') is distinct from 'string'
      or jsonb_typeof(p_args->'documents') is distinct from 'boolean'
      or jsonb_typeof(p_args->'cells') is distinct from 'boolean' then
      raise exception using errcode='22023',message='Consulta de projeto inválida.';
    end if;
    project_id := (p_args->>'id')::uuid;
    show_documents := (p_args->>'documents')::boolean;
    show_cells := (p_args->>'cells')::boolean;

    select jsonb_build_object(
      'project',jsonb_build_object(
        'id',p.id,'numero',p.numero,'nome',p.nome,'cliente_id',p.cliente_id,
        'cliente_nome_exportacao',p.cliente_nome_exportacao,'tipo_equipamento_id',p.tipo_equipamento_id,
        'equipamento_id',p.equipamento_id,'descricao_equipamento',p.descricao_equipamento,
        'contato',p.contato,'proprietario',p.proprietario,'escopo_abreviado',p.escopo_abreviado,
        'eventualidades',p.eventualidades,'gestor_responsavel_id',p.gestor_responsavel_id,
        'status',p.status,'status_pcp',p.status_pcp,'nota_fiscal',p.nota_fiscal,
        'chegada_do_equipamento',p.chegada_do_equipamento,'data_prevista_inicio',p.data_prevista_inicio,
        'data_prevista_final',p.data_prevista_final,'data_contratual',p.data_contratual,
        'data_renegociada',p.data_renegociada,'data_inicio_peritagem',p.data_inicio_peritagem,
        'data_fim_peritagem',p.data_fim_peritagem,'data_inicio_reparo',p.data_inicio_reparo,
        'data_fim_reparo',p.data_fim_reparo,'data_real_de_entrega',p.data_real_de_entrega,
        'replanejamento_motivo',p.replanejamento_motivo,'created_at',p.created_at,'updated_at',p.updated_at
      ) || case when show_documents then jsonb_build_object(
        'arquivo_nota_fiscal_url',p.arquivo_nota_fiscal_url,'documento_proposta_url',p.documento_proposta_url)
        else '{}'::jsonb end,
      'client',case when c.id is not null then jsonb_build_object('id',c.id,'codigo',c.codigo,'nome',c.nome,'descricao',c.descricao) end,
      'cells',coalesce((select jsonb_agg(to_jsonb(x) order by x.indice,x.id) from (
        select ce.id,ce.codigo,ce.nome,ce.indice,ce.ordem
        from public.rm_celulas ce
        where show_cells and rm_private.workshop_cell_owned_v1(ce.id,p_office)
        order by ce.indice,ce.id limit 20000
      ) x),'[]'::jsonb)
    ) into result
    from public.rm_projetos p
    left join public.rm_clientes c on c.id=p.cliente_id and rm_private.workshop_read_visible_v1('client',c.id,p_office)
    where p.id=project_id and rm_private.workshop_project_owned_v1(p.id,p_office);
    return result;
  end if;

  if jsonb_typeof(p_args->'q') is distinct from 'string' or length(p_args->>'q')>100
    or jsonb_typeof(p_args->'page') is distinct from 'number' or p_args->>'page' !~ '^[1-9][0-9]{0,4}$'
    or jsonb_typeof(p_args->'cell') not in ('null','string')
    or jsonb_typeof(p_args->'status') not in ('null','string') or length(p_args->>'status')>100 then
    raise exception using errcode='22023',message='Filtros de projetos inválidos.';
  end if;
  page_no := (p_args->>'page')::integer;
  if page_no>10000 then raise exception using errcode='22023',message='Página de projetos inválida.';end if;
  term := lower(p_args->>'q');
  status_filter := nullif(p_args->>'status','');
  cell_filter := (p_args->>'cell')::uuid;

  if p_resource='project_list' then
    if jsonb_typeof(p_args->'planning') is distinct from 'boolean'
      or jsonb_typeof(p_args->'client') not in ('null','string') then
      raise exception using errcode='22023',message='Seletores de projetos inválidos.';
    end if;
    show_cells := (p_args->>'planning')::boolean;
    if cell_filter is not null and not show_cells then
      raise exception using errcode='42501',message='Consulta por célula indisponível.';
    end if;
    client_filter := (p_args->>'client')::uuid;
    start_at := (page_no-1)*25;
    with visible_projects as materialized (
      select p.id,p.numero,p.nome,p.cliente_id,p.cliente_nome_exportacao,p.equipamento_id,
        p.descricao_equipamento,p.status_pcp,p.data_prevista_final,p.updated_at
      from public.rm_projetos p
      where rm_private.workshop_project_owned_v1(p.id,p_office)
        and (status_filter is null or p.status_pcp::text=status_filter)
        and (client_filter is null or (p.cliente_id=client_filter
          and rm_private.workshop_read_visible_v1('client',client_filter,p_office)))
        and (cell_filter is null or (rm_private.workshop_cell_owned_v1(cell_filter,p_office)
          and exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=p.id and a.celula_id=cell_filter and not a.retirada)))
        and (term='' or strpos(lower(coalesce(p.numero,'')),term)>0 or strpos(lower(coalesce(p.nome,'')),term)>0
          or strpos(lower(coalesce(p.cliente_nome_exportacao,'')),term)>0 or strpos(lower(coalesce(p.descricao_equipamento,'')),term)>0)
    ), paginated as (
      select * from visible_projects order by updated_at desc,id offset start_at limit 25
    )
    select jsonb_build_object(
      'rows',coalesce((select jsonb_agg(jsonb_build_object(
        'id',p.id,'numero',p.numero,'nome',p.nome,'cliente_nome',coalesce(nullif(c.nome,''),nullif(p.cliente_nome_exportacao,'')),
        'descricao_equipamento_exibicao',coalesce(nullif(p.descricao_equipamento,''),nullif(e.descricao,'')),
        'status_pcp',p.status_pcp,'data_prevista_final',p.data_prevista_final,'updated_at',p.updated_at
      ) order by p.updated_at desc,p.id) from paginated p
      left join public.rm_clientes c on c.id=p.cliente_id and rm_private.workshop_read_visible_v1('client',c.id,p_office)
      left join public.rm_equipamentos e on e.id=p.equipamento_id and e.projeto_id=p.id),'[]'::jsonb),
      'total',(select count(*) from visible_projects),'page',page_no,'pageSize',25,
      'clients',coalesce((select jsonb_agg(to_jsonb(x) order by x.nome,x.id) from (
        select c.id,c.nome from public.rm_clientes c
        where rm_private.workshop_read_visible_v1('client',c.id,p_office)
        order by c.nome,c.id limit 20000
      ) x),'[]'::jsonb),
      'cells',coalesce((select jsonb_agg(to_jsonb(x) order by x.nome,x.id) from (
        select c.id,c.codigo,c.nome,c.indice,c.ordem from public.rm_celulas c
        where show_cells and rm_private.workshop_cell_owned_v1(c.id,p_office)
        order by c.nome,c.id limit 20000
      ) x),'[]'::jsonb),
      'statuses',coalesce((select jsonb_agg(jsonb_build_object('id',o.option_key,'option_key',o.option_key,
        'bubble_display',o.bubble_display,'sort_order',o.sort_order) order by o.sort_order,o.option_key)
        from public.rm_option_sets o where o.option_set_key='status_pcp'),'[]'::jsonb)
    ) into result;
    return result;
  end if;

  if jsonb_typeof(p_args->'project_details') is distinct from 'boolean' then
    raise exception using errcode='22023',message='Consulta de planejamento inválida.';
  end if;
  show_project := (p_args->>'project_details')::boolean;
  start_at := (page_no-1)*50;
  with visible_allocations as materialized (
    select a.id,a.projeto_id,a.celula_id,a.numero_projeto,a.cliente_nome_export,a.status,
      a.bloqueada,a.visibilidade,a.prioridade,a.posicao,a.data_inicio,a.data_limite,
      case when show_project then jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,
        'status_pcp',p.status_pcp,'data_real_de_entrega',p.data_real_de_entrega,'cliente_nome_exportacao',p.cliente_nome_exportacao) end as project
    from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id
    where not a.retirada and rm_private.workshop_project_owned_v1(a.projeto_id,p_office)
      and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)
      and (cell_filter is null or a.celula_id=cell_filter)
      and (status_filter is null or a.status::text=status_filter)
      and (term='' or case when show_project then strpos(lower(coalesce(p.numero,'')),term)>0
        or strpos(lower(coalesce(p.nome,'')),term)>0 or strpos(lower(coalesce(p.cliente_nome_exportacao,'')),term)>0
        else strpos(lower(coalesce(a.numero_projeto,'')),term)>0 or strpos(lower(coalesce(a.cliente_nome_export,'')),term)>0 end)
  ), paginated as (
    select * from visible_allocations order by posicao,id offset start_at limit 50
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(to_jsonb(a) order by a.posicao,a.id) from paginated a),'[]'::jsonb),
    'total',(select count(*) from visible_allocations),'page',page_no,'pageSize',50,
    'projects',coalesce((select jsonb_agg(to_jsonb(x) order by x.numero,x.id) from (
      select p.id,p.numero,p.nome,p.status_pcp,p.data_real_de_entrega from public.rm_projetos p
      where show_project and rm_private.workshop_project_owned_v1(p.id,p_office)
      order by p.numero,p.id limit 20000
    ) x),'[]'::jsonb),
    'cells',coalesce((select jsonb_agg(to_jsonb(x) order by x.nome,x.id) from (
      select c.id,c.codigo,c.nome,c.indice,c.ordem from public.rm_celulas c
      where rm_private.workshop_cell_owned_v1(c.id,p_office) order by c.nome,c.id limit 20000
    ) x),'[]'::jsonb),
    'statuses',coalesce((select jsonb_agg(jsonb_build_object('id',o.option_key,'option_key',o.option_key,
      'bubble_display',o.bubble_display,'sort_order',o.sort_order) order by o.sort_order,o.option_key)
      from public.rm_option_sets o where o.option_set_key='status_cel_proj'),'[]'::jsonb)
  ) into result;
  return result;
end$$;
revoke all on function rm_private.workshop_project_read_data_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

-- These readers are reachable only after consuming a session-bound permit.
create function rm_private.workshop_gantt_snapshot_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare
 filters jsonb; pid uuid; cid uuid; closed boolean; project_details boolean;
 n bigint; ids uuid[]; pids uuid[]; result jsonb; settings jsonb; settings_size bigint;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object'
  or not p_args?&array['project_id','cell_id','include_closed','project_details','can_manage']
  or exists(select 1 from jsonb_object_keys(p_args) k where k not in('project_id','cell_id','include_closed','project_details','can_manage'))
  or jsonb_typeof(p_args->'project_id') not in('null','string') or jsonb_typeof(p_args->'cell_id') not in('null','string')
  or jsonb_typeof(p_args->'include_closed') is distinct from 'boolean'
  or jsonb_typeof(p_args->'project_details') is distinct from 'boolean'
  or p_args->'can_manage' is distinct from 'false'::jsonb then
  raise exception using errcode='22023',message='Seleção do cronograma inválida.';
 end if;
 filters:=p_args-'project_details'-'can_manage';
 pid:=(p_args->>'project_id')::uuid;
 cid:=(p_args->>'cell_id')::uuid;
 closed:=(p_args->>'include_closed')::boolean;
 project_details:=(p_args->>'project_details')::boolean;
 if pid is not null and(cid is not null or not closed or not project_details) then
  raise exception using errcode='22023',message='Seleção do cronograma inválida.';
 end if;
 if (pid is not null and not rm_private.workshop_project_owned_v1(pid,p_office))
  or (cid is not null and not rm_private.workshop_cell_owned_v1(cid,p_office)) then
  return null;
 end if;
 with eligible as materialized(
  select a.id from public.rm_celulas_projeto a
  join public.rm_projetos p on p.id=a.projeto_id
  join rm_private.workshop_project_ownership po on po.id=p.id and po.workshop_id=p_office
  join rm_private.workshop_cell_ownership co on co.cell_id=a.celula_id and co.workshop_id=p_office
  where not a.retirada and(pid is null or a.projeto_id=pid) and(cid is null or a.celula_id=cid)
   and(closed or(p.data_real_de_entrega is null and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
    and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
    and a.status is distinct from 'finalizado'::public.rm_status_cel_proj_enum and a.status is distinct from 'n_a'::public.rm_status_cel_proj_enum))
 )
 select count(*),array(select id from eligible order by id limit 2000) into n,ids from eligible;
 if n>2000 then
  return jsonb_build_object('as_of',statement_timestamp(),'filters',filters,'total',n,'complete',false,
   'items','[]'::jsonb,'projects','[]'::jsonb,'cells','[]'::jsonb,'links','[]'::jsonb,'baseline',null,'settings','[]'::jsonb);
 end if;
 select case when pid is not null then array[pid] else array_agg(distinct a.projeto_id order by a.projeto_id) end
 into pids from public.rm_celulas_projeto a where a.id=any(ids);
 select jsonb_build_object('as_of',statement_timestamp(),'filters',filters,'total',n,'complete',true,
  'items',coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'projeto_id',a.projeto_id,'celula_id',a.celula_id,'numero_projeto',coalesce(a.numero_projeto,p.numero),
   'cliente_nome_export',a.cliente_nome_export,'celula_nome',c.nome,'status',a.status,'bloqueada',a.bloqueada,
   'motivo_bloqueio',a.motivo_bloqueio,'visibilidade',a.visibilidade,'prioridade',a.prioridade,'indice',a.indice,'posicao',a.posicao,
   'responsavel_nome',u.nome,'data_inicio',a.data_inicio,'data_limite',a.data_limite,'updated_at',a.updated_at,
   'can_edit',false)
   order by p.numero nulls last,a.projeto_id,a.indice nulls last,a.posicao nulls last,a.id)
   from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id
   left join public.rm_users u on u.id=a.responsavel_id where a.id=any(ids)),'[]'),
  'projects',coalesce((select jsonb_agg(jsonb_build_object(
   'id',p.id,'numero',p.numero,'nome',case when project_details then p.nome end,'updated_at',p.updated_at,
   'plan_version',rm_private.web_gantt_project_version_v1(p.id),
   'closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false),
   'planned_start',case when project_details then p.data_prevista_inicio end,
   'planned_end',case when project_details then p.data_prevista_final end,
   'contract_date',case when project_details then p.data_contratual end,
   'renegotiated_date',case when project_details then p.data_renegociada end) order by p.id)
   from public.rm_projetos p where p.id=any(pids)),'[]'),
  'cells',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome) order by c.nome,c.id) from public.rm_celulas c
   where c.id=cid or exists(select 1 from public.rm_celulas_projeto a where a.id=any(ids) and a.celula_id=c.id)),'[]'),
  'links',coalesce((select jsonb_agg(jsonb_build_object('projeto_id',g.projeto_id,
   'predecessor_id',l.value->'predecessor_id','successor_id',l.value->'successor_id','lag_days',l.value->'lag_days')
   order by g.projeto_id,l.value->>'predecessor_id',l.value->>'successor_id')
   from rm_private.gantt_project_plans g cross join lateral jsonb_array_elements(g.links) l
   join public.rm_celulas_projeto predecessor on predecessor.id=(l.value->>'predecessor_id')::uuid and predecessor.projeto_id=g.projeto_id
   join public.rm_celulas_projeto successor on successor.id=(l.value->>'successor_id')::uuid and successor.projeto_id=g.projeto_id
   where g.projeto_id=any(pids) and predecessor.id=any(ids) and successor.id=any(ids)),'[]'),
  'baseline',(select jsonb_build_object('id',b.id,'label',b.label,'created_at',b.created_at,'items',coalesce((
   select jsonb_agg(jsonb_build_object('allocation_id',entry.value->'allocation_id',
    'data_inicio',entry.value->'data_inicio','data_limite',entry.value->'data_limite') order by entry.position)
   from jsonb_array_elements(b.items) with ordinality entry(value,position)
   join public.rm_celulas_projeto a on a.id=(entry.value->>'allocation_id')::uuid and a.projeto_id=b.projeto_id
   join rm_private.workshop_cell_ownership co on co.cell_id=a.celula_id and co.workshop_id=p_office),'[]'))
   from rm_private.gantt_baselines b where b.projeto_id=pid order by b.created_at desc,b.id desc limit 1)) into result;
 select coalesce(sum(octet_length(s.calendar::text)+250+
  case when project_details then octet_length(s.milestones::text) else 2 end),0) into settings_size
 from rm_private.gantt_project_settings s where s.projeto_id=any(pids);
 if octet_length(result::text)+settings_size>10485760 or jsonb_array_length(result->'links')>4000 then
  raise exception using errcode='PT413',message='O cronograma excede o limite de leitura. Selecione um projeto ou célula.';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('projeto_id',s.projeto_id,'calendar',s.calendar,
  'milestones',case when project_details then s.milestones else '[]' end,'updated_at',s.updated_at) order by s.projeto_id),'[]') into settings
 from rm_private.gantt_project_settings s where s.projeto_id=any(pids);
 result:=result||jsonb_build_object('settings',settings);
 if octet_length(result::text)>10485760 then
  raise exception using errcode='PT413',message='O cronograma excede o limite de leitura. Selecione um projeto ou célula.';
 end if;
 return result;
end;
$$;

create function rm_private.workshop_gantt_projects_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare q text; requested_page integer;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' or not p_args?&array['q','page']
  or exists(select 1 from jsonb_object_keys(p_args) k where k not in('q','page'))
  or jsonb_typeof(p_args->'q') is distinct from 'string' or length(p_args->>'q')>100
  or jsonb_typeof(p_args->'page') is distinct from 'number' or (p_args->>'page')!~'^[0-9]{1,5}$' then
  raise exception using errcode='22023',message='Seleção do cronograma inválida.';
 end if;
 q:=p_args->>'q';
 requested_page:=(p_args->>'page')::integer;
 if requested_page not between 1 and 10000 then
  raise exception using errcode='22023',message='Seleção do cronograma inválida.';
 end if;
 return(
  with eligible as materialized(
   select p.id,p.numero,p.nome from public.rm_projetos p
   join rm_private.workshop_project_ownership po on po.id=p.id and po.workshop_id=p_office
   where q='' or strpos(lower(p.numero),lower(q))>0 or strpos(lower(p.nome),lower(q))>0
  ), page_rows as(
   select * from eligible order by numero,id limit 25 offset (requested_page-1)*25
  )
  select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.numero,p.id) from page_rows p),'[]'),
   'total',(select count(*) from eligible),'page',requested_page,'page_size',25)
 );
end;
$$;

create function rm_private.workshop_gantt_cells_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare result jsonb;
begin
 if p_office is null or p_args is distinct from '{}'::jsonb then
  raise exception using errcode='22023',message='Seleção do cronograma inválida.';
 end if;
 select coalesce(jsonb_agg(to_jsonb(c) order by c.nome,c.id),'[]') into result
 from(select c.id,c.nome from public.rm_celulas c
  join rm_private.workshop_cell_ownership co on co.cell_id=c.id and co.workshop_id=p_office
  order by c.nome,c.id limit 20000) c;
 if jsonb_array_length(result)>=20000 then
  raise exception using errcode='PT413',message='A consulta de células excedeu o limite desta tela.';
 end if;
 return result;
end;
$$;
revoke all on function rm_private.workshop_gantt_snapshot_v1(jsonb,uuid),
 rm_private.workshop_gantt_projects_v1(jsonb,uuid),rm_private.workshop_gantt_cells_v1(jsonb,uuid)
 from public,anon,authenticated,service_role;

-- Preserve the issuer/consumer OIDs and grants. Extend the exact 059 source.
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
  resource in ('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
    'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells')
);

do $extend$
declare
  issuer text := pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
  consumer text := pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
  issuer_guard text := $s$p_resource not in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices')$s$;
  issuer_extension text := $s$p_resource not in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices','project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells')$s$;
  consumer_dispatch text := 'result:=rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id);';
begin
  if array_length(string_to_array(issuer,issuer_guard),1) is distinct from 2
    or array_length(string_to_array(consumer,consumer_dispatch),1) is distinct from 2 then
    raise exception 'Unexpected 059 workshop permit source.';
  end if;
  execute replace(issuer,issuer_guard,issuer_extension);
  execute replace(consumer,consumer_dispatch,$dispatch$result:=case p_resource
  when 'gantt_snapshot' then rm_private.workshop_gantt_snapshot_v1(p_args,permit.workshop_id)
  when 'gantt_projects' then rm_private.workshop_gantt_projects_v1(p_args,permit.workshop_id)
  when 'gantt_cells' then rm_private.workshop_gantt_cells_v1(p_args,permit.workshop_id)
  when 'project_list' then rm_private.workshop_project_read_data_v1(p_resource,p_args,permit.workshop_id)
  when 'project_entry' then rm_private.workshop_project_read_data_v1(p_resource,p_args,permit.workshop_id)
  when 'planning_list' then rm_private.workshop_project_read_data_v1(p_resource,p_args,permit.workshop_id)
  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)
 end;$dispatch$);
end
$extend$;

notify pgrst,'reload schema';
commit;
