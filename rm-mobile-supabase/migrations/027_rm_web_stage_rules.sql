-- Immutable operational configuration IDs; no existing row changes on install.
begin;
create table rm_private.stage_rule_events(
 id uuid primary key default gen_random_uuid(),projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 etapa_id uuid not null references public.rm_aprovacoes_etapas(id) on delete restrict,
 related_etapa_id uuid references public.rm_aprovacoes_etapas(id) on delete restrict,
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 action text not null check(action in('create','replace','retire','restore','use')),
 log_id uuid references public.rm_logs_aprovacao(id) on delete restrict,client_submission_id uuid,
 created_at timestamptz not null default clock_timestamp(),
 check((action='replace' and related_etapa_id is not null) or action<>'replace'),
 check((action='use' and log_id is not null) or (action<>'use' and log_id is null))
);
create index rm_stage_rule_events_project on rm_private.stage_rule_events(projeto_id,etapa_id,created_at,id);
create unique index rm_stage_rule_events_birth on rm_private.stage_rule_events(etapa_id) where action in('create','replace');
create unique index rm_stage_rule_events_effect on rm_private.stage_rule_events(log_id,etapa_id) where action='use';
revoke all on rm_private.stage_rule_events from public,anon,authenticated,service_role;

create function rm_private.stage_rule_config_v1(r public.rm_aprovacoes_etapas) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object('celula_origem_id',r.celula_origem_id,'celula_destino_id',r.celula_destino_id,'status_cel_proj',r.status_cel_proj,
  'bloquear_avanco_sem_aprov',r.bloquear_avanco_sem_aprov,
  'aprovadores_ids',coalesce((select jsonb_agg(x order by x) from(select distinct x from unnest(r.aprovadores_ids||array[r.aprovador_id]) x where x is not null) u),'[]'::jsonb),
  'aprovadores_retorno_ids',coalesce((select jsonb_agg(x order by x) from(select distinct x from unnest(r.aprovadores_retorno_ids) x where x is not null) u),'[]'::jsonb));
$$;
revoke all on function rm_private.stage_rule_config_v1(public.rm_aprovacoes_etapas) from public,anon,authenticated,service_role;

