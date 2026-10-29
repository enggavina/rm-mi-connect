-- PCP queues are explicitly saved; installing this migration changes no rows.
-- Ordering and priority remain independent. Existing offline/mobile IDs survive.
begin;

create view rm_private.web_open_cell_allocations_v1 with(security_invoker=true) as
select a.*,p.updated_at as project_updated_at
from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id
where p.data_real_de_entrega is null
  and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
  and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
  and a.status is distinct from 'finalizado'::public.rm_status_cel_proj_enum
  and a.status is distinct from 'n_a'::public.rm_status_cel_proj_enum;
revoke all on rm_private.web_open_cell_allocations_v1 from public,anon,authenticated,service_role;
grant select on rm_private.web_open_cell_allocations_v1 to authenticated;

create function public.rm_web_cell_queue_snapshot_v1(p_cell_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  with queue as materialized (
    select * from rm_private.web_open_cell_allocations_v1 where celula_id=p_cell_id
  ), aggregate as (
    select count(*) total,
      coalesce(jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at,'project_updated_at',a.project_updated_at)
        order by coalesce(a.posicao,a.indice,0),a.id),'[]'::jsonb) revisions,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',a.id,'projeto_id',a.projeto_id,'celula_id',a.celula_id,'numero_projeto',a.numero_projeto,
        'cliente_nome_export',a.cliente_nome_export,'tipo_equipamento_nome_export',a.tipo_equipamento_nome_export,
        'status',a.status,'bloqueada',a.bloqueada,'motivo_bloqueio',a.motivo_bloqueio,'visibilidade',a.visibilidade,
        'prioridade',a.prioridade,'indice',a.indice,'posicao',a.posicao,'horas_previstas',a.horas_previstas::text,
        'horas_realizadas',a.horas_realizadas::text,'data_inicio',a.data_inicio,'data_limite',a.data_limite,
        'responsavel_id',a.responsavel_id,'responsavel_nome',u.nome,'updated_at',a.updated_at)
        order by coalesce(a.posicao,a.indice,0),a.id),'[]'::jsonb) items
    from queue a left join public.rm_users u on u.id=a.responsavel_id
  )
  select jsonb_build_object('cell',jsonb_build_object('id',c.id,'nome',c.nome,'updated_at',c.updated_at),
    'total',a.total,'complete',a.total<=2000,'items',case when a.total<=2000 then a.items else '[]'::jsonb end,
    'queue_version',encode(sha256(convert_to(jsonb_build_object('cell_updated_at',c.updated_at,'revisions',a.revisions)::text,'UTF8')),'hex'))
  from public.rm_celulas c cross join aggregate a where c.id=p_cell_id;
$$;

create function public.rm_web_planning_load_v1() returns jsonb
language sql stable security invoker set search_path='' as $$
  with counts as (
    select celula_id,count(*) as open_allocations,
      count(*) filter(where visibilidade) as visible_allocations,
      count(*) filter(where not visibilidade) as hidden_allocations,
      count(*) filter(where bloqueada='sim') as blocked_allocations,
      count(*) filter(where (data_limite at time zone 'America/Sao_Paulo')::date
        <(statement_timestamp() at time zone 'America/Sao_Paulo')::date) as overdue_allocations,
      count(*) filter(where horas_previstas is not null) as estimated_allocations,
      count(*) filter(where horas_previstas is null) as unestimated_allocations,
      sum(horas_previstas)::text as planned_hours,sum(horas_realizadas)::text as realized_hours
    from rm_private.web_open_cell_allocations_v1 group by celula_id
  )
  select jsonb_build_object('as_of',statement_timestamp(),'cells',coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'nome',c.nome,'open_allocations',coalesce(a.open_allocations,0),
    'visible_allocations',coalesce(a.visible_allocations,0),'hidden_allocations',coalesce(a.hidden_allocations,0),
    'blocked_allocations',coalesce(a.blocked_allocations,0),'overdue_allocations',coalesce(a.overdue_allocations,0),
    'estimated_allocations',coalesce(a.estimated_allocations,0),'unestimated_allocations',coalesce(a.unestimated_allocations,0),
    'planned_hours',a.planned_hours,'realized_hours',a.realized_hours)
    order by coalesce(c.indice,c.ordem,0),c.nome,c.id),'[]'::jsonb))
  from public.rm_celulas c left join counts a on a.celula_id=c.id;
$$;

