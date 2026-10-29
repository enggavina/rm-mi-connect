-- Web decisions reuse the mobile stage transaction; no operational row is
-- rewritten by installation, no actor/ACL is inferred, and no external work runs.
begin;

create table public.rm_web_stage_decisions (
  id uuid primary key default gen_random_uuid(),
  aprovacao_etapa_id uuid not null references public.rm_aprovacoes_etapas(id) on delete restrict,
  projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
  celula_id uuid not null references public.rm_celulas(id) on delete restrict,
  celula_projeto_id uuid not null references public.rm_celulas_projeto(id) on delete restrict,
  actor_id uuid not null references public.rm_users(id) on delete restrict,
  acao text not null check(acao in ('liberar','retornar','aprovar')),
  status_anterior public.rm_status_etapa_enum,
  status_novo public.rm_status_etapa_enum not null,
  observacao text check(observacao is null or length(observacao)<=10000),
  log_id uuid not null unique references public.rm_logs_aprovacao(id) on delete restrict,
  comentario_id uuid unique references public.rm_comentarios(id) on delete restrict,
  client_submission_id uuid not null unique,
  source text not null default 'web' check(source='web'),
  created_at timestamptz not null default clock_timestamp()
);
create index rm_web_stage_decisions_stage on public.rm_web_stage_decisions(aprovacao_etapa_id,created_at desc,id);
alter table public.rm_web_stage_decisions enable row level security;
create policy rm_web_stage_decisions_read on public.rm_web_stage_decisions for select to authenticated
  using((select rm_private.is_rm_authenticated()));
revoke all on public.rm_web_stage_decisions from public,anon,authenticated,service_role;
grant select on public.rm_web_stage_decisions to authenticated;

