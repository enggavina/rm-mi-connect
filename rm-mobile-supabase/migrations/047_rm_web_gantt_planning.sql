-- A complete, bounded Gantt projection and atomic date/dependency planning.
-- Installation does not create plans, baselines, receipts or operational rows.
begin;

create table rm_private.gantt_project_plans(
 id uuid primary key default gen_random_uuid(),
 projeto_id uuid not null unique references public.rm_projetos(id) on delete restrict,
 links jsonb not null default '[]' check(jsonb_typeof(links)='array' and jsonb_array_length(links)<=4000),
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid not null references public.rm_users(id) on delete restrict
);
create table rm_private.gantt_baselines(
 id uuid primary key default gen_random_uuid(),
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 label text not null check(length(btrim(label)) between 1 and 120),
 items jsonb not null check(jsonb_typeof(items)='array' and jsonb_array_length(items)<=2000),
 created_at timestamptz not null default clock_timestamp(),
 created_by uuid not null references public.rm_users(id) on delete restrict
);
create index rm_gantt_baselines_latest on rm_private.gantt_baselines(projeto_id,created_at desc,id desc);
revoke all on rm_private.gantt_project_plans,rm_private.gantt_baselines from public,anon,authenticated,service_role;
alter table rm_private.gantt_project_plans enable row level security;
alter table rm_private.gantt_baselines enable row level security;
grant select on rm_private.gantt_project_plans,rm_private.gantt_baselines to authenticated;

create function rm_private.web_gantt_read_allowed_v1() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in('administrador','padr_o','auditor'))
 and(not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.factor_type='totp' and f.status='verified') or auth.jwt()->>'aal'='aal2');
$$;
revoke all on function rm_private.web_gantt_read_allowed_v1() from public,anon,authenticated,service_role;
grant execute on function rm_private.web_gantt_read_allowed_v1() to authenticated;
create policy rm_gantt_plans_read on rm_private.gantt_project_plans for select to authenticated
 using(rm_private.web_gantt_read_allowed_v1() and exists(select 1 from public.rm_projetos p where p.id=projeto_id));
create policy rm_gantt_baselines_read on rm_private.gantt_baselines for select to authenticated
 using(rm_private.web_gantt_read_allowed_v1() and exists(select 1 from public.rm_projetos p where p.id=projeto_id));

-- The version includes every active allocation of the project, including those
-- omitted by the current cell/open filter. An off-screen edit invalidates a draft.
create function rm_private.web_gantt_project_version_v1(p_project_id uuid) returns text
language sql stable security invoker set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_object('project',jsonb_build_object('id',p.id,'updated_at',p.updated_at),
  'allocations',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at) order by a.id)
   from public.rm_celulas_projeto a where a.projeto_id=p.id and not a.retirada),'[]'),
  'plan',coalesce((select jsonb_build_object('id',g.id,'updated_at',g.updated_at,'links',g.links) from rm_private.gantt_project_plans g where g.projeto_id=p.id),'null'),
  'baseline',coalesce((select jsonb_build_object('id',b.id,'created_at',b.created_at) from rm_private.gantt_baselines b where b.projeto_id=p.id order by b.created_at desc,b.id desc limit 1),'null'))::text,'UTF8')),'hex')
 from public.rm_projetos p where p.id=p_project_id;
$$;
revoke all on function rm_private.web_gantt_project_version_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function rm_private.web_gantt_project_version_v1(uuid) to authenticated;