create function public.rm_web_receivings_v1(p_reason text default 'all',p_search text default '',
  p_page integer default 1,p_page_size integer default 25) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if p_reason is null or p_reason not in ('all','without_number','without_type','without_allocation','awaiting_arrival','legacy_type_locked')
    or p_search is null or length(p_search)>200 or p_page is null or p_page<1 or p_page>10000
    or p_page_size is null or p_page_size<1 or p_page_size>100 then
    raise exception 'Filtros de recebimento inválidos.' using errcode='22023'; end if;
  with allocations as (
    select projeto_id,count(*) allocation_count from public.rm_celulas_projeto group by projeto_id
  ), projects as (
    select p.*,c.nome cliente_nome,t.nome tipo_equipamento_nome,coalesce(a.allocation_count,0) allocation_count,
      array_remove(array[
        case when nullif(btrim(p.numero),'') is null then 'without_number' end,
        case when p.tipo_equipamento_id is null then 'without_type' end,
        case when coalesce(a.allocation_count,0)=0 then 'without_allocation' end,
        case when p.chegada_do_equipamento is null then 'awaiting_arrival' end,
        case when p.tipo_equipamento_id is null and coalesce(a.allocation_count,0)>0 then 'legacy_type_locked' end
      ],null) reasons
    from public.rm_projetos p left join public.rm_clientes c on c.id=p.cliente_id
      left join public.rm_tipos_equipamento t on t.id=p.tipo_equipamento_id
      left join allocations a on a.projeto_id=p.id
    where p.data_real_de_entrega is null
      and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
      and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
      and (nullif(btrim(p.numero),'') is null or p.tipo_equipamento_id is null or coalesce(a.allocation_count,0)=0)
  ), filtered as materialized (
    select * from projects p where (p_reason='all' or p_reason=any(p.reasons))
      and (btrim(p_search)='' or strpos(lower(concat_ws(' ',p.numero,p.nome,p.cliente_nome,p.cliente_nome_exportacao,
        p.descricao_equipamento,p.nota_fiscal)),lower(btrim(p_search)))>0)
  ), page as (
    select * from filtered order by chegada_do_equipamento nulls first,created_at,id
    limit p_page_size offset ((p_page-1)*p_page_size)
  )
  select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object(
    'id',p.id,'numero',p.numero,'nome',p.nome,'cliente_id',p.cliente_id,'cliente_nome_exportacao',p.cliente_nome_exportacao,
    'cliente_nome',p.cliente_nome,'descricao_equipamento',p.descricao_equipamento,'chegada_do_equipamento',p.chegada_do_equipamento,
    'nota_fiscal',p.nota_fiscal,'tipo_equipamento_id',p.tipo_equipamento_id,'tipo_equipamento_nome',p.tipo_equipamento_nome,
    'status_pcp',p.status_pcp,'updated_at',p.updated_at,'allocation_count',p.allocation_count,'reasons',p.reasons)
    order by p.chegada_do_equipamento nulls first,p.created_at,p.id) from page p),'[]'::jsonb),
    'total',(select count(*) from filtered),'page',p_page,'page_size',p_page_size,
    'summary',jsonb_build_object(
      'without_number',(select count(*) from projects where 'without_number'=any(reasons)),
      'without_type',(select count(*) from projects where 'without_type'=any(reasons)),
      'without_allocation',(select count(*) from projects where 'without_allocation'=any(reasons)),
      'awaiting_arrival',(select count(*) from projects where 'awaiting_arrival'=any(reasons)),
      'legacy_type_locked',(select count(*) from projects where 'legacy_type_locked'=any(reasons)))) into result;
  return result;
end $$;
revoke all on function public.rm_web_cell_queue_snapshot_v1(uuid),public.rm_web_planning_load_v1(),
  public.rm_web_receivings_v1(text,text,integer,integer) from public,anon,service_role;
grant execute on function public.rm_web_cell_queue_snapshot_v1(uuid),public.rm_web_planning_load_v1(),
  public.rm_web_receivings_v1(text,text,integer,integer) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_stage_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  cell_id uuid; project_id uuid; item jsonb; item_id uuid; expected timestamptz;
  priority public.rm_prioridade_cel_enum; apply_order boolean; before_record jsonb; snapshot jsonb;
  project_ids uuid[]; queue_ids uuid[]; submitted_ids uuid[]; n integer; ordinal integer; changed uuid[]:='{}'; result jsonb;