-- Read-only, bounded proof. Never expose private receipt bodies or grant their
-- SELECT privileges to an authenticated user. Missing evidence is not invented.
create function rm_private.stage_rule_metadata_v1(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not rm_private.is_rm_authenticated() then return null; end if;
 if (select count(*) from public.rm_aprovacoes_etapas where projeto_id=p_project_id)>1000 then
  return jsonb_build_object('items','[]'::jsonb,'version',encode(sha256(convert_to('overflow','UTF8')),'hex')); end if;
 with recursive rules as materialized(select a as configuration,a.*,rm_private.stage_rule_config_v1(a) effective_config from public.rm_aprovacoes_etapas a where projeto_id=p_project_id),
 edges as materialized(select etapa_id newer,related_etapa_id older from rm_private.stage_rule_events where projeto_id=p_project_id and action='replace'),
 families(seed,id) as(select id,id from rules union select f.seed,case when e.newer=f.id then e.older else e.newer end
   from families f join edges e on e.newer=f.id or e.older=f.id),
 evidence as(
  select r.*,
   coalesce(r.status,'nulo')<>'nulo' or r.aprovado_por_id is not null or r.data_aprovacao is not null
    or exists(select 1 from rm_private.stage_rule_events e where e.etapa_id=r.id and e.action='use')
    or exists(select 1 from public.rm_web_stage_decisions d where d.aprovacao_etapa_id=r.id)
    or exists(select 1 from rm_private.mobile_mutation_receipts m where m.rpc_name='rm_transition_stage_approval_v1' and
     (m.params->>'p_aprovacao_etapa_id'=r.id::text or m.result->>'aprovacao_etapa_id'=r.id::text or m.result->'affected_approval_ids' ? r.id::text))
    or exists(select 1 from rm_private.web_mutation_receipts w where w.operation='transition_stage_approval' and (w.payload->>'aprovacao_etapa_id'=r.id::text or w.result->>'id'=r.id::text))
    or exists(select 1 from public.rm_sync_outbox o where o.entity_type='Aprovacao_Etapa_Transition' and
     (o.record_id=r.id or o.payload->'affected_approval_ids' ? r.id::text)) used,
   exists(select 1 from public.rm_logs_aprovacao l where l.projeto_id=p_project_id and l.celula_id=r.celula_origem_id
    and coalesce(l.data_aprovacao,l.created_at)>=r.created_at
    and not exists(select 1 from public.rm_web_stage_decisions d where d.log_id=l.id)
    and not exists(select 1 from rm_private.stage_rule_events e where e.log_id=l.id)
    and not exists(select 1 from rm_private.mobile_mutation_receipts m where m.rpc_name='rm_transition_stage_approval_v1' and m.result->>'log_id'=l.id::text)
    and not exists(select 1 from public.rm_sync_outbox o where o.entity_type='Aprovacao_Etapa_Transition' and o.payload->>'log_id'=l.id::text)) history_ambiguous
  from rules r
 ), dtos as(
  select r.id,jsonb_build_object('id',r.id,'used',r.used,'history_ambiguous',r.history_ambiguous,
   'managed_birth',exists(select 1 from rm_private.stage_rule_events e where e.etapa_id=r.id and e.action in('create','replace')),
   'related_return_ids',coalesce((select jsonb_agg(x.id order by x.id) from rules x where x.celula_origem_id=r.celula_destino_id
    and x.celula_destino_id=r.celula_origem_id and x.status_cel_proj='retornado'),'[]'::jsonb),
   'pair_ambiguous',(select count(*) from rules x where x.celula_origem_id=r.celula_destino_id and x.celula_destino_id=r.celula_origem_id and x.status_cel_proj='retornado')>1
    or (exists(select 1 from rules x where x.celula_origem_id=r.celula_destino_id and x.celula_destino_id=r.celula_origem_id and x.status_cel_proj='retornado')
     and (select count(*) from rules x where x.celula_origem_id=r.celula_origem_id and x.celula_destino_id=r.celula_destino_id and x.status_cel_proj is distinct from 'retornado')>1),
   'family_ids',coalesce((select jsonb_agg(f.id order by f.id) from families f where f.seed=r.id),'[]'::jsonb),
   'active_family',exists(select 1 from families f join rules x on x.id=f.id where f.seed=r.id and x.id<>r.id and x.ativo),
   'active_duplicate',exists(select 1 from rules x where x.id<>r.id and x.ativo and x.effective_config=r.effective_config),
   'supersedes_id',(select older from edges where newer=r.id)) dto from evidence r
 ) select jsonb_build_object('items',coalesce((select jsonb_agg(dto order by id) from dtos),'[]'::jsonb),
  'version',encode(sha256(convert_to(jsonb_build_object('metadata',coalesce((select jsonb_agg(dto order by id) from dtos),'[]'::jsonb),
   'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'created_at',e.created_at) order by e.id) from rm_private.stage_rule_events e where e.projeto_id=p_project_id),'[]'::jsonb))::text,'UTF8')),'hex')) into result;
 return result;
end $$;


revoke all on function rm_private.stage_rule_metadata_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function rm_private.stage_rule_metadata_v1(uuid) to authenticated;

create function public.rm_web_stage_rules_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_choices boolean default false)
returns jsonb language sql stable security invoker set search_path='' as $$
 with context as materialized(
  select p.id project_id,p.numero,p.status_pcp,p.data_real_de_entrega,p.updated_at project_updated_at,
   p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false) closed,
   a.id allocation_id,a.celula_id,a.status,a.updated_at allocation_updated_at,c.nome celula_nome
  from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id join public.rm_celulas c on c.id=a.celula_id
  where p.id=p_project_id and a.id=p_allocation_id
 ), allocations as materialized(select a.*,c.nome,c.updated_at cell_updated_at from public.rm_celulas_projeto a
  join public.rm_celulas c on c.id=a.celula_id where a.projeto_id=p_project_id),
 rules as materialized(select * from public.rm_aprovacoes_etapas where projeto_id=p_project_id),
 own_rules as materialized(select r.* from rules r cross join context c where r.celula_origem_id=c.celula_id
  and (r.celula_projeto_id=c.allocation_id or r.celula_projeto_id is null)),
 members as materialized(select t.*,u.updated_at user_updated_at,u.status user_status from public.rm_tablet_celula_users t
  left join public.rm_users u on u.id=t.identidade_id where t.celula_id in(select celula_id from allocations)),
 eligible as materialized(select u.id,u.nome,u.matricula,array_agg(distinct m.celula_id order by m.celula_id) celula_ids
  from members m join public.rm_users u on u.id=m.identidade_id where u.status='ativo' group by u.id,u.nome,u.matricula),
 counts as materialized(select (select count(*) from rules) total,(select count(*) from own_rules) selected_total,
  (select count(*) from allocations) allocations_total,(select count(*) from eligible) eligible_total,(select count(*) from members) memberships_total),
 proof as materialized(select rm_private.stage_rule_metadata_v1(p_project_id) value),
 metadata as materialized(select x from proof cross join jsonb_array_elements(coalesce(value->'items','[]'::jsonb)) x),
 flags as(
  select r.*,m.x,c.closed or coalesce(c.status='n_a',false) or n.total>1000 or n.allocations_total>1000 or n.eligible_total>1000 or n.memberships_total>5000
   or coalesce(r.status_cel_proj='retornado',false) or coalesce((m.x->>'used')::boolean,true) or coalesce((m.x->>'history_ambiguous')::boolean,true)
   or (coalesce(jsonb_array_length(m.x->'related_return_ids'),0)>0 and not coalesce((m.x->>'managed_birth')::boolean,false)) protected
  from own_rules r cross join context c cross join counts n left join metadata m on m.x->>'id'=r.id::text
 ), rule_dtos as(
  select r.id,r.created_at,jsonb_build_object('id',r.id,'projeto_id',r.projeto_id,'celula_projeto_id',r.celula_projeto_id,
   'celula_origem_id',r.celula_origem_id,'celula_destino_id',r.celula_destino_id,'celula_destino_nome',(select nome from public.rm_celulas where id=r.celula_destino_id),
   'status_cel_proj',r.status_cel_proj,'status',r.status,'bloquear_avanco_sem_aprov',r.bloquear_avanco_sem_aprov,
   'aprovador_id',r.aprovador_id,'aprovadores_ids',r.aprovadores_ids,'aprovadores_retorno_ids',r.aprovadores_retorno_ids,
   'aprovado_por_id',r.aprovado_por_id,'data_aprovacao',r.data_aprovacao,'ativo',r.ativo,'created_at',r.created_at,'updated_at',r.updated_at,
   'approvers',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome,'matricula',u.matricula,
     'eligible',u.status='ativo' and exists(select 1 from members t where t.identidade_id=u.id and t.celula_id=r.celula_origem_id)) order by u.nome,u.id)
    from public.rm_users u where u.id=r.aprovador_id or u.id=any(r.aprovadores_ids)),'[]'::jsonb),
   'return_approvers',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome,'matricula',u.matricula,
     'eligible',u.status='ativo' and exists(select 1 from members t where t.identidade_id=u.id and t.celula_id=r.celula_destino_id)) order by u.nome,u.id)
    from public.rm_users u where u.id=any(r.aprovadores_retorno_ids)),'[]'::jsonb),
   'used',coalesce((r.x->>'used')::boolean,false),'history_ambiguous',coalesce((r.x->>'history_ambiguous')::boolean,false),
   'managed_birth',coalesce((r.x->>'managed_birth')::boolean,false),
   'related_return_ids',coalesce(r.x->'related_return_ids','[]'::jsonb),'pair_ambiguous',coalesce((r.x->>'pair_ambiguous')::boolean,false),
   'family_ids',coalesce(r.x->'family_ids',jsonb_build_array(r.id)),'supersedes_id',r.x->'supersedes_id',
   'can_edit',not r.protected and r.ativo and n.total<1000,'can_retire',not r.protected and r.ativo,
   'can_restore',not r.protected and not r.ativo and r.status_cel_proj is not null and r.celula_destino_id is distinct from r.celula_origem_id
    and exists(select 1 from allocations a where a.celula_id=r.celula_destino_id and not coalesce(a.status in('finalizado','n_a'),false))
    and not coalesce((r.x->>'active_family')::boolean,true) and not coalesce((r.x->>'active_duplicate')::boolean,true),
   'action_reason',case when c.closed or c.status='n_a' then 'Projeto encerrado ou célula N/A: somente consulta.'
    when n.total>1000 or n.allocations_total>1000 or n.eligible_total>1000 or n.memberships_total>5000 then 'O conjunto excede o limite de edição completa.'
    when r.status_cel_proj='retornado' then 'Etapa de retorno gerida pelo fluxo de decisão: somente consulta.'
    when (r.x->>'used')::boolean then 'Há evidência de uso desta regra. A configuração permanece preservada.'
    when (r.x->>'history_ambiguous')::boolean then 'Há histórico da célula sem vínculo exato: regra preservada para consulta.'
    when jsonb_array_length(r.x->'related_return_ids')>0 and not(r.x->>'managed_birth')::boolean then 'Há retorno relacionado ao trajeto legado. A configuração permanece preservada.'
    when not r.ativo and (r.status_cel_proj is null or r.celula_destino_id is not distinct from r.celula_origem_id or not exists(
     select 1 from allocations a where a.celula_id=r.celula_destino_id and not coalesce(a.status in('finalizado','n_a'),false)))
     then 'O destino ou status original não é compatível com a alocação atual. A restauração exige reconciliação operacional.'
    when not r.ativo and (r.x->>'active_family')::boolean then 'Retire a versão sucessora ativa antes de restaurar esta configuração.'
    when not r.ativo and (r.x->>'active_duplicate')::boolean then 'Já existe uma configuração equivalente ativa.'
    when not r.ativo then 'Regra retirada. Restaure o mesmo item para recuperar uma tentativa offline compatível.' else null end) dto
  from flags r cross join context c cross join counts n
 ), summary as(
  select encode(sha256(convert_to(jsonb_build_object('project',c.project_id,'project_version',c.project_updated_at,'allocation',c.allocation_id,
   'allocations',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at,'cell_version',a.cell_updated_at) order by a.id) from allocations a),'[]'::jsonb),
   'rules',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'updated_at',r.updated_at) order by r.id) from rules r),'[]'::jsonb),
   'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'updated_at',m.updated_at,'identity',m.identidade_id,'user_version',m.user_updated_at,'status',m.user_status) order by m.id) from members m),'[]'::jsonb),
   'proof',p.value->>'version')::text,'UTF8')),'hex') version from context c cross join proof p
 ) select jsonb_build_object('project',jsonb_build_object('id',c.project_id,'numero',c.numero,'status_pcp',c.status_pcp,'data_real_de_entrega',c.data_real_de_entrega,'updated_at',c.project_updated_at,'closed',c.closed),
  'allocation',jsonb_build_object('id',c.allocation_id,'projeto_id',c.project_id,'celula_id',c.celula_id,'celula_nome',c.celula_nome,'status',c.status,'updated_at',c.allocation_updated_at),
  'rules',case when n.total<=1000 and n.allocations_total<=1000 then coalesce((select jsonb_agg(dto order by created_at,id) from rule_dtos),'[]'::jsonb) else '[]'::jsonb end,
  'statuses',case when p_include_choices and n.total<=1000 and n.allocations_total<=1000 and n.eligible_total<=1000 and n.memberships_total<=5000
    and exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in('administrador','padr_o'))
    then coalesce((select jsonb_agg(jsonb_build_object('key',s.option_key,'label',s.bubble_display) order by s.sort_order,s.option_key) from public.rm_option_sets s where s.option_set_key='status_cel_proj' and s.option_key<>'retornado'),'[]'::jsonb) else '[]'::jsonb end,
  'destinations',case when p_include_choices and n.total<=1000 and n.allocations_total<=1000 and n.eligible_total<=1000 and n.memberships_total<=5000
    and exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in('administrador','padr_o'))
    then coalesce((select jsonb_agg(jsonb_build_object('allocation_id',a.id,'celula_id',a.celula_id,'nome',a.nome,'status',a.status,'updated_at',a.updated_at,
     'can_select',a.celula_id<>c.celula_id and not coalesce(a.status in('finalizado','n_a'),false),
     'reason',case when a.celula_id=c.celula_id then 'Selecione outra célula de destino.' when a.status in('finalizado','n_a') then 'Célula de destino finalizada ou N/A.' else null end) order by a.nome,a.id) from allocations a),'[]'::jsonb) else '[]'::jsonb end,
  'eligible_users',case when p_include_choices and n.total<=1000 and n.allocations_total<=1000 and n.eligible_total<=1000 and n.memberships_total<=5000
    and exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in('administrador','padr_o'))
    then coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'nome',u.nome,'matricula',u.matricula,'celula_ids',u.celula_ids) order by u.nome,u.id) from eligible u),'[]'::jsonb) else '[]'::jsonb end,
  'rules_version',v.version,'total',n.total,'selected_total',n.selected_total,'complete',n.total<=1000,'allocations_total',n.allocations_total,'allocations_complete',n.allocations_total<=1000,
  'eligible_total',n.eligible_total,'eligible_complete',n.eligible_total<=1000,'memberships_total',n.memberships_total,'memberships_complete',n.memberships_total<=5000)
 from context c cross join counts n cross join summary v;
