-- A planning designation exists before a form registration; it is not a decision.
-- No existing operational row is rewritten and no historical data is invented.
begin;
alter table public.rm_celulas_projeto add constraint rm_allocation_context_identity unique(projeto_id,celula_id,id);
create table public.rm_form_reviewer_assignments(
 id uuid primary key default gen_random_uuid(),bubble_id text unique,
 projeto_id uuid not null,celula_id uuid not null,celula_projeto_id uuid not null,
 form_id uuid not null references public.rm_forms(id) on update restrict on delete restrict,
 avaliador_user_id uuid not null references public.rm_users(id) on update restrict on delete restrict,
 created_by_id uuid references public.rm_users(id) on delete restrict,
 updated_by_id uuid references public.rm_users(id) on delete restrict,
 legacy_source_ids text[] not null default '{}',
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 bubble_modified_at timestamptz,sync_source text not null default 'supabase' check(sync_source in('supabase','bubble','etl')),
 unique(projeto_id,celula_id,form_id),
 foreign key(projeto_id,celula_id,celula_projeto_id) references public.rm_celulas_projeto(projeto_id,celula_id,id) on update restrict on delete restrict
);
create trigger trg_touch_rm_form_reviewer_assignments before update on public.rm_form_reviewer_assignments
 for each row execute function rm_private.touch_updated_at();
alter table public.rm_form_reviewer_assignments enable row level security;
revoke all on public.rm_form_reviewer_assignments from public,anon,authenticated,service_role;
grant select on public.rm_form_reviewer_assignments to authenticated,service_role;
create policy rm_reviewer_assignment_read on public.rm_form_reviewer_assignments for select to authenticated
 using((select rm_private.is_rm_authenticated()));