begin
  if p_operation is distinct from 'save_cell_queue' then
    return rm_private.web_mutate_stage_core_v1(p_client_submission_id,p_operation,p_payload); end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or not coalesce(actor.perfil in ('administrador','padr_o'),false) then
    raise exception 'Operação restrita à administração/PCP.' using errcode='42501'; end if;
  if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
    and (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
  if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Envio inválido.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
  select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
  if found then
    if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
      raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
    return receipt.result||jsonb_build_object('idempotent_replay',true);
  end if;
  if not p_payload ?& array['celula_id','expected_queue_version','apply_order','items']
    or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('celula_id','expected_queue_version','apply_order','items'))
    or jsonb_typeof(p_payload->'celula_id') is distinct from 'string'
    or jsonb_typeof(p_payload->'expected_queue_version') is distinct from 'string'
    or (p_payload->>'expected_queue_version')!~'^[0-9a-f]{64}$'
    or jsonb_typeof(p_payload->'apply_order') is distinct from 'boolean'
    or jsonb_typeof(p_payload->'items') is distinct from 'array' then
    raise exception 'Fila ou versão inválida.' using errcode='22023'; end if;
  n:=jsonb_array_length(p_payload->'items');
  if n<1 or n>2000 then raise exception 'A fila deve conter entre 1 e 2000 alocações.' using errcode='22023'; end if;
  cell_id:=(p_payload->>'celula_id')::uuid; apply_order:=(p_payload->>'apply_order')::boolean;
  for item in select value from jsonb_array_elements(p_payload->'items') loop
    if jsonb_typeof(item)<>'object' or not item ?& array['id','expected_updated_at','prioridade']
      or exists(select 1 from jsonb_object_keys(item) k where k not in ('id','expected_updated_at','prioridade'))
      or jsonb_typeof(item->'id') is distinct from 'string'
      or jsonb_typeof(item->'expected_updated_at') is distinct from 'string'
      or jsonb_typeof(item->'prioridade') not in ('string','null') then
      raise exception 'Item de fila inválido.' using errcode='22023'; end if;
    item_id:=(item->>'id')::uuid; expected:=(item->>'expected_updated_at')::timestamptz;
    if not isfinite(expected) then raise exception 'Versão inválida.' using errcode='22023'; end if;
    priority:=(item->>'prioridade')::public.rm_prioridade_cel_enum;
  end loop;
  select array_agg((value->>'id')::uuid order by ordinality) into submitted_ids
    from jsonb_array_elements(p_payload->'items') with ordinality;
  if (select count(distinct id) from unnest(submitted_ids) id)<>n then
    raise exception 'Alocação repetida.' using errcode='22023'; end if;
  -- Existing writers acquire project11 before touching allocations or parent FK
  -- rows. Match that order, including currently closed projects, then lock the
  -- cell parent. New FK allocations either commit first and invalidate the hash,
  -- or wait until this queue save commits; no unlisted allocation is overwritten.
  select coalesce(array_agg(distinct projeto_id order by projeto_id),'{}') into project_ids
    from public.rm_celulas_projeto where celula_id=cell_id;
  foreach project_id in array project_ids loop
    perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
  end loop;
  perform 1 from public.rm_projetos where id=any(project_ids) order by id for update;
  perform 1 from public.rm_celulas where id=cell_id for update;
  if not found then raise exception 'Célula não encontrada.' using errcode='P0002'; end if;
  perform 1 from public.rm_celulas_projeto where celula_id=cell_id order by id for update;
  before_record:=public.rm_web_cell_queue_snapshot_v1(cell_id);
  if before_record is null then raise exception 'Célula não encontrada.' using errcode='P0002'; end if;
  if not (before_record->>'complete')::boolean or before_record->>'queue_version' is distinct from p_payload->>'expected_queue_version'
    or (before_record->>'total')::integer<>n then
    raise exception 'A fila foi alterada. Atualize antes de salvar.' using errcode='PT409'; end if;
  select array_agg((value->>'id')::uuid order by ordinality) into queue_ids
    from jsonb_array_elements(before_record->'items') with ordinality;
  if not submitted_ids @> queue_ids or not queue_ids @> submitted_ids or (not apply_order and submitted_ids<>queue_ids) then
    raise exception 'A fila deve conter todas as alocações e sua ordem atual.' using errcode='22023'; end if;
  ordinal:=0;
  for item in select value from jsonb_array_elements(p_payload->'items') loop
    ordinal:=ordinal+1; item_id:=(item->>'id')::uuid; expected:=(item->>'expected_updated_at')::timestamptz;
    priority:=(item->>'prioridade')::public.rm_prioridade_cel_enum;
    if not exists(select 1 from public.rm_celulas_projeto where id=item_id and updated_at=expected) then
      raise exception 'Alocação alterada. Atualize antes de salvar.' using errcode='PT409'; end if;
    update public.rm_celulas_projeto set prioridade=priority,
      posicao=case when apply_order then ordinal else posicao end,
      modified_by_id=actor.id,replanejada_em=clock_timestamp(),replanejada_por_id=actor.id,sync_source='supabase'
      where id=item_id and (prioridade is distinct from priority or (apply_order and posicao is distinct from ordinal));
    if found then changed:=array_append(changed,item_id); end if;
  end loop;
  snapshot:=public.rm_web_cell_queue_snapshot_v1(cell_id);
  result:=jsonb_build_object('operation',p_operation,'id',cell_id,'projeto_id',null,'updated_at',clock_timestamp(),
    'record',jsonb_build_object('celula_id',cell_id,'changed_ids',changed,'queue_version',snapshot->>'queue_version'),
    'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
  if p_operation='save_cell_queue' then raise exception 'Identificador, prioridade ou data inválida.' using errcode='22023'; end if;
  raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
    'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue'));
do $$ declare definition text; needle text:='when ''transition_stage_approval'' then ''em.approvals.decide'' end;'; begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
  execute replace(definition,needle,'when ''transition_stage_approval'' then ''em.approvals.decide'' when ''save_cell_queue'' then ''em.planning.manage'' end;');
  execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),
  rm_private.web_mutate_stage_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