-- A private SECURITY INVOKER view shares safe context and the exact current
-- mobile authorization/state rules between list and detail. It never exposes
-- Auth identifiers, sync metadata, private credentials or URLs. Corporate scopes
-- are checked afresh by the BFF, not inferred from this legacy RM read boundary.
create view rm_private.web_stage_approval_context_v1 with(security_invoker=true) as
with actor as (
  select * from public.rm_users where auth_user_id=auth.uid() and status='ativo'
), base as (
  select a as stage_row,cp as allocation_row,p as project_row,
    cl.nome as cliente_nome,o.nome as origin_nome,d.nome as destination_nome,
    actor.id as actor_id,actor.perfil as actor_perfil,
    coalesce(actor.perfil='administrador' or exists(select 1 from public.rm_tablet_celula_users t
      where t.identidade_id=actor.id and t.celula_id=a.celula_origem_id),false) as cell_access,
    coalesce(actor.perfil='administrador' or a.aprovador_id=actor.id or actor.id=any(a.aprovadores_ids)
      or (a.aprovador_id is null and cardinality(a.aprovadores_ids)=0 and actor.perfil_assinante &&
        array['aprovador','aprovador_supervis_o']::public.rm_perfil_assinante_enum[]),false) as general_approver,
    coalesce(actor.id=any(a.aprovadores_retorno_ids),false) as return_approver
  from public.rm_aprovacoes_etapas a
  join public.rm_projetos p on p.id=a.projeto_id
  join public.rm_celulas o on o.id=a.celula_origem_id
  left join public.rm_celulas d on d.id=a.celula_destino_id
  left join public.rm_clientes cl on cl.id=p.cliente_id
  left join public.rm_celulas_projeto cp on cp.projeto_id=a.projeto_id and cp.celula_id=a.celula_origem_id
  left join actor on true
), eligible as (
  select *,case
    when not coalesce(actor_perfil in ('administrador','padr_o'),false) or actor_id is null then '[]'::jsonb
    when (allocation_row).id is null or ((stage_row).celula_projeto_id is not null
      and (stage_row).celula_projeto_id<>(allocation_row).id) then '[]'::jsonb
    when coalesce((stage_row).status,'nulo')<>'nulo' or not cell_access then '[]'::jsonb
    when (stage_row).status_cel_proj='retornado' then
      (case when (allocation_row).status='retornado' and (general_approver or return_approver)
        then '["retornar"]'::jsonb else '[]'::jsonb end)
      ||(case when general_approver then '["aprovar"]'::jsonb else '[]'::jsonb end)
    when (stage_row).status_cel_proj is not null and (stage_row).status_cel_proj=(allocation_row).status
      and general_approver then '["liberar"]'::jsonb
    else '[]'::jsonb end as available_actions
  from base
)
select (stage_row).id as id,(stage_row).projeto_id as projeto_id,(stage_row).celula_origem_id as celula_id,
  (stage_row).status as status,(stage_row).created_at as created_at,
  jsonb_build_object(
    'stage',jsonb_build_object('id',(stage_row).id,'projeto_id',(stage_row).projeto_id,
      'celula_projeto_id',(stage_row).celula_projeto_id,'celula_origem_id',(stage_row).celula_origem_id,
      'celula_destino_id',(stage_row).celula_destino_id,'bloquear_avanco_sem_aprov',(stage_row).bloquear_avanco_sem_aprov,
      'status',(stage_row).status,'status_cel_proj',(stage_row).status_cel_proj,'aprovador_id',(stage_row).aprovador_id,
      'aprovado_por_id',(stage_row).aprovado_por_id,'aprovadores_ids',(stage_row).aprovadores_ids,
      'aprovadores_retorno_ids',(stage_row).aprovadores_retorno_ids,'data_aprovacao',(stage_row).data_aprovacao,
      'created_at',(stage_row).created_at,'updated_at',(stage_row).updated_at),
    'allocation',case when (allocation_row).id is null then null else jsonb_build_object(
      'id',(allocation_row).id,'projeto_id',(allocation_row).projeto_id,'celula_id',(allocation_row).celula_id,
      'status',(allocation_row).status,'visibilidade',(allocation_row).visibilidade,'bloqueada',(allocation_row).bloqueada,
      'motivo_bloqueio',(allocation_row).motivo_bloqueio,'updated_at',(allocation_row).updated_at) end,
    'project',jsonb_build_object('id',(project_row).id,'numero',(project_row).numero,'nome',(project_row).nome,
      'cliente_id',(project_row).cliente_id,'cliente_nome_exportacao',(project_row).cliente_nome_exportacao,
      'cliente_nome',cliente_nome,'descricao_equipamento',(project_row).descricao_equipamento),
    'origin',jsonb_build_object('id',(stage_row).celula_origem_id,'nome',origin_nome),
    'destination',case when (stage_row).celula_destino_id is null then null
      else jsonb_build_object('id',(stage_row).celula_destino_id,'nome',destination_nome) end,
    'available_actions',available_actions,
    'action_reason',case when jsonb_array_length(available_actions)>0 then null
      when actor_id is null or not coalesce(actor_perfil in ('administrador','padr_o'),false) then 'Seu perfil permite apenas consulta.'
      when (allocation_row).id is null or ((stage_row).celula_projeto_id is not null
        and (stage_row).celula_projeto_id<>(allocation_row).id) then 'Etapa sem alocação compatível. Revise o planejamento.'
      when coalesce((stage_row).status,'nulo')<>'nulo' then 'Esta etapa já foi decidida.'
      when not cell_access then 'Você não tem acesso operacional cadastrado para esta célula.'
      when not general_approver and not ((stage_row).status_cel_proj='retornado' and return_approver)
        then 'Você não está autorizado como aprovador desta etapa.'
      when (stage_row).status_cel_proj='retornado' then 'O retorno exige que a célula esteja no status Retornado.'
      when (stage_row).status_cel_proj is null then 'A etapa não tem um status de liberação configurado.'
      else 'Aguarde a célula atingir o status previsto para liberar esta etapa.' end) as context
from eligible;
revoke all on rm_private.web_stage_approval_context_v1 from public,anon,authenticated,service_role;
grant select on rm_private.web_stage_approval_context_v1 to authenticated;

create function public.rm_web_stage_approvals_v1(p_project_id uuid default null,p_cell_id uuid default null,
  p_state text default 'pending',p_mine boolean default false,p_search text default '',p_page integer default 1,p_page_size integer default 25)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if p_state is null or p_state not in ('pending','approved','returned','all') or p_mine is null
    or p_search is null or length(p_search)>200 or p_page is null or p_page<1 or p_page>100000
    or p_page_size is null or p_page_size<1 or p_page_size>100 then
    raise exception 'Filtros de aprovação inválidos.' using errcode='22023'; end if;
  with filtered as materialized (
    select * from rm_private.web_stage_approval_context_v1 v
    where (p_project_id is null or v.projeto_id=p_project_id) and (p_cell_id is null or v.celula_id=p_cell_id)
      and (p_state='all' or (p_state='pending' and coalesce(v.status,'nulo')='nulo')
        or (p_state='approved' and v.status='aprovado') or (p_state='returned' and v.status='reprovado'))
      and (not p_mine or jsonb_array_length(v.context->'available_actions')>0)
      and (btrim(p_search)='' or strpos(lower(concat_ws(' ',v.context->'project'->>'numero',
        v.context->'project'->>'nome',v.context->'project'->>'cliente_nome',
        v.context->'project'->>'cliente_nome_exportacao',v.context->'origin'->>'nome',
        v.context->'destination'->>'nome')),lower(btrim(p_search)))>0)
  ), page as (
    select * from filtered order by created_at,id limit p_page_size offset ((p_page-1)*p_page_size)
  ) select jsonb_build_object('items',coalesce((select jsonb_agg(context order by created_at,id) from page),'[]'::jsonb),
    'total',(select count(*) from filtered),'page',p_page,'page_size',p_page_size) into result;
  return result;