create function public.rm_web_form_reviewer_assignments_snapshot_v1(p_project_id uuid,p_allocation_id uuid,p_include_eligible boolean default false)
returns jsonb language sql stable security invoker set search_path='' as $$
 with context as materialized(
  select p.id project_id,p.numero,p.status_pcp,p.data_real_de_entrega,p.updated_at project_updated_at,
   p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false) closed,
   a.id allocation_id,a.celula_id,a.status,a.updated_at allocation_updated_at,a.forms_ids,c.nome celula_nome,c.updated_at cell_updated_at
  from public.rm_projetos p join public.rm_celulas_projeto a on a.projeto_id=p.id join public.rm_celulas c on c.id=a.celula_id
  where p.id=p_project_id and a.id=p_allocation_id
 ), assignments as materialized(
  select a.* from public.rm_form_reviewer_assignments a cross join context c where a.projeto_id=c.project_id and a.celula_id=c.celula_id
 ), records as materialized(
  select r.* from public.rm_registros_formulario r cross join context c where r.projeto_id=c.project_id and r.celula_id=c.celula_id
 ), members as materialized(
  select t.id,t.updated_at,t.identidade_id,u.updated_at user_updated_at,u.status user_status
  from public.rm_tablet_celula_users t cross join context c left join public.rm_users u on u.id=t.identidade_id where t.celula_id=c.celula_id
 ), eligible as materialized(
  select distinct u.id,u.nome,u.matricula from members m join public.rm_users u on u.id=m.identidade_id where u.status='ativo'
 ), definitions as materialized(
  select f.*,f.id=any(c.forms_ids) linked from public.rm_forms f cross join context c where f.id in(
   select unnest(c.forms_ids) union select form_id from assignments union select form_id from records)
 ), counts as materialized(
  select (select count(*) from definitions) total,(select count(*) from records) records_total,(select count(*) from eligible) eligible_total,
   coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at,'identidade_id',identidade_id,
    'user_updated_at',user_updated_at,'user_status',user_status) order by id) from members),'[]'::jsonb) membership_versions
 ), forms as(
  select f.id,f.titulo,jsonb_build_object('id',f.id,'titulo',f.titulo,'linked',f.linked,
   'assignment',case when a.id is null then null else jsonb_build_object('id',a.id,'avaliador_user_id',a.avaliador_user_id,
    'avaliador_nome',u.nome,'updated_at',a.updated_at,'eligible',exists(select 1 from eligible e where e.id=a.avaliador_user_id)) end,
   'records',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'status',r.status,'preenchido',r.preenchido,
    'avaliador_user_id',r.avaliador_user_id,'avaliador_nome',reviewer.nome,'updated_at',r.updated_at) order by r.created_at,r.id)
    from records r left join public.rm_users reviewer on reviewer.id=r.avaliador_user_id where r.form_id=f.id),'[]'::jsonb),
   'can_assign',not c.closed and not coalesce(c.status in('finalizado','n_a'),false) and f.linked
    and n.total<=1000 and n.records_total<=2000 and n.eligible_total<=1000 and not exists(select 1 from records r where r.form_id=f.id and r.status='aprovado'),
   'action_reason',case when c.closed or c.status in('finalizado','n_a') then 'Projeto ou célula encerrados: somente consulta.'
    when not f.linked then 'Formulário não está vinculado à alocação atual: somente consulta.'
    when exists(select 1 from records r where r.form_id=f.id and r.status='aprovado') then 'Há registro aprovado neste formulário: atribuição bloqueada.'
    when n.total>1000 or n.records_total>2000 or n.eligible_total>1000 then 'O conjunto excede o limite de edição completa.'
    when a.id is not null and not exists(select 1 from eligible e where e.id=a.avaliador_user_id) then 'O avaliador designado não está mais ativo e vinculado à célula.' else null end,
   'context_version',encode(sha256(convert_to(jsonb_build_object('project',c.project_id,'project_version',c.project_updated_at,
    'allocation',c.allocation_id,'allocation_version',c.allocation_updated_at,'cell_version',c.cell_updated_at,'form',f.id,'form_version',f.updated_at,
    'assignment',case when a.id is null then null else jsonb_build_object('id',a.id,'updated_at',a.updated_at,'avaliador_user_id',a.avaliador_user_id) end,
    'records',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'updated_at',r.updated_at,'status',r.status,
      'avaliador_user_id',r.avaliador_user_id) order by r.id) from records r where r.form_id=f.id),'[]'::jsonb),
    'members',n.membership_versions)::text,'UTF8')),'hex')) dto
  from definitions f cross join context c cross join counts n left join assignments a on a.form_id=f.id left join public.rm_users u on u.id=a.avaliador_user_id
 )
 select jsonb_build_object('project',jsonb_build_object('id',c.project_id,'numero',c.numero,'status_pcp',c.status_pcp,
   'data_real_de_entrega',c.data_real_de_entrega,'updated_at',c.project_updated_at,'closed',c.closed),
  'allocation',jsonb_build_object('id',c.allocation_id,'projeto_id',c.project_id,'celula_id',c.celula_id,'celula_nome',c.celula_nome,
   'status',c.status,'updated_at',c.allocation_updated_at),
  'forms',case when n.total<=1000 and n.records_total<=2000 then coalesce((select jsonb_agg(dto order by titulo,id) from forms),'[]'::jsonb) else '[]'::jsonb end,
  'eligible_users',case when p_include_eligible and n.eligible_total<=1000 and exists(select 1 from public.rm_users u
    where u.auth_user_id=auth.uid() and u.status='ativo' and u.perfil in('administrador','padr_o'))
    then coalesce((select jsonb_agg(jsonb_build_object('id',id,'nome',nome,'matricula',matricula) order by nome,id) from eligible),'[]'::jsonb) else '[]'::jsonb end,
  'total',n.total,'complete',n.total<=1000,'records_total',n.records_total,'records_complete',n.records_total<=2000,
  'eligible_total',n.eligible_total,'eligible_complete',n.eligible_total<=1000) from context c cross join counts n;