$$;
revoke all on function public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_form_reviewer_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype; project public.rm_projetos%rowtype;
 allocation public.rm_celulas_projeto%rowtype; destination public.rm_celulas_projeto%rowtype; stage public.rm_aprovacoes_etapas%rowtype;
 next_rule public.rm_aprovacoes_etapas%rowtype; snapshot jsonb; rule_dto jsonb; result jsonb; before_record jsonb; config jsonb;
 action text; allowed text[]; project_id uuid; allocation_id uuid; target_id uuid; new_id uuid; locked_project uuid;
 expected_project timestamptz; expected_allocation timestamptz; expected_rule timestamptz;
 approvers uuid[]; return_approvers uuid[]; all_candidates uuid[]; changed uuid[]:='{}'; previous_id uuid;
begin
 if p_operation not in('manage_stage_rules','transition_stage_approval') or p_operation is null then
  return rm_private.web_mutate_form_reviewer_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à administração/planejamento.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 if p_operation='transition_stage_approval' then
  if not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id) then
   select projeto_id into locked_project from public.rm_aprovacoes_etapas where id=(p_payload->>'aprovacao_etapa_id')::uuid;
   if locked_project is not null then
    perform pg_advisory_xact_lock(hashtextextended(locked_project::text,11));
    perform 1 from public.rm_projetos where id=locked_project for update;
    perform set_config('rm.stage_rule_submission_id',p_client_submission_id::text,true);
   end if;
  end if;
  return rm_private.web_mutate_form_reviewer_core_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 action:=p_payload->>'action';
 allowed:=array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','expected_rules_version'];
 if action='create' then allowed:=allowed||array['id','config'];
 elsif action='replace' then allowed:=allowed||array['etapa_id','expected_etapa_updated_at','replacement_id','config','confirm_change'];
 elsif action in('retire','restore') then allowed:=allowed||array['etapa_id','expected_etapa_updated_at','confirm_change'];
 else raise exception 'Ação de regra inválida.' using errcode='22023'; end if;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or exists(select 1 from unnest(array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','expected_rules_version']) k where jsonb_typeof(p_payload->k) is distinct from 'string')
  or p_payload->>'expected_rules_version' !~ '^[0-9a-f]{64}$'
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then raise exception 'Contexto ou versão inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; allocation_id:=(p_payload->>'celula_projeto_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
 if action<>'create' then
  if p_payload->'confirm_change' is distinct from 'true'::jsonb or jsonb_typeof(p_payload->'etapa_id') is distinct from 'string'
   or jsonb_typeof(p_payload->'expected_etapa_updated_at') is distinct from 'string'
   or p_payload->>'expected_etapa_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then raise exception 'Confirme a alteração e informe a versão da regra.' using errcode='22023'; end if;
  target_id:=(p_payload->>'etapa_id')::uuid; expected_rule:=(p_payload->>'expected_etapa_updated_at')::timestamptz;
 end if;
 if action in('create','replace') then
  if jsonb_typeof(p_payload->case when action='create' then 'id' else 'replacement_id' end) is distinct from 'string' then raise exception 'UUID da nova regra obrigatório.' using errcode='22023'; end if;
  new_id:=(p_payload->>case when action='create' then 'id' else 'replacement_id' end)::uuid;
  config:=p_payload->'config';
  if jsonb_typeof(config) is distinct from 'object' or not config ?& array['celula_destino_id','status_cel_proj','bloquear_avanco_sem_aprov','aprovadores_ids','aprovadores_retorno_ids']
   or exists(select 1 from jsonb_object_keys(config) k where k not in('celula_destino_id','status_cel_proj','bloquear_avanco_sem_aprov','aprovadores_ids','aprovadores_retorno_ids'))
   or jsonb_typeof(config->'celula_destino_id') is distinct from 'string' or jsonb_typeof(config->'status_cel_proj') is distinct from 'string'
   or jsonb_typeof(config->'bloquear_avanco_sem_aprov') is distinct from 'boolean'
   or jsonb_typeof(config->'aprovadores_ids') is distinct from 'array' or jsonb_typeof(config->'aprovadores_retorno_ids') is distinct from 'array'
   or jsonb_array_length(config->'aprovadores_ids') not between 1 and 100 or jsonb_array_length(config->'aprovadores_retorno_ids') not between 1 and 100
   or exists(select 1 from jsonb_array_elements((config->'aprovadores_ids')||(config->'aprovadores_retorno_ids')) x where jsonb_typeof(x) is distinct from 'string') then raise exception 'Configuração de regra inválida.' using errcode='22023'; end if;
  approvers:=array(select jsonb_array_elements_text(config->'aprovadores_ids'))::uuid[];
  return_approvers:=array(select jsonb_array_elements_text(config->'aprovadores_retorno_ids'))::uuid[];
  if cardinality(approvers)<>(select count(distinct x) from unnest(approvers) x) or cardinality(return_approvers)<>(select count(distinct x) from unnest(return_approvers) x) then raise exception 'Aprovadores repetidos.' using errcode='22023'; end if;
  all_candidates:=approvers||return_approvers;
  next_rule.id:=new_id; next_rule.projeto_id:=project_id; next_rule.celula_projeto_id:=allocation_id;
  next_rule.celula_destino_id:=(config->>'celula_destino_id')::uuid; next_rule.status_cel_proj:=(config->>'status_cel_proj')::public.rm_status_cel_proj_enum;
  next_rule.bloquear_avanco_sem_aprov:=(config->>'bloquear_avanco_sem_aprov')::boolean;
  next_rule.aprovadores_ids:=approvers; next_rule.aprovadores_retorno_ids:=return_approvers; next_rule.status:='nulo'; next_rule.ativo:=true;
  if next_rule.status_cel_proj='retornado' then raise exception 'Retorno é gerido pela decisão, não pelo editor.' using errcode='22023'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 perform 1 from public.rm_celulas_projeto where projeto_id=project_id order by id for update;
 select * into allocation from public.rm_celulas_projeto where id=allocation_id and projeto_id=project_id;
 if not found then raise exception 'Célula não pertence ao projeto.' using errcode='P0002'; end if;
 perform 1 from public.rm_celulas where id in(select celula_id from public.rm_celulas_projeto where projeto_id=project_id) order by id for share;
 perform 1 from public.rm_users where id=any(all_candidates) or id in(select identidade_id from public.rm_tablet_celula_users
  where celula_id in(select celula_id from public.rm_celulas_projeto where projeto_id=project_id)) order by id for share;
 perform 1 from public.rm_tablet_celula_users where celula_id in(select celula_id from public.rm_celulas_projeto where projeto_id=project_id) order by id for share;
 perform 1 from public.rm_aprovacoes_etapas where projeto_id=project_id order by id for update;
 snapshot:=public.rm_web_stage_rules_snapshot_v1(project_id,allocation_id,true);
 if project.updated_at<>expected_project or allocation.updated_at<>expected_allocation or snapshot->>'rules_version' is distinct from p_payload->>'expected_rules_version' then raise exception 'Projeto, regras ou vínculos alterados. Recarregue.' using errcode='PT409'; end if;
 if not(snapshot->>'complete')::boolean or not(snapshot->>'allocations_complete')::boolean or not(snapshot->>'eligible_complete')::boolean or not(snapshot->>'memberships_complete')::boolean then raise exception 'O conjunto excede o limite de edição completa.' using errcode='22023'; end if;
 if (snapshot->'project'->>'closed')::boolean or allocation.status='n_a' then raise exception 'Projeto encerrado ou célula N/A: somente consulta.' using errcode='22023'; end if;
 if action<>'create' then
  select * into stage from public.rm_aprovacoes_etapas where id=target_id and projeto_id=project_id and celula_origem_id=allocation.celula_id
   and (celula_projeto_id=allocation_id or celula_projeto_id is null);
  if not found then raise exception 'Regra não pertence à alocação atual.' using errcode='22023'; end if;
  if stage.updated_at<>expected_rule then raise exception 'A regra foi alterada. Recarregue.' using errcode='PT409'; end if;
  select x into rule_dto from jsonb_array_elements(snapshot->'rules') x where x->>'id'=target_id::text;
  if stage.status_cel_proj='retornado' or (rule_dto->>'used')::boolean or (rule_dto->>'history_ambiguous')::boolean
   or (jsonb_array_length(rule_dto->'related_return_ids')>0 and not(rule_dto->>'managed_birth')::boolean) then
   raise exception 'Regra com uso, retorno ou histórico ambíguo: somente consulta.' using errcode='22023'; end if;
  if action='replace' and not stage.ativo then raise exception 'Uma regra retirada não pode ser substituída. Restaure o ID original quando permitido.' using errcode='22023'; end if;
  before_record:=rule_dto;
 end if;
 if action in('create','replace') then
  if (snapshot->>'total')::int>=1000 then raise exception 'Não cabe outra versão no conjunto completo de regras.' using errcode='22023'; end if;
  if exists(select 1 from public.rm_aprovacoes_etapas where id=new_id)
   or exists(select 1 from rm_private.mobile_mutation_receipts m where m.rpc_name='rm_transition_stage_approval_v1' and
    (m.params->>'p_aprovacao_etapa_id'=new_id::text or m.result->>'aprovacao_etapa_id'=new_id::text or m.result->'affected_approval_ids' ? new_id::text))
   or exists(select 1 from rm_private.web_mutation_receipts w where w.operation='transition_stage_approval' and (w.payload->>'aprovacao_etapa_id'=new_id::text or w.result->>'id'=new_id::text))
   or exists(select 1 from public.rm_sync_outbox o where o.entity_type='Aprovacao_Etapa_Transition' and
    (o.record_id=new_id or o.payload->'affected_approval_ids' ? new_id::text)) then raise exception 'UUID da nova regra já utilizado ou reservado por histórico offline.' using errcode='22023'; end if;
  select * into destination from public.rm_celulas_projeto where projeto_id=project_id and celula_id=next_rule.celula_destino_id;
  if not found or destination.celula_id=allocation.celula_id or destination.status in('finalizado','n_a') then raise exception 'Selecione outra célula de destino alocada e disponível no projeto.' using errcode='22023'; end if;
  if exists(select 1 from(select unnest(approvers) u,allocation.celula_id c union all select unnest(return_approvers),destination.celula_id) q
   where not exists(select 1 from public.rm_users u join public.rm_tablet_celula_users t on t.identidade_id=u.id and t.celula_id=q.c where u.id=q.u and u.status='ativo')) then raise exception 'Aprovadores devem estar ativos e vinculados às células correspondentes.' using errcode='22023'; end if;
  next_rule.celula_origem_id:=allocation.celula_id;
  if exists(select 1 from public.rm_aprovacoes_etapas a where a.projeto_id=project_id and a.ativo and a.id is distinct from target_id
   and rm_private.stage_rule_config_v1(a)=rm_private.stage_rule_config_v1(next_rule)) then raise exception 'Já existe uma configuração equivalente ativa.' using errcode='22023'; end if;
  if action='replace' then
   update public.rm_aprovacoes_etapas set ativo=false,sync_source='supabase' where id=target_id;
   previous_id:=target_id; changed:=array_append(changed,target_id);
  end if;
  insert into public.rm_aprovacoes_etapas(id,projeto_id,celula_projeto_id,celula_tipo_equipamento_id,celula_origem_id,celula_destino_id,
   status_cel_proj,bloquear_avanco_sem_aprov,aprovadores_ids,aprovadores_retorno_ids,status,ativo,sync_source)
   values(new_id,project_id,allocation_id,case when action='replace' then stage.celula_tipo_equipamento_id end,allocation.celula_id,
    next_rule.celula_destino_id,next_rule.status_cel_proj,next_rule.bloquear_avanco_sem_aprov,approvers,return_approvers,'nulo',true,'supabase') returning * into stage;
  changed:=array_append(changed,new_id);
  insert into rm_private.stage_rule_events(projeto_id,etapa_id,related_etapa_id,actor_id,action,client_submission_id)
   values(project_id,new_id,previous_id,actor.id,action,p_client_submission_id);
 elsif action='retire' then
  if stage.ativo then
   update public.rm_aprovacoes_etapas set ativo=false,sync_source='supabase' where id=target_id returning * into stage;
   changed:=array_append(changed,target_id);
  end if;
 else
  if not stage.ativo then
   if not(rule_dto->>'can_restore')::boolean then raise exception '%',rule_dto->>'action_reason' using errcode='22023'; end if;
   update public.rm_aprovacoes_etapas set ativo=true,sync_source='supabase' where id=target_id returning * into stage;
   changed:=array_append(changed,target_id);
  end if;
 end if;
 if action in('retire','restore') and cardinality(changed)>0 then
  insert into rm_private.stage_rule_events(projeto_id,etapa_id,actor_id,action,client_submission_id)
   values(project_id,target_id,actor.id,action,p_client_submission_id);
 end if;
 snapshot:=public.rm_web_stage_rules_snapshot_v1(project_id,allocation_id,true);
 result:=jsonb_build_object('operation',p_operation,'id',stage.id,'projeto_id',project_id,'updated_at',stage.updated_at,
  'record',jsonb_build_object('projeto_id',project_id,'celula_projeto_id',allocation_id,'action',action,'etapa_id',stage.id,
   'previous_etapa_id',previous_id,'rules_version',snapshot->>'rules_version','changed_ids',to_jsonb(changed)),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='manage_stage_rules' then raise exception 'Identificador, estado ou data inválidos.' using errcode='22023'; end if; raise;
end $$;

-- Retire is the only removal path. Operational config cannot be silently
-- rewritten by a later generic importer; model rows keep their 018 editor.
create function rm_private.guard_operational_stage_identity_v1() returns trigger
language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then
  if old.projeto_id is not null then raise exception 'Regra operacional preserva seu ID; retire pelo planejamento.' using errcode='22023'; end if;
  return old;
 end if;
 if (old.projeto_id is not null or new.projeto_id is not null) and row(old.projeto_id,old.celula_projeto_id,old.celula_tipo_equipamento_id,
   old.celula_origem_id,old.celula_destino_id,old.status_cel_proj,old.bloquear_avanco_sem_aprov,old.aprovador_id,old.aprovadores_ids,old.aprovadores_retorno_ids)
  is distinct from row(new.projeto_id,new.celula_projeto_id,new.celula_tipo_equipamento_id,new.celula_origem_id,new.celula_destino_id,
   new.status_cel_proj,new.bloquear_avanco_sem_aprov,new.aprovador_id,new.aprovadores_ids,new.aprovadores_retorno_ids) then
  raise exception 'Configuração operacional é imutável por ID; substitua a regra pelo planejamento.' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function rm_private.guard_operational_stage_identity_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_operational_stage_identity before update or delete on public.rm_aprovacoes_etapas
 for each row execute function rm_private.guard_operational_stage_identity_v1();

-- Retired rows remain readable tombstones for SQLite. The normal decision list
-- excludes them; a direct detail remains consultation with no available action.
create view rm_private.web_stage_effective_context_v1 with(security_invoker=true) as
 select v.id,v.projeto_id,v.celula_id,v.status,v.created_at,
  v.context||jsonb_build_object('stage',(v.context->'stage')||jsonb_build_object('ativo',a.ativo),
   'available_actions',case when a.ativo then v.context->'available_actions' else '[]'::jsonb end,
   'action_reason',case when a.ativo then v.context->'action_reason' else to_jsonb('Regra retirada do planejamento: somente consulta.'::text) end) context,
  a.ativo from rm_private.web_stage_approval_context_v1 v join public.rm_aprovacoes_etapas a on a.id=v.id;
revoke all on rm_private.web_stage_effective_context_v1 from public,anon,authenticated,service_role;
grant select on rm_private.web_stage_effective_context_v1 to authenticated;
do $$ declare definition text; begin
 definition:=pg_get_functiondef('public.rm_web_stage_approvals_v1(uuid,uuid,text,boolean,text,integer,integer)'::regprocedure);
 if strpos(definition,'where (p_project_id is null')=0 then raise exception 'Unexpected stage list definition'; end if;
 definition:=replace(definition,'rm_private.web_stage_approval_context_v1','rm_private.web_stage_effective_context_v1');
 execute replace(definition,'where (p_project_id is null','where v.ativo and (p_project_id is null');
 definition:=pg_get_functiondef('public.rm_web_stage_approval_snapshot_v1(uuid)'::regprocedure);
 execute replace(definition,'rm_private.web_stage_approval_context_v1','rm_private.web_stage_effective_context_v1');
end $$;

do $$ declare definition text; marker text; begin
 definition:=pg_get_functiondef('public.rm_transition_stage_approval_v1(uuid,uuid,text,text)'::regprocedure);
 definition:=replace(definition,'pr public.rm_projetos%rowtype;','pr public.rm_projetos%rowtype; locked_project uuid; submission_id uuid;');
 marker:='  perform pg_advisory_xact_lock(hashtextextended(a.projeto_id::text,11));';
 if strpos(definition,marker)=0 then raise exception 'Unexpected shared stage lock'; end if;
 definition:=replace(definition,marker,marker||$patch$
  locked_project:=a.projeto_id;
  submission_id:=nullif(current_setting('rm.stage_rule_submission_id',true),'')::uuid;
  perform set_config('rm.stage_rule_submission_id','',true);
  perform 1 from public.rm_projetos where id=locked_project for update;
  perform 1 from public.rm_celulas_projeto where projeto_id=locked_project order by id for update;
  perform 1 from public.rm_aprovacoes_etapas where projeto_id=locked_project order by id for update;
$patch$);
 marker:='  select * into a from public.rm_aprovacoes_etapas where id=p_aprovacao_etapa_id for update;';
 definition:=replace(definition,marker,marker||$patch$
  if a.projeto_id is distinct from locked_project then raise exception 'Contexto da regra alterado. Sincronize novamente.' using errcode='PT409'; end if;
  if not a.ativo then raise exception 'Regra retirada do planejamento. Solicite ao gestor restaurar a mesma configuração quando permitido; a tentativa offline foi preservada.' using errcode='PT409'; end if;
$patch$);
 definition:=replace(definition,'and status_cel_proj=''retornado'' order by','and ativo and status_cel_proj=''retornado'' order by');
 definition:=replace(definition,'and celula_destino_id=a.celula_destino_id and bloquear_avanco_sem_aprov','and ativo and celula_destino_id=a.celula_destino_id and bloquear_avanco_sem_aprov');
 definition:=replace(definition,'and celula_destino_id=a.celula_origem_id and status=''aprovado''','and ativo and celula_destino_id=a.celula_origem_id and status=''aprovado''');
 definition:=replace(definition,'and celula_origem_id=a.celula_origem_id and coalesce(status,''nulo'')=''nulo''','and ativo and celula_origem_id=a.celula_origem_id and coalesce(status,''nulo'')=''nulo''');
 marker:='  return jsonb_build_object(''aprovacao_etapa_id'',a.id,';
 if strpos(definition,marker)=0 then raise exception 'Unexpected stage result'; end if;
 definition:=replace(definition,marker,$patch$
  insert into rm_private.stage_rule_events(projeto_id,etapa_id,related_etapa_id,actor_id,action,log_id,client_submission_id)
   select a.projeto_id,x,a.id,p_operador_id,'use',log_id,submission_id from(select distinct x from unnest(array_append(affected,a.id)) x) ids;
$patch$||marker);
 execute definition;
 definition:=pg_get_functiondef('rm_private.update_cell_status_v1(uuid,uuid,text)'::regprocedure);
 marker:='where a.projeto_id=cp.projeto_id and a.celula_origem_id=cp.celula_id)';
 if strpos(definition,marker)=0 then raise exception 'Unexpected status visibility predicate'; end if;
 execute replace(definition,marker,'where a.projeto_id=cp.projeto_id and a.celula_origem_id=cp.celula_id and a.ativo)');
 definition:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 marker:='    v_result:=public.rm_transition_stage_approval_v1';
 if strpos(definition,marker)=0 then raise exception 'Unexpected mobile stage dispatch'; end if;
 execute replace(definition,marker,'    perform set_config(''rm.stage_rule_submission_id'',p_client_submission_id::text,true);'||chr(10)||marker);
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
  'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
  'set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules'));
do $$ declare definition text; needle text:='when ''assign_form_reviewer'' then ''em.planning.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected permit map'; end if;
 execute replace(definition,needle,'when ''assign_form_reviewer'' then ''em.planning.manage'' when ''manage_stage_rules'' then ''em.planning.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_form_reviewer_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