end $$;

create function public.rm_web_stage_approval_snapshot_v1(p_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
  select v.context||jsonb_build_object(
    'approvers',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome) order by u.nome,u.id)
      from public.rm_users u where u.id=(v.context->'stage'->>'aprovador_id')::uuid
        or u.id in(select x::uuid from jsonb_array_elements_text(v.context->'stage'->'aprovadores_ids') x)),'[]'::jsonb),
    'return_approvers',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome) order by u.nome,u.id)
      from public.rm_users u where u.id in(select x::uuid from jsonb_array_elements_text(v.context->'stage'->'aprovadores_retorno_ids') x)),'[]'::jsonb),
    'decided_by',(select jsonb_build_object('id',u.id,'nome',u.nome) from public.rm_users u
      where u.id=(v.context->'stage'->>'aprovado_por_id')::uuid),
    'history',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'aprovacao_etapa_id',h.aprovacao_etapa_id,
      'acao',h.acao,'status_anterior',h.status_anterior,'status_novo',h.status_novo,'observacao',h.observacao,
      'actor_id',h.actor_id,'actor_nome',u.nome,'created_at',h.created_at,'source',h.source) order by h.created_at desc,h.id)
      from public.rm_web_stage_decisions h left join public.rm_users u on u.id=h.actor_id where h.aprovacao_etapa_id=v.id),'[]'::jsonb),
    -- Logs without an exact new link remain cell history, not a guessed action
    -- or stage association. This includes pre-existing and mobile decisions.
    'legacy_history',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'projeto_id',h.projeto_id,
      'celula_id',h.celula_id,'aprovador_id',h.aprovador_id,'aprovador_nome',u.nome,'status_aprovacao',h.status_aprovacao,
      'data_aprovacao',h.data_aprovacao,'created_at',h.created_at) order by h.data_aprovacao desc,h.id)
      from public.rm_logs_aprovacao h left join public.rm_users u on u.id=h.aprovador_id
      where h.projeto_id=v.projeto_id and h.celula_id=v.celula_id
        and not exists(select 1 from public.rm_web_stage_decisions w where w.log_id=h.id)),'[]'::jsonb))
  from rm_private.web_stage_approval_context_v1 v where v.id=p_id;
$$;
revoke all on function public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer),
  public.rm_web_stage_approval_snapshot_v1(uuid) from public,anon,service_role;
grant execute on function public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer),
  public.rm_web_stage_approval_snapshot_v1(uuid) to authenticated;

-- Return exact linkage from the shared transaction. Existing mobile response
-- keys and all state/outbox effects remain unchanged; the extra keys are additive.
do $$ declare definition text; needle text:='''novo_status_etapa'',decision);'; begin
  definition:=pg_get_functiondef('public.rm_transition_stage_approval_v1(uuid,uuid,text,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected shared stage transaction'; end if;
  execute replace(definition,needle,'''novo_status_etapa'',decision,''log_id'',log_id,''comentario_id'',comment_id,''affected_approval_ids'',affected);');
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_form_template_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  stage public.rm_aprovacoes_etapas%rowtype; allocation public.rm_celulas_projeto%rowtype;
  ident uuid; expected timestamptz; expected_cell timestamptz; action text; observation text;
  before_record jsonb; result jsonb; effect jsonb; history_id uuid;