create function public.rm_web_gantt_snapshot_v1(p_filters jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare pid uuid;cid uuid;closed boolean;n bigint;ids uuid[];pids uuid[];result jsonb;can_plan boolean;
begin
 if not coalesce(rm_private.web_gantt_read_allowed_v1(),false) then raise exception 'Acesso ao cronograma não autorizado.' using errcode='42501';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or not p_filters?&array['project_id','cell_id','include_closed']
  or exists(select 1 from jsonb_object_keys(p_filters) k where k not in('project_id','cell_id','include_closed'))
  or jsonb_typeof(p_filters->'project_id') not in('null','string') or jsonb_typeof(p_filters->'cell_id') not in('null','string')
  or jsonb_typeof(p_filters->'include_closed') is distinct from 'boolean' then raise exception 'Seleção do cronograma inválida.' using errcode='22023';end if;
 pid:=(p_filters->>'project_id')::uuid;cid:=(p_filters->>'cell_id')::uuid;closed:=(p_filters->>'include_closed')::boolean;
 if pid is not null and(cid is not null or not closed) then raise exception 'A visão de projeto deve incluir seu roteiro completo.' using errcode='22023';end if;
 if pid is not null and not exists(select 1 from public.rm_projetos p where p.id=pid) then raise exception 'Projeto não disponível.' using errcode='P0002';end if;
 if cid is not null and not exists(select 1 from public.rm_celulas c where c.id=cid) then raise exception 'Célula não disponível.' using errcode='P0002';end if;
 select count(*),array_agg(a.id order by a.id) into n,ids from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id
  where not a.retirada and(pid is null or a.projeto_id=pid) and(cid is null or a.celula_id=cid)
  and(closed or(p.data_real_de_entrega is null and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
   and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
   and a.status is distinct from 'finalizado'::public.rm_status_cel_proj_enum and a.status is distinct from 'n_a'::public.rm_status_cel_proj_enum));
 if n>2000 then return jsonb_build_object('as_of',statement_timestamp(),'filters',p_filters,'total',n,'complete',false,'items','[]'::jsonb,'projects','[]'::jsonb,'cells','[]'::jsonb,'links','[]'::jsonb,'baseline',null);end if;
 select array_agg(distinct a.projeto_id order by a.projeto_id) into pids from public.rm_celulas_projeto a where a.id=any(ids);
 if pid is not null then pids:=array[pid];end if;
 select perfil in('administrador','padr_o') into can_plan from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 select jsonb_build_object('as_of',statement_timestamp(),'filters',p_filters,'total',n,'complete',true,
  'items',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'projeto_id',a.projeto_id,'celula_id',a.celula_id,
   'numero_projeto',coalesce(a.numero_projeto,p.numero),'cliente_nome_export',a.cliente_nome_export,'celula_nome',c.nome,
   'status',a.status,'bloqueada',a.bloqueada,'motivo_bloqueio',a.motivo_bloqueio,'visibilidade',a.visibilidade,'prioridade',a.prioridade,
   'indice',a.indice,'posicao',a.posicao,'responsavel_nome',u.nome,'data_inicio',a.data_inicio,'data_limite',a.data_limite,'updated_at',a.updated_at,
   'can_edit',coalesce(can_plan,false) and p.data_real_de_entrega is null and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
    and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
    and a.status is distinct from 'finalizado'::public.rm_status_cel_proj_enum and a.status is distinct from 'n_a'::public.rm_status_cel_proj_enum)
   order by p.numero nulls last,a.projeto_id,a.indice nulls last,a.posicao nulls last,a.id)
   from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id
    left join public.rm_users u on u.id=a.responsavel_id where a.id=any(ids)),'[]'),
  'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,'updated_at',p.updated_at,
   'plan_version',rm_private.web_gantt_project_version_v1(p.id),'closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false),
   'planned_start',p.data_prevista_inicio,'planned_end',p.data_prevista_final,'contract_date',p.data_contratual,'renegotiated_date',p.data_renegociada) order by p.id)
   from public.rm_projetos p where p.id=any(pids)),'[]'),
  'cells',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome) order by c.nome,c.id) from public.rm_celulas c
   where c.id=cid or exists(select 1 from public.rm_celulas_projeto a where a.id=any(ids) and a.celula_id=c.id)),'[]'),
  'links',coalesce((select jsonb_agg(l.value||jsonb_build_object('projeto_id',g.projeto_id) order by g.projeto_id,l.value->>'predecessor_id',l.value->>'successor_id')
   from rm_private.gantt_project_plans g cross join lateral jsonb_array_elements(g.links) l
   where g.projeto_id=any(pids) and(l.value->>'predecessor_id')::uuid=any(ids) and(l.value->>'successor_id')::uuid=any(ids)),'[]'),
  'baseline',(select jsonb_build_object('id',b.id,'label',b.label,'created_at',b.created_at,'items',b.items) from rm_private.gantt_baselines b
   where b.projeto_id=pid order by b.created_at desc,b.id desc limit 1)) into result;
 if octet_length(result::text)>10485760 or jsonb_array_length(result->'links')>4000 then raise exception 'O cronograma excede o limite de leitura. Selecione um projeto ou célula.' using errcode='PT413';end if;
 return result;