$$;
revoke all on function public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_operational_photos_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 project public.rm_projetos%rowtype; allocation public.rm_celulas_projeto%rowtype; assignment public.rm_form_reviewer_assignments%rowtype;
 registration public.rm_registros_formulario%rowtype; locked_project uuid; snapshot jsonb; form_snapshot jsonb;
 project_id uuid; allocation_id uuid; target_form_id uuid; reviewer_id uuid; expected_project timestamptz; expected_allocation timestamptz;
 changed_ids uuid[]:='{}'; result jsonb; old_record jsonb;
begin
 if p_operation not in('assign_form_reviewer','review_form') or p_operation is null then
  return rm_private.web_mutate_operational_photos_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null then raise exception 'Conta RM ativa necessária.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 if p_operation='review_form' then
  -- Existing receipts retain exact historical semantics; only fresh decisions
  -- join the project's lock order before their original record-level guard.
  if not exists(select 1 from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id) then
   select * into registration from public.rm_registros_formulario where id=(p_payload->>'registro_formulario_id')::uuid;
   if found then
    locked_project:=registration.projeto_id;
    perform pg_advisory_xact_lock(hashtextextended(locked_project::text,11));
    perform 1 from public.rm_projetos where id=locked_project for update;
    select * into registration from public.rm_registros_formulario where id=registration.id for update;
    if registration.projeto_id is distinct from locked_project then raise exception 'Contexto do registro alterado. Recarregue.' using errcode='PT409'; end if;
   end if;
  end if;
  return rm_private.web_mutate_operational_photos_core_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 if not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à administração/planejamento.' using errcode='42501'; end if;
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload ?& array['projeto_id','celula_projeto_id','form_id','avaliador_user_id','expected_project_updated_at','expected_allocation_updated_at','expected_context_version','confirm_replace']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('projeto_id','celula_projeto_id','form_id','avaliador_user_id','expected_project_updated_at','expected_allocation_updated_at','expected_context_version','confirm_replace'))
  or exists(select 1 from unnest(array['projeto_id','celula_projeto_id','form_id','avaliador_user_id','expected_project_updated_at','expected_allocation_updated_at','expected_context_version']) k where jsonb_typeof(p_payload->k) is distinct from 'string')
  or jsonb_typeof(p_payload->'confirm_replace') is distinct from 'boolean'
  or p_payload->>'expected_context_version' !~ '^[0-9a-f]{64}$'
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then raise exception 'Contexto ou versão inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; allocation_id:=(p_payload->>'celula_projeto_id')::uuid;
 target_form_id:=(p_payload->>'form_id')::uuid; reviewer_id:=(p_payload->>'avaliador_user_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 select * into allocation from public.rm_celulas_projeto where id=allocation_id and projeto_id=project_id for update;
 if not found then raise exception 'Célula não pertence ao projeto.' using errcode='P0002'; end if;
 perform 1 from public.rm_celulas where id=allocation.celula_id for share;
 -- User before membership avoids inversion with ON DELETE SET NULL on TCU.
 perform 1 from public.rm_users where id=reviewer_id or id in(select identidade_id from public.rm_tablet_celula_users where celula_id=allocation.celula_id) order by id for share;
 perform 1 from public.rm_tablet_celula_users where celula_id=allocation.celula_id order by id for share;
 perform 1 from public.rm_forms where id=target_form_id for share;
 select * into assignment from public.rm_form_reviewer_assignments a where a.projeto_id=project_id and a.celula_id=allocation.celula_id and a.form_id=target_form_id for update;
 perform 1 from public.rm_registros_formulario where projeto_id=project_id and celula_id=allocation.celula_id order by id for update;
 snapshot:=public.rm_web_form_reviewer_assignments_snapshot_v1(project_id,allocation_id,true);
 if project.updated_at<>expected_project or allocation.updated_at<>expected_allocation then raise exception 'Projeto ou alocação alterados. Recarregue.' using errcode='PT409'; end if;
 if not(snapshot->>'complete')::boolean or not(snapshot->>'records_complete')::boolean or not(snapshot->>'eligible_complete')::boolean then raise exception 'O conjunto excede o limite de edição completa.' using errcode='22023'; end if;
 select x into form_snapshot from jsonb_array_elements(snapshot->'forms') x where x->>'id'=target_form_id::text;
 if form_snapshot is null or not coalesce((form_snapshot->>'linked')::boolean,false) then raise exception 'Formulário não está vinculado à alocação atual.' using errcode='22023'; end if;
 if form_snapshot->>'context_version' is distinct from p_payload->>'expected_context_version' then raise exception 'Atribuição, registros ou elegibilidade alterados. Recarregue.' using errcode='PT409'; end if;
 if not(form_snapshot->>'can_assign')::boolean then raise exception '%',form_snapshot->>'action_reason' using errcode='22023'; end if;
 if not exists(select 1 from public.rm_users u join public.rm_tablet_celula_users t on t.identidade_id=u.id
  where u.id=reviewer_id and u.status='ativo' and t.celula_id=allocation.celula_id) then raise exception 'Avaliador não está ativo e vinculado à célula.' using errcode='22023'; end if;
 if not(p_payload->>'confirm_replace')::boolean and (assignment.id is not null or exists(select 1 from public.rm_registros_formulario r
   where r.projeto_id=project_id and r.celula_id=allocation.celula_id and r.form_id=target_form_id and r.avaliador_user_id is not null and r.avaliador_user_id<>reviewer_id)) then
  raise exception 'Confirme a troca ou reaplicação do avaliador.' using errcode='22023'; end if;
 old_record:=form_snapshot;
 if assignment.id is null then
  insert into public.rm_form_reviewer_assignments(projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id,created_by_id,updated_by_id)
   values(project_id,allocation.celula_id,allocation_id,target_form_id,reviewer_id,actor.id,actor.id) returning * into assignment;
 elsif assignment.avaliador_user_id is distinct from reviewer_id then
  update public.rm_form_reviewer_assignments set avaliador_user_id=reviewer_id,updated_by_id=actor.id,sync_source='supabase' where id=assignment.id returning * into assignment;
 end if;
 with changed as(update public.rm_registros_formulario r set avaliador_user_id=reviewer_id,sync_source='supabase'
  where r.projeto_id=project_id and r.celula_id=allocation.celula_id and r.form_id=target_form_id and r.status<>'aprovado'
   and r.avaliador_user_id is distinct from reviewer_id returning r.id)
 select coalesce(array_agg(id order by id),'{}'::uuid[]) into changed_ids from changed;
 snapshot:=public.rm_web_form_reviewer_assignments_snapshot_v1(project_id,allocation_id,true);
 select x into form_snapshot from jsonb_array_elements(snapshot->'forms') x where x->>'id'=target_form_id::text;
 result:=jsonb_build_object('operation',p_operation,'id',assignment.id,'projeto_id',project_id,'updated_at',assignment.updated_at,
  'record',jsonb_build_object('assignment_id',assignment.id,'projeto_id',project_id,'celula_projeto_id',allocation_id,'celula_id',allocation.celula_id,
   'form_id',target_form_id,'avaliador_user_id',reviewer_id,'context_version',form_snapshot->>'context_version','records_updated_ids',to_jsonb(changed_ids)),
  'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,old_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='assign_form_reviewer' then raise exception 'Identificador ou data inválida.' using errcode='22023'; end if; raise;
end $$;

-- The import boundary is deliberately separate from the user's planning action.
-- It preserves historical metadata, never propagates into registrations, and
-- never updates a prior assignment, even if the source became newer.
create function public.rm_bootstrap_form_reviewer_assignment_v1(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare project public.rm_projetos%rowtype; allocation public.rm_celulas_projeto%rowtype; existing public.rm_form_reviewer_assignments%rowtype;
 ident uuid; project_id uuid; cell_id uuid; allocation_id uuid; target_form_id uuid; reviewer_id uuid; source_id text; sources text[];
 expected_project timestamptz; expected_allocation timestamptz; source_created timestamptz; source_modified timestamptz; state text:='inserted';
begin
 if p_payload is null or jsonb_typeof(p_payload)<>'object' or not p_payload ?& array['id','bubble_id','legacy_source_ids','projeto_id','celula_id','celula_projeto_id','form_id','avaliador_user_id','expected_project_updated_at','expected_allocation_updated_at','created_at','bubble_modified_at']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','bubble_id','legacy_source_ids','projeto_id','celula_id','celula_projeto_id','form_id','avaliador_user_id','expected_project_updated_at','expected_allocation_updated_at','created_at','bubble_modified_at'))
  or exists(select 1 from unnest(array['id','bubble_id','projeto_id','celula_id','celula_projeto_id','form_id','avaliador_user_id','expected_project_updated_at','expected_allocation_updated_at','created_at','bubble_modified_at']) k where jsonb_typeof(p_payload->k) is distinct from 'string')
  or jsonb_typeof(p_payload->'legacy_source_ids') is distinct from 'array' or jsonb_array_length(p_payload->'legacy_source_ids') not between 1 and 100
  or exists(select 1 from jsonb_array_elements(p_payload->'legacy_source_ids') x where jsonb_typeof(x) is distinct from 'string' or nullif(btrim(x#>>'{}'),'') is null or length(x#>>'{}')>200)
  or exists(select 1 from unnest(array['expected_project_updated_at','expected_allocation_updated_at','created_at','bubble_modified_at']) k
   where p_payload->>k !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$') then raise exception 'Importação de atribuição inválida.' using errcode='22023'; end if;
 ident:=(p_payload->>'id')::uuid; project_id:=(p_payload->>'projeto_id')::uuid; cell_id:=(p_payload->>'celula_id')::uuid;
 allocation_id:=(p_payload->>'celula_projeto_id')::uuid; target_form_id:=(p_payload->>'form_id')::uuid; reviewer_id:=(p_payload->>'avaliador_user_id')::uuid;
 source_id:=p_payload->>'bubble_id'; sources:=array(select jsonb_array_elements_text(p_payload->'legacy_source_ids') order by 1);
 if nullif(btrim(source_id),'') is null or length(source_id)>200 or not source_id=any(sources) or cardinality(sources)<>(select count(distinct x) from unnest(sources) x) then raise exception 'Proveniência inválida.' using errcode='22023'; end if;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
 source_created:=(p_payload->>'created_at')::timestamptz; source_modified:=(p_payload->>'bubble_modified_at')::timestamptz;
 if source_created>source_modified then raise exception 'Datas de origem inválidas.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 select * into allocation from public.rm_celulas_projeto where id=allocation_id and projeto_id=project_id and celula_id=cell_id for update;
 if project.id is null or allocation.id is null then raise exception 'Contexto histórico não encontrado.' using errcode='P0002'; end if;
 if project.updated_at<>expected_project or allocation.updated_at<>expected_allocation then raise exception 'Contexto histórico alterado.' using errcode='PT409'; end if;
 perform 1 from public.rm_forms where id=target_form_id for share;
 if not found then raise exception 'Formulário histórico não encontrado.' using errcode='P0002'; end if;
 perform 1 from public.rm_users where id=reviewer_id for share;
 if not found then raise exception 'Identidade histórica não encontrada.' using errcode='P0002'; end if;
 select * into existing from public.rm_form_reviewer_assignments a where a.projeto_id=project_id and a.celula_id=cell_id and a.form_id=target_form_id for update;
 if found then
  if existing.celula_projeto_id<>allocation_id or existing.avaliador_user_id<>reviewer_id or existing.bubble_id is distinct from source_id
   or existing.legacy_source_ids is distinct from sources or existing.created_at<>source_created or existing.bubble_modified_at is distinct from source_modified
   or existing.sync_source<>'bubble' then raise exception 'Atribuição histórica conflita com o destino; nenhuma alteração aplicada.' using errcode='PT409'; end if;
  ident:=existing.id; state:='existing';
 else
  insert into public.rm_form_reviewer_assignments(id,bubble_id,projeto_id,celula_id,celula_projeto_id,form_id,avaliador_user_id,legacy_source_ids,created_at,bubble_modified_at,sync_source)
   values(ident,source_id,project_id,cell_id,allocation_id,target_form_id,reviewer_id,sources,source_created,source_modified,'bubble');
 end if;
 return jsonb_build_object('status',state,'id',ident,'projeto_id',project_id,'celula_projeto_id',allocation_id,'form_id',target_form_id);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'Identificador ou data histórica inválida.' using errcode='22023';
end $$;
revoke all on function public.rm_bootstrap_form_reviewer_assignment_v1(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_bootstrap_form_reviewer_assignment_v1(jsonb) to service_role;

-- Existing mobile receipts are checked by the envelope before these primitives.
-- Project before record/sequence lets assignment, decision and creation agree.
do $$ declare definition text; marker text; begin
 definition:=pg_get_functiondef('public.rm_submit_form_inspection_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb)'::regprocedure);
 marker:='  select * into v_projeto from public.rm_projetos where id = p_projeto_id;';
 if strpos(definition,marker)=0 then raise exception 'Unexpected inspection primitive'; end if;
 definition:=replace(definition,marker,$patch$
  perform pg_advisory_xact_lock(hashtextextended(p_projeto_id::text,11));
  select * into v_projeto from public.rm_projetos where id = p_projeto_id for update;
$patch$);
 marker:='  -- 4. Grava todas as Respostas em lote (substitui novo_form_recursivo cofnw)';
 if strpos(definition,marker)=0 then raise exception 'Unexpected inspection insertion'; end if;
 definition:=replace(definition,marker,$patch$
  -- User/membership locks prevent an in-flight revocation from becoming a grant.
  perform 1 from public.rm_users u join public.rm_form_reviewer_assignments a on a.avaliador_user_id=u.id
    where a.projeto_id=p_projeto_id and a.celula_id=p_celula_id and a.form_id=p_form_id for share of u;
  perform 1 from public.rm_tablet_celula_users t join public.rm_form_reviewer_assignments a on a.avaliador_user_id=t.identidade_id
    where a.projeto_id=p_projeto_id and a.celula_id=p_celula_id and a.form_id=p_form_id and t.celula_id=p_celula_id order by t.id for share of t;
  update public.rm_registros_formulario r set avaliador_user_id=a.avaliador_user_id
    from public.rm_form_reviewer_assignments a join public.rm_users u on u.id=a.avaliador_user_id and u.status='ativo'
    where r.id=v_registro_id and a.projeto_id=p_projeto_id and a.celula_id=p_celula_id and a.form_id=p_form_id
      and exists(select 1 from public.rm_tablet_celula_users t where t.identidade_id=a.avaliador_user_id and t.celula_id=p_celula_id);
$patch$||marker);
 execute definition;
 definition:=pg_get_functiondef('public.rm_submit_form_revision_v1(uuid,uuid,jsonb)'::regprocedure);
 marker:='  select * into r from public.rm_registros_formulario where id=p_registro_formulario_id for update;';
 if strpos(definition,marker)=0 then raise exception 'Unexpected revision primitive'; end if;
 definition:=replace(definition,'v_pending integer;','v_pending integer; v_locked_project_id uuid;');
 definition:=replace(definition,marker,$patch$
  select projeto_id into v_locked_project_id from public.rm_registros_formulario where id=p_registro_formulario_id;
  if not found then raise exception 'Registro não encontrado.' using errcode='P0002'; end if;
  if v_locked_project_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_locked_project_id::text,11));
    perform 1 from public.rm_projetos where id=v_locked_project_id for update;
  end if;
$patch$||marker||$patch$
  if r.projeto_id is distinct from v_locked_project_id then raise exception 'Contexto do registro alterado. Recarregue.' using errcode='PT409'; end if;
$patch$);
 execute definition;
 execute pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
  'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
  'set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer'));
do $$ declare definition text; needle text:='when ''manage_operational_photos'' then ''em.planning.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
 execute replace(definition,needle,'when ''manage_operational_photos'' then ''em.planning.manage'' when ''assign_form_reviewer'' then ''em.planning.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_operational_photos_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