begin
  if p_operation is distinct from 'transition_stage_approval' then
    return rm_private.web_mutate_form_template_core_v1(p_client_submission_id,p_operation,p_payload); end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or not coalesce(actor.perfil in ('administrador','padr_o'),false) then
    raise exception 'Perfil sem permissão para decidir etapas.' using errcode='42501'; end if;
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
  if not p_payload ?& array['aprovacao_etapa_id','expected_updated_at','expected_cell_updated_at','acao','observacao']
    or exists(select 1 from jsonb_object_keys(p_payload) k where k not in
      ('aprovacao_etapa_id','expected_updated_at','expected_cell_updated_at','acao','observacao'))
    or jsonb_typeof(p_payload->'aprovacao_etapa_id') is distinct from 'string'
    or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string'
    or jsonb_typeof(p_payload->'expected_cell_updated_at') is distinct from 'string'
    or jsonb_typeof(p_payload->'acao') is distinct from 'string'
    or p_payload->>'acao' not in ('liberar','retornar','aprovar')
    or jsonb_typeof(p_payload->'observacao') not in ('string','null') then
    raise exception 'Decisão ou versão inválida.' using errcode='22023'; end if;
  ident:=(p_payload->>'aprovacao_etapa_id')::uuid;
  expected:=(p_payload->>'expected_updated_at')::timestamptz;
  expected_cell:=(p_payload->>'expected_cell_updated_at')::timestamptz;
  if not isfinite(expected) or not isfinite(expected_cell) then
    raise exception 'Versão inválida.' using errcode='22023'; end if;
  action:=p_payload->>'acao'; observation:=nullif(btrim(p_payload->>'observacao'),'');
  if length(p_payload->>'observacao')>10000 or (action='retornar' and observation is null) then
    raise exception 'Informe o motivo do retorno, com até 10000 caracteres.' using errcode='22023'; end if;
  select * into stage from public.rm_aprovacoes_etapas where id=ident;
  if not found or stage.projeto_id is null then raise exception 'Etapa de projeto não encontrada.' using errcode='P0002'; end if;
  -- Project lock matches mobile, status updates and planning before taking rows.
  perform pg_advisory_xact_lock(hashtextextended(stage.projeto_id::text,11));
  select * into stage from public.rm_aprovacoes_etapas where id=ident for update;
  if not found or stage.projeto_id is null then raise exception 'Etapa de projeto não encontrada.' using errcode='P0002'; end if;
  select * into allocation from public.rm_celulas_projeto
    where projeto_id=stage.projeto_id and celula_id=stage.celula_origem_id for update;
  if not found then raise exception 'Célula de origem não encontrada.' using errcode='P0002'; end if;
  if stage.celula_projeto_id is not null and stage.celula_projeto_id<>allocation.id then
    raise exception 'Etapa sem alocação compatível.' using errcode='22023'; end if;
  perform rm_private.assert_cell_access(actor.id,allocation.celula_id);
  if not coalesce(actor.perfil='administrador' or stage.aprovador_id=actor.id or actor.id=any(stage.aprovadores_ids)
    or (action='retornar' and actor.id=any(stage.aprovadores_retorno_ids))
    or (stage.aprovador_id is null and cardinality(stage.aprovadores_ids)=0 and
      actor.perfil_assinante && array['aprovador','aprovador_supervis_o']::public.rm_perfil_assinante_enum[]),false) then
    raise exception 'Operador sem permissão de aprovação nesta etapa.' using errcode='42501'; end if;
  if stage.updated_at is distinct from expected or allocation.updated_at is distinct from expected_cell then
    raise exception 'Etapa ou célula alterada. Atualize antes de decidir.' using errcode='PT409'; end if;
  before_record:=public.rm_web_stage_approval_snapshot_v1(ident);
  effect:=public.rm_transition_stage_approval_v1(ident,actor.id,action,observation);
  insert into public.rm_web_stage_decisions(aprovacao_etapa_id,projeto_id,celula_id,celula_projeto_id,
    actor_id,acao,status_anterior,status_novo,observacao,log_id,comentario_id,client_submission_id)
    values(ident,stage.projeto_id,stage.celula_origem_id,allocation.id,actor.id,action,stage.status,
      (effect->>'novo_status_etapa')::public.rm_status_etapa_enum,observation,(effect->>'log_id')::uuid,
      (effect->>'comentario_id')::uuid,p_client_submission_id) returning id into history_id;
  result:=jsonb_build_object('operation',p_operation,'id',ident,'projeto_id',stage.projeto_id,
    'updated_at',(select updated_at from public.rm_aprovacoes_etapas where id=ident),
    'decision_id',history_id,'snapshot',public.rm_web_stage_approval_snapshot_v1(ident),'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
  if p_operation='transition_stage_approval' then
    raise exception 'Identificador, decisão ou data inválida.' using errcode='22023'; end if;
  raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
    'create_form_template','save_form_template','publish_form_template','transition_stage_approval'));
do $$ declare definition text; needle text:='when ''publish_form_template'' then ''em.form_templates.manage'' end;'; begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
  execute replace(definition,needle,'when ''publish_form_template'' then ''em.form_templates.manage'' when ''transition_stage_approval'' then ''em.approvals.decide'' end;');
  execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),
  rm_private.web_mutate_form_template_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