exception when invalid_text_representation then raise exception 'Identificador do cronograma inválido.' using errcode='22023';
end $$;
revoke all on function public.rm_web_gantt_snapshot_v1(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_gantt_snapshot_v1(jsonb) to authenticated;

-- Metadata participates in the same confirmed project deletion closure. Dates
-- and offline IDs never acquire an implicit deletion or an unrelated cascade.
alter function rm_private.project_delete_scope_v1(uuid) rename to project_delete_scope_before_gantt_v1;
create function rm_private.project_delete_scope_v1(p_project uuid)
returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 select * from rm_private.project_delete_scope_before_gantt_v1(p_project)
 union all select 'rm_private','gantt_baselines',array(select id from rm_private.gantt_baselines where projeto_id=p_project)
 union all select 'rm_private','gantt_project_plans',array(select id from rm_private.gantt_project_plans where projeto_id=p_project);
$$;
revoke all on function rm_private.project_delete_scope_v1(uuid),rm_private.project_delete_scope_before_gantt_v1(uuid) from public,anon,authenticated,service_role;
do $$ declare d text;needle text:='foreach label in array array[''public.rm_project_document_locations''';begin
 d:=pg_get_functiondef('rm_private.web_mutate_before_route_config_v1(uuid,text,jsonb)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected project deletion leaf order';end if;
 execute replace(d,needle,'foreach label in array array[''rm_private.gantt_baselines'',''rm_private.gantt_project_plans'',''public.rm_project_document_locations''');
 execute pg_get_functiondef('rm_private.project_delete_context_v1(uuid)'::regprocedure);
end $$;

-- Baselines are immutable snapshots. Confirmed project deletion is the only
-- product operation which removes them; installation leaves history untouched.
create function rm_private.guard_gantt_baseline_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' and rm_private.project_deletion_in_progress_v1(old.projeto_id) then return old;end if;
 raise exception 'A referência aprovada do cronograma é imutável. Crie uma nova referência.' using errcode='42501';
end $$;
revoke all on function rm_private.guard_gantt_baseline_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_gantt_baseline before update or delete on rm_private.gantt_baselines for each row execute function rm_private.guard_gantt_baseline_v1();

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_gantt_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype;receipt rm_private.web_mutation_receipts%rowtype;p public.rm_projetos%rowtype;allocation_row public.rm_celulas_projeto%rowtype;
 proj jsonb;item jsonb;link jsonb;field_value jsonb;changes jsonb;desired jsonb;old_links jsonb;remaining jsonb;roots uuid[];
 project_ids uuid[];item_ids uuid[];pid uuid;dep_pid uuid;base_pid uuid;bid uuid;child_id uuid;expected timestamptz;
 new_start timestamptz;start_day date;field_name text;reason text;label text;
 result jsonb;child_result jsonb;before_record jsonb;changed uuid[]:='{}';links_changed boolean:=false;n int;
begin
 if p_operation is distinct from 'save_gantt_plan' then return rm_private.web_mutate_before_gantt_v1(p_client_submission_id,p_operation,p_payload);end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à administração/PCP.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023';end if;
 if octet_length(p_payload::text)>2097152 then raise exception 'O plano excede o limite de envio.' using errcode='PT413';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio já utilizado com outro conteúdo.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload?&array['reason','projects','items'] or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('reason','projects','items','dependencies','baseline'))
  or jsonb_typeof(p_payload->'reason') is distinct from 'string' or length(btrim(p_payload->>'reason')) not between 3 and 2000
  or jsonb_typeof(p_payload->'projects') is distinct from 'array' or jsonb_array_length(p_payload->'projects') not between 1 and 2000
  or jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items')>2000 then raise exception 'Plano ou justificativa inválidos.' using errcode='22023';end if;
 reason:=btrim(p_payload->>'reason');
 for proj in select value from jsonb_array_elements(p_payload->'projects') loop
  if jsonb_typeof(proj)<>'object' or not proj?&array['id','expected_updated_at','expected_plan_version']
   or exists(select 1 from jsonb_object_keys(proj) k where k not in('id','expected_updated_at','expected_plan_version'))
   or jsonb_typeof(proj->'id') is distinct from 'string' or jsonb_typeof(proj->'expected_updated_at') is distinct from 'string'
   or(proj->>'expected_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
   or jsonb_typeof(proj->'expected_plan_version') is distinct from 'string' or(proj->>'expected_plan_version') !~ '^[0-9a-f]{64}$' then raise exception 'Versão de projeto inválida.' using errcode='22023';end if;
  pid:=(proj->>'id')::uuid;expected:=(proj->>'expected_updated_at')::timestamptz;
  if not isfinite(expected) then raise exception 'Versão de projeto inválida.' using errcode='22023';end if;
 end loop;
 select array_agg((value->>'id')::uuid order by (value->>'id')::uuid) into project_ids from jsonb_array_elements(p_payload->'projects');
 if cardinality(project_ids)<>(select count(distinct x) from unnest(project_ids) x) then raise exception 'Projeto repetido.' using errcode='22023';end if;
 if p_payload?'dependencies' then
  field_value:=p_payload->'dependencies';
  if jsonb_typeof(field_value)<>'object' or not field_value?&array['projeto_id','links'] or exists(select 1 from jsonb_object_keys(field_value) k where k not in('projeto_id','links'))
   or jsonb_typeof(field_value->'projeto_id') is distinct from 'string' or jsonb_typeof(field_value->'links') is distinct from 'array' or jsonb_array_length(field_value->'links')>4000
   or cardinality(project_ids)<>1 then raise exception 'Dependências exigem o contexto de um projeto.' using errcode='22023';end if;
  dep_pid:=(field_value->>'projeto_id')::uuid;desired:=field_value->'links';
  if dep_pid<>project_ids[1] then raise exception 'Projeto das dependências divergente.' using errcode='22023';end if;
  for link in select x from jsonb_array_elements(desired) x loop
   if jsonb_typeof(link)<>'object' or not link?&array['predecessor_id','successor_id','lag_days']
    or exists(select 1 from jsonb_object_keys(link) k where k not in('predecessor_id','successor_id','lag_days'))
    or jsonb_typeof(link->'predecessor_id') is distinct from 'string' or jsonb_typeof(link->'successor_id') is distinct from 'string'
    or jsonb_typeof(link->'lag_days') is distinct from 'number' or(link->>'lag_days') !~ '^\d+$' or(link->>'lag_days')::numeric not between 0 and 3650
    or(link->>'predecessor_id')::uuid=(link->>'successor_id')::uuid then raise exception 'Dependência término-início inválida.' using errcode='22023';end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(desired) l group by(l->>'predecessor_id')::uuid,(l->>'successor_id')::uuid having count(*)>1) then raise exception 'Dependência repetida.' using errcode='22023';end if;
  select coalesce(jsonb_agg(jsonb_build_object('predecessor_id',(l->>'predecessor_id')::uuid,'successor_id',(l->>'successor_id')::uuid,'lag_days',(l->>'lag_days')::int)
   order by(l->>'predecessor_id')::uuid,(l->>'successor_id')::uuid),'[]') into desired from jsonb_array_elements(desired) l;
  remaining:=desired;
  while jsonb_array_length(remaining)>0 loop
   select array_agg(distinct(l->>'predecessor_id')::uuid) into roots from jsonb_array_elements(remaining) l
    where not exists(select 1 from jsonb_array_elements(remaining) incoming where incoming->>'successor_id'=l->>'predecessor_id');
   if coalesce(cardinality(roots),0)=0 then raise exception 'As dependências formam um ciclo.' using errcode='22023';end if;
   select coalesce(jsonb_agg(l),'[]') into remaining from jsonb_array_elements(remaining) l where not(l->>'predecessor_id')::uuid=any(roots);
  end loop;
 end if;
 if p_payload?'baseline' then
  field_value:=p_payload->'baseline';
  if jsonb_typeof(field_value)<>'object' or not field_value?&array['projeto_id','label'] or exists(select 1 from jsonb_object_keys(field_value) k where k not in('projeto_id','label'))
   or jsonb_typeof(field_value->'projeto_id') is distinct from 'string' or jsonb_typeof(field_value->'label') is distinct from 'string' or length(btrim(field_value->>'label')) not between 1 and 120
   or cardinality(project_ids)<>1 or jsonb_array_length(p_payload->'items')<>0 or p_payload?'dependencies' then raise exception 'Salve as alterações antes de criar uma referência do projeto.' using errcode='22023';end if;
  base_pid:=(field_value->>'projeto_id')::uuid;label:=btrim(field_value->>'label');
  if base_pid<>project_ids[1] then raise exception 'Projeto da referência divergente.' using errcode='22023';end if;
 end if;
 if jsonb_array_length(p_payload->'items')=0 and dep_pid is null and base_pid is null then raise exception 'Nenhuma alteração informada.' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(p_payload->'items') loop
  if jsonb_typeof(item)<>'object' or not item?&array['id','expected_updated_at','changes'] or exists(select 1 from jsonb_object_keys(item) k where k not in('id','expected_updated_at','changes'))
   or jsonb_typeof(item->'id') is distinct from 'string' or jsonb_typeof(item->'expected_updated_at') is distinct from 'string'
   or(item->>'expected_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
   or jsonb_typeof(item->'changes') is distinct from 'object' or item->'changes'='{}'::jsonb
   or exists(select 1 from jsonb_object_keys(item->'changes') k where k not in('data_inicio','data_limite')) then raise exception 'Alteração de data inválida.' using errcode='22023';end if;
  pid:=(item->>'id')::uuid;expected:=(item->>'expected_updated_at')::timestamptz;
  if not isfinite(expected) then raise exception 'Versão inválida.' using errcode='22023';end if;
  for field_name,field_value in select * from jsonb_each(item->'changes') loop
   if jsonb_typeof(field_value)<>'null' then
    if jsonb_typeof(field_value)<>'string' or(field_value#>>'{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Use datas de calendário ou deixe o campo vazio.' using errcode='22023';end if;
    start_day:=(field_value#>>'{}')::date;
    if start_day not between '1900-01-01'::date and '2200-12-31'::date then raise exception 'Data fora do intervalo permitido.' using errcode='22023';end if;
   end if;
  end loop;
 end loop;
 select coalesce(array_agg((value->>'id')::uuid),'{}') into item_ids from jsonb_array_elements(p_payload->'items');
 if cardinality(item_ids)<>(select count(distinct x) from unnest(item_ids) x) then raise exception 'Alocação repetida.' using errcode='22023';end if;

 -- Same project lock and order as the existing planning/mobile writers.
 foreach pid in array project_ids loop
  perform pg_advisory_xact_lock(hashtextextended(pid::text,11));
  select * into p from public.rm_projetos where id=pid for update;
  if not found then raise exception 'Projeto inexistente.' using errcode='P0002';end if;
  select x into proj from jsonb_array_elements(p_payload->'projects') x where(x->>'id')::uuid=pid;
  if p.updated_at is distinct from (proj->>'expected_updated_at')::timestamptz then raise exception 'O projeto mudou. Recarregue o cronograma.' using errcode='PT409';end if;
  if p.data_real_de_entrega is not null or p.status_pcp in('cancelado','finalizando_para_faturar') then raise exception 'Projeto encerrado: somente consulta.' using errcode='22023';end if;
  perform 1 from public.rm_celulas_projeto where projeto_id=pid order by id for update;
  perform 1 from rm_private.gantt_project_plans where projeto_id=pid for update;
  if rm_private.web_gantt_project_version_v1(pid) is distinct from proj->>'expected_plan_version' then raise exception 'O roteiro ou planejamento mudou. Recarregue antes de salvar.' using errcode='PT409';end if;
  if(select count(*) from public.rm_celulas_projeto where projeto_id=pid and not retirada)>2000 then raise exception 'O roteiro excede o limite de planejamento.' using errcode='PT413';end if;
 end loop;
 if exists(select 1 from unnest(item_ids) selected(id) left join public.rm_celulas_projeto x on x.id=selected.id where x.id is null or not x.projeto_id=any(project_ids)) then raise exception 'Alocação não pertence aos projetos informados.' using errcode='22023';end if;
 if exists(select 1 from unnest(project_ids) selected(id) where selected.id is distinct from dep_pid and selected.id is distinct from base_pid and not exists(select 1 from public.rm_celulas_projeto x where x.id=any(item_ids) and x.projeto_id=selected.id)) then raise exception 'Projeto sem alteração no lote.' using errcode='22023';end if;
 if dep_pid is not null then
  if exists(select 1 from jsonb_array_elements(desired) l where not exists(select 1 from public.rm_celulas_projeto a where a.id=(l->>'predecessor_id')::uuid and a.projeto_id=dep_pid and not a.retirada)
   or not exists(select 1 from public.rm_celulas_projeto a where a.id=(l->>'successor_id')::uuid and a.projeto_id=dep_pid and not a.retirada)) then raise exception 'Uma dependência aponta para outra origem ou célula retirada.' using errcode='22023';end if;
 end if;
 select jsonb_build_object('projects',p_payload->'projects','items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'projeto_id',x.projeto_id,'data_inicio',x.data_inicio,'data_limite',x.data_limite,'updated_at',x.updated_at) order by x.id) from public.rm_celulas_projeto x where x.id=any(item_ids)),'[]'),
  'links',coalesce((select jsonb_agg(jsonb_build_object('projeto_id',g.projeto_id,'links',g.links) order by g.projeto_id) from rm_private.gantt_project_plans g where g.projeto_id=any(project_ids)),'[]')) into before_record;
 for item in select x from jsonb_array_elements(p_payload->'items') x order by(x->>'id')::uuid loop
  select * into allocation_row from public.rm_celulas_projeto where id=(item->>'id')::uuid;
  if allocation_row.updated_at is distinct from(item->>'expected_updated_at')::timestamptz then raise exception 'A alocação mudou. Recarregue antes de salvar.' using errcode='PT409';end if;
  if allocation_row.retirada or allocation_row.status in('finalizado','n_a') then raise exception 'Célula retirada, concluída ou N/A: somente consulta.' using errcode='22023';end if;
  changes:='{}';
  for field_name,field_value in select * from jsonb_each(item->'changes') loop
   new_start:=case when jsonb_typeof(field_value)='null' then null else ((field_value#>>'{}')::date+time '12:00') at time zone 'America/Sao_Paulo' end;
   if(case field_name when 'data_inicio' then allocation_row.data_inicio else allocation_row.data_limite end) is distinct from new_start then changes:=changes||jsonb_build_object(field_name,new_start);end if;
  end loop;
  if changes<>'{}'::jsonb then
   -- Reuse plan_cell validation and its audit receipt. Child IDs are stable for
   -- one parent submission; no new SSO permit is needed inside this transaction.
   child_id:=md5('em-gantt-v1:'||p_client_submission_id::text||':'||allocation_row.id::text)::uuid;
   child_result:=rm_private.web_mutate_before_gantt_v1(child_id,'plan_cell',jsonb_build_object('projeto_id',allocation_row.projeto_id,'celula_id',allocation_row.celula_id,'expected_updated_at',allocation_row.updated_at,'changes',changes));
   changed:=array_append(changed,allocation_row.id);
  end if;
 end loop;
 if dep_pid is not null then
  select links into old_links from rm_private.gantt_project_plans where projeto_id=dep_pid;
  -- The project snapshot deliberately hides retired stages. Replacing its
  -- visible edges must not erase links which may return with a restored stage.
  select coalesce(jsonb_agg(l order by (l->>'predecessor_id')::uuid,(l->>'successor_id')::uuid),'[]') into desired
   from jsonb_array_elements(desired||coalesce((select jsonb_agg(l) from jsonb_array_elements(coalesce(old_links,'[]')) l
    where exists(select 1 from public.rm_celulas_projeto x where x.projeto_id=dep_pid and x.retirada
     and x.id in((l->>'predecessor_id')::uuid,(l->>'successor_id')::uuid))),'[]')) l;
  if jsonb_array_length(desired)>4000 then raise exception 'O projeto excede o limite de dependências preservadas.' using errcode='PT413';end if;
  -- Include preserved links in cycle checking, so restoring an allocation can
  -- never turn a previously accepted dependency plan into a directed cycle.
  remaining:=desired;
  while jsonb_array_length(remaining)>0 loop
   select array_agg(distinct(l->>'predecessor_id')::uuid) into roots from jsonb_array_elements(remaining) l
    where not exists(select 1 from jsonb_array_elements(remaining) incoming where incoming->>'successor_id'=l->>'predecessor_id');
   if coalesce(cardinality(roots),0)=0 then raise exception 'As dependências formam um ciclo, incluindo etapas retiradas.' using errcode='22023';end if;
   select coalesce(jsonb_agg(l),'[]') into remaining from jsonb_array_elements(remaining) l where not(l->>'predecessor_id')::uuid=any(roots);
  end loop;
  links_changed:=coalesce(old_links,'[]') is distinct from desired;
  if links_changed then insert into rm_private.gantt_project_plans(projeto_id,links,updated_by) values(dep_pid,desired,actor.id)
   on conflict(projeto_id) do update set links=excluded.links,updated_at=clock_timestamp(),updated_by=excluded.updated_by;end if;
 end if;
 -- Validate the WHOLE graph after the staged changes. Errors roll back all
 -- child receipts and dates. Missing dates are allowed as unplanned work.
 if base_pid is null then
  if exists(select 1 from rm_private.gantt_project_plans g cross join lateral jsonb_array_elements(g.links) l
   left join public.rm_celulas_projeto predecessor on predecessor.id=(l->>'predecessor_id')::uuid and predecessor.projeto_id=g.projeto_id
   left join public.rm_celulas_projeto successor on successor.id=(l->>'successor_id')::uuid and successor.projeto_id=g.projeto_id
   where g.projeto_id=any(project_ids) and not predecessor.retirada and not successor.retirada
    and predecessor.data_limite is not null and successor.data_inicio is not null and (successor.data_inicio at time zone 'America/Sao_Paulo')::date < (predecessor.data_limite at time zone 'America/Sao_Paulo')::date+1+(l->>'lag_days')::integer) then
   raise exception 'O plano viola uma dependência término-início. Revise o projeto e as datas antes de salvar.' using errcode='PT409';end if;
 end if;
 if base_pid is not null then
  select coalesce(jsonb_agg(jsonb_build_object('allocation_id',a.id,'data_inicio',a.data_inicio,'data_limite',a.data_limite) order by a.id),'[]') into desired from public.rm_celulas_projeto a where a.projeto_id=base_pid and not a.retirada;
  insert into rm_private.gantt_baselines(projeto_id,label,items,created_by) values(base_pid,label,desired,actor.id) returning id into bid;
 end if;
 pid:=case when cardinality(project_ids)=1 then project_ids[1] else null end;
 result:=jsonb_build_object('operation',p_operation,'id',coalesce(pid,p_client_submission_id),'projeto_id',pid,'updated_at',clock_timestamp(),
  'record',jsonb_build_object('changed_ids',to_jsonb(changed),'links_changed',links_changed,'baseline_id',bid),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='save_gantt_plan' then raise exception 'Identificador, versão ou data inválidos.' using errcode='22023';end if;raise;
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_gantt_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

do $$ declare d text;constraint_definition text;needle text:='when ''plan_cell'' then ''em.planning.manage''';begin
 select pg_get_constraintdef(oid) into constraint_definition from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check';
 if strpos(constraint_definition,'''delete_form_template''::text')=0 then raise exception 'Migration 046 is required';end if;
 constraint_definition:=replace(constraint_definition,'''delete_form_template''::text','''delete_form_template''::text, ''save_gantt_plan''::text');
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check '||constraint_definition;
 d:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected SSO capability map';end if;
 execute replace(d,needle,needle||' when ''save_gantt_plan'' then ''em.planning.manage''');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;
