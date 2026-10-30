-- Cell availability keeps IDs, positions and all existing work. No old business
-- value is rewritten by installation; retirada=false is an additive projection.
begin;
alter table public.rm_celulas_projeto add column retirada boolean not null default false;
alter table public.rm_celulas_projeto add constraint rm_retired_allocation_hidden check(not retirada or not visibilidade);
create table rm_private.cell_availability_events(
 id uuid primary key default gen_random_uuid(),projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 celula_projeto_id uuid not null references public.rm_celulas_projeto(id) on delete restrict,
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 action text not null check(action in('set_visibility','retire','restore')),
 old_visibility boolean not null,new_visibility boolean not null,old_retired boolean not null,new_retired boolean not null,
 allocation_version timestamptz not null,client_submission_id uuid not null unique,
 transaction_id bigint not null default txid_current(),created_at timestamptz not null default clock_timestamp()
);
create index rm_cell_availability_events_context on rm_private.cell_availability_events(celula_projeto_id,created_at,id);
revoke all on rm_private.cell_availability_events from public,anon,authenticated,service_role;

-- Technical fixtures can insert an exact owner-only event in the same local
-- transaction; the product exposes no lifecycle bypass or arbitrary journal RPC.
create function rm_private.guard_cell_availability_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'A alocação preserva seu ID. Use a retirada protegida.' using errcode='22023'; end if;
 if row(old.id,old.projeto_id,old.celula_id) is distinct from row(new.id,new.projeto_id,new.celula_id) then
  raise exception 'Projeto e célula da alocação são imutáveis por ID.' using errcode='22023'; end if;
 if old.retirada is distinct from new.retirada and not exists(select 1 from rm_private.cell_availability_events e
  where e.celula_projeto_id=old.id and e.projeto_id=old.projeto_id and e.transaction_id=txid_current()
   and e.allocation_version=old.updated_at and e.old_retired=old.retirada and e.new_retired=new.retirada
   and e.old_visibility=old.visibilidade and e.new_visibility=new.visibilidade and
    ((e.action='retire' and new.retirada and not new.visibilidade) or (e.action='restore' and not new.retirada and not new.visibilidade))) then
  raise exception 'Retirar ou restaurar exige o comando de disponibilidade autorizado.' using errcode='42501'; end if;
 if old.retirada and new.retirada and (new.visibilidade or
  to_jsonb(new)-array['numero_projeto','cliente_nome_export','tipo_equipamento_nome_export','escopo_abreviado','updated_at','bubble_id','bubble_modified_at','sync_source']
   is distinct from to_jsonb(old)-array['numero_projeto','cliente_nome_export','tipo_equipamento_nome_export','escopo_abreviado','updated_at','bubble_id','bubble_modified_at','sync_source']) then
  raise exception 'Alocação retirada. Restaure o mesmo item para retomar o trabalho; sua tentativa foi preservada.' using errcode='PT409'; end if;
 return new;
end $$;

revoke all on function rm_private.guard_cell_availability_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_cell_availability before update or delete on public.rm_celulas_projeto
 for each row execute function rm_private.guard_cell_availability_v1();

-- Used before mutable children; callers already follow project11 ordering. The
-- NOWAIT parent order also makes uncoordinated technical row writes retry rather
-- than deadlock while a retirement/decision holds the parent resource.
create function rm_private.assert_allocation_available_v1(p_project_id uuid,p_cell_id uuid,p_allocation_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare a public.rm_celulas_projeto%rowtype;
begin
 if p_project_id is null and p_allocation_id is not null then
  select projeto_id into p_project_id from public.rm_celulas_projeto where id=p_allocation_id;
 end if;
 if p_project_id is null then return; end if;
 perform 1 from public.rm_projetos where id=p_project_id for key share nowait;
 if p_allocation_id is not null then
  select * into a from public.rm_celulas_projeto where id=p_allocation_id for key share nowait;
  if found and (a.projeto_id is distinct from p_project_id or (p_cell_id is not null and a.celula_id is distinct from p_cell_id)) then
   raise exception 'Alocação não corresponde ao contexto informado.' using errcode='22023'; end if;
 else
  select * into a from public.rm_celulas_projeto where projeto_id=p_project_id and celula_id=p_cell_id for key share nowait;
 end if;
 if a.id is not null and a.retirada then raise exception 'Alocação retirada. Solicite ao gestor restaurar o mesmo item e tente novamente; o envio offline foi preservado.' using errcode='PT409'; end if;
exception when lock_not_available then raise exception 'A alocação está sendo alterada. Tente novamente com o mesmo protocolo.' using errcode='PT409';
end $$;
revoke all on function rm_private.assert_allocation_available_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

-- Remaining definitions are installed below in this same atomic migration.
create function rm_private.cell_availability_metadata_v1(p_allocation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a public.rm_celulas_projeto%rowtype; result jsonb;
begin
 if not rm_private.is_rm_authenticated() then return null; end if;
 select * into a from public.rm_celulas_projeto where id=p_allocation_id;
 if not found then return null; end if;
 with records as materialized(select * from public.rm_registros_formulario r where r.projeto_id=a.projeto_id and r.celula_id=a.celula_id),
 drafts as materialized(select * from public.rm_respostas_temp d where (d.projeto_id=a.projeto_id and d.form_id=any(a.forms_ids))
  or d.registro_formulario_id in(select id from records)),
 photos as materialized(select * from public.rm_fotos f where f.celula_projeto_id=a.id or (f.projeto_id=a.projeto_id and f.celula_id=a.celula_id)),
 stages as materialized(select * from public.rm_aprovacoes_etapas s where s.celula_projeto_id=a.id or
  (s.projeto_id=a.projeto_id and (s.celula_origem_id=a.celula_id or s.celula_destino_id=a.celula_id))),
 comments as materialized(select * from public.rm_comentarios c where c.projeto_id=a.projeto_id and c.celula_id=a.celula_id),
 logs as materialized(select * from public.rm_logs_aprovacao l where l.projeto_id=a.projeto_id and l.celula_id=a.celula_id),
 stage_proof as materialized(select rm_private.stage_rule_metadata_v1(a.projeto_id) data),
 mobile as materialized(select m.client_submission_id,m.created_at from rm_private.mobile_mutation_receipts m
  where m.rpc_name in('rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_record_cell_photo_v1','rm_update_cell_status_v1','rm_add_cell_comment_v1','rm_transition_stage_approval_v1') and (
   lower(m.params->>'p_celula_projeto_id')=a.id::text or m.result->>'celula_projeto_id'=a.id::text
   or (lower(m.params->>'p_projeto_id')=a.projeto_id::text and lower(m.params->>'p_celula_id')=a.celula_id::text)
   or (m.result->>'projeto_id'=a.projeto_id::text and m.result->>'celula_id'=a.celula_id::text)
   or lower(m.params->>'p_registro_formulario_id') in(select id::text from records) or m.result->>'registro_formulario_id' in(select id::text from records)
   or lower(m.params->>'p_foto_id') in(select id::text from photos) or m.result->>'foto_id' in(select id::text from photos)
   or lower(m.params->>'p_aprovacao_etapa_id') in(select id::text from stages) or m.result->>'aprovacao_etapa_id' in(select id::text from stages)
   or (m.rpc_name='rm_transition_stage_approval_v1' and m.result->>'projeto_id'=a.projeto_id::text and m.created_at>=a.created_at
    and not exists(select 1 from public.rm_aprovacoes_etapas s where s.id::text=lower(m.params->>'p_aprovacao_etapa_id'))))),
 web as materialized(select w.client_submission_id,w.created_at from rm_private.web_mutation_receipts w where
  (w.operation='review_form' and (lower(w.payload->>'registro_formulario_id') in(select id::text from records)
   or(w.result->>'projeto_id'=a.projeto_id::text and w.result->'record'->>'celula_id'=a.celula_id::text)))
  or(w.operation='transition_stage_approval' and (lower(w.payload->>'aprovacao_etapa_id') in(select id::text from stages)
   or(w.result->>'projeto_id'=a.projeto_id::text and (w.result->'snapshot'->'stage'->>'celula_origem_id'=a.celula_id::text
    or w.result->'snapshot'->'stage'->>'celula_destino_id'=a.celula_id::text))))),
 jobs as materialized(select o.id,o.created_at,o.status from public.rm_sync_outbox o
  where o.entity_type in('Celula_Projeto_Status','Comentario_Celula','Registro_Formulario_Bundle','Registro_Formulario_Revision','Aprovacao_Etapa_Transition','Fotos_RM_Sync') and (
   o.record_id=a.id or o.record_id in(select id from records) or o.record_id in(select id from stages) or o.record_id in(select id from photos)
   or o.payload->>'foto_id' in(select id::text from photos)
   or o.payload->>'celula_projeto_id'=a.id::text or(o.payload->>'projeto_id'=a.projeto_id::text and o.payload->>'celula_id'=a.celula_id::text)
   or(o.payload->>'projeto_id'=a.projeto_id::text and o.entity_type like 'Registro_Formulario%' and o.payload->>'form_id'=any(array(select x::text from unnest(a.forms_ids) x)))
   or(o.entity_type='Aprovacao_Etapa_Transition' and o.payload->>'projeto_id'=a.projeto_id::text and o.created_at>=a.created_at
    and not exists(select 1 from public.rm_aprovacoes_etapas s where s.id=o.record_id)))),
 evidence as(select case
  when a.status<>'pendente' then 'Somente alocações pendentes e sem uso podem ser retiradas.'
  when exists(select 1 from unnest(a.status_historico) s where s is distinct from 'pendente'::public.rm_status_cel_proj_enum)
    or coalesce(a.horas_realizadas,0)<>0 or a.data_fim_real is not null then 'Há evidência de execução ou encerramento nesta alocação.'
  when exists(select 1 from records) then 'Há registros de formulário vinculados a esta célula do projeto.'
  when exists(select 1 from drafts) then 'Há rascunhos de servidor compatíveis com os formulários desta alocação.'
  when exists(select 1 from photos f where (f.celula_projeto_id is not null and f.celula_projeto_id<>a.id)
   or f.projeto_id is distinct from a.projeto_id or f.celula_id is distinct from a.celula_id) then 'Há vínculos de foto incompatíveis que precisam de reconciliação.'
  when exists(select 1 from photos f where nullif(btrim(f.foto_url),'') is not null or f.selecao_relatorio
   or exists(select 1 from unnest(f.fotos_arquivos_urls) u where nullif(btrim(u),'') is not null)) then 'Há fotos registradas ou selecionadas, incluindo histórico preservado.'
  when exists(select 1 from comments) or exists(select 1 from logs) then 'Há comentários ou histórico operacional desta célula.'
  when exists(select 1 from stages s where s.celula_projeto_id=a.id and (s.projeto_id is distinct from a.projeto_id or s.celula_origem_id<>a.celula_id)) then 'Há vínculos de etapa incompatíveis que precisam de reconciliação.'
  when exists(select 1 from stages s where s.ativo) then 'Há etapas ativas entrando ou saindo desta célula. Revise as regras antes de retirar.'
  when exists(select 1 from stage_proof p cross join jsonb_array_elements(coalesce(p.data->'items','[]'::jsonb)) m
   where m->>'id' in(select id::text from stages) and ((m->>'used')::boolean or (m->>'history_ambiguous')::boolean)) then 'Há uso ou histórico ambíguo de etapas relacionadas à alocação.'
  when exists(select 1 from stages) and (select count(*) from public.rm_aprovacoes_etapas s where s.projeto_id=a.projeto_id)>1000 then 'O histórico de etapas excede o limite de conferência completa.'
  when exists(select 1 from mobile) or exists(select 1 from web) or exists(select 1 from jobs) then 'Há recibos ou eventos de uso operacional relacionados a esta alocação.'
  else null end reason)
 select jsonb_build_object('retire_reason',e.reason,'fingerprint',encode(sha256(convert_to(jsonb_build_object(
  'records',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from records),'[]'::jsonb),
  'drafts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from drafts),'[]'::jsonb),
  'photos',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from photos),'[]'::jsonb),
  'stages',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from stages),'[]'::jsonb),
  'comments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from comments),'[]'::jsonb),
  'logs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'updated_at',updated_at) order by id) from logs),'[]'::jsonb),
  'mobile',coalesce((select jsonb_agg(jsonb_build_object('id',client_submission_id,'at',created_at) order by client_submission_id) from mobile),'[]'::jsonb),
  'web',coalesce((select jsonb_agg(jsonb_build_object('id',client_submission_id,'at',created_at) order by client_submission_id) from web),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(jsonb_build_object('id',id,'at',created_at,'status',status) order by id) from jobs),'[]'::jsonb),
  'reviewer_designations',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'updated_at',r.updated_at) order by r.id) from public.rm_form_reviewer_assignments r where r.projeto_id=a.projeto_id and r.celula_id=a.celula_id),'[]'::jsonb),
  'availability_events',coalesce((select jsonb_agg(jsonb_build_object('id',id,'at',created_at) order by id) from rm_private.cell_availability_events where celula_projeto_id=a.id),'[]'::jsonb),
  'stage_proof',(select data->>'version' from stage_proof),'reason',e.reason)::text,'UTF8')),'hex')) into result from evidence e;
 return result;
end $$;
revoke all on function rm_private.cell_availability_metadata_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function rm_private.cell_availability_metadata_v1(uuid) to authenticated;

create function public.rm_web_cell_availability_snapshot_v1(p_project_id uuid,p_allocation_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 with context as materialized(select a.*,c.nome celula_nome,c.updated_at cell_updated_at,p.numero,p.status_pcp,p.data_real_de_entrega,p.updated_at project_updated_at,
  p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false) closed
  from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id
  where a.id=p_allocation_id and a.projeto_id=p_project_id),
 evidence as materialized(select rm_private.cell_availability_metadata_v1(p_allocation_id) v)
 select jsonb_build_object('project',jsonb_build_object('id',a.projeto_id,'numero',a.numero,'status_pcp',a.status_pcp,'data_real_de_entrega',a.data_real_de_entrega,'updated_at',a.project_updated_at,'closed',a.closed),
  'allocation',jsonb_build_object('id',a.id,'projeto_id',a.projeto_id,'celula_id',a.celula_id,'celula_nome',a.celula_nome,'status',a.status,
   'visibilidade',a.visibilidade,'retirada',a.retirada,'indice',a.indice,'posicao',a.posicao,'prioridade',a.prioridade,'updated_at',a.updated_at),
  'can_set_visibility',not a.closed and not a.retirada and a.status<>'n_a',
  'can_retire',not a.closed and not a.retirada and e.v is not null and e.v->>'retire_reason' is null,
  'can_restore',not a.closed and a.retirada,
  'visibility_reason',case when a.closed then 'Projeto encerrado: somente consulta.' when a.retirada then 'Alocação retirada. Restaure o mesmo item antes de exibir.' when a.status='n_a' then 'Célula N/A: disponibilidade preservada para consulta.' else null end,
  'retire_reason',case when a.closed then 'Projeto encerrado: somente consulta.' when a.retirada then 'A alocação já está retirada.' else e.v->>'retire_reason' end,
  'restore_reason',case when a.closed then 'Projeto encerrado: somente consulta.' when not a.retirada then 'A alocação já está ativa.' else null end,
  'in_queue',not a.closed and not a.retirada and a.status not in('finalizado','n_a'),
  'context_version',encode(sha256(convert_to(jsonb_build_object('project',a.projeto_id,'project_version',a.project_updated_at,'allocation',a.id,'allocation_version',a.updated_at,
   'cell_version',a.cell_updated_at,'evidence',e.v->>'fingerprint')::text,'UTF8')),'hex'))
 from context a cross join evidence e;
$$;
revoke all on function public.rm_web_cell_availability_snapshot_v1(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_cell_availability_snapshot_v1(uuid,uuid) to authenticated;

-- Operational children take short parent locks before they can create work.
-- NOWAIT makes an uncoordinated importer retry instead of inverting the project
-- and child-row order of the supported mobile/web transactions.
create function rm_private.guard_allocation_child_v1() returns trigger
language plpgsql security definer set search_path='' as $$
declare item jsonb; r public.rm_registros_formulario%rowtype; project_id uuid; cell_id uuid; allocation_id uuid; a record;
begin
 for item in select x from jsonb_array_elements(case when tg_op='UPDATE' then jsonb_build_array(to_jsonb(old),to_jsonb(new))
  when tg_op='DELETE' then jsonb_build_array(to_jsonb(old)) else jsonb_build_array(to_jsonb(new)) end) x loop
  project_id:=null; cell_id:=null; allocation_id:=null;
  if tg_table_name='rm_respostas' then
   select * into r from public.rm_registros_formulario where id=(item->>'registro_formulario_id')::uuid;
   project_id:=r.projeto_id; cell_id:=r.celula_id;
  elsif tg_table_name='rm_respostas_temp' then
   select * into r from public.rm_registros_formulario where id=(item->>'registro_formulario_id')::uuid;
   if found then project_id:=r.projeto_id; cell_id:=r.celula_id;
   elsif tg_op<>'DELETE' and item->>'projeto_id' is not null and item->>'form_id' is not null and not exists(
     select 1 from public.rm_celulas_projeto c where c.projeto_id=(item->>'projeto_id')::uuid
      and (item->>'form_id')::uuid=any(c.forms_ids) and not c.retirada) then
    -- A draft without a cell cannot be assigned to a retired context by guess.
    -- A shared form still usable in another active cell remains usable there.
    for a in select c.* from public.rm_celulas_projeto c where c.projeto_id=(item->>'projeto_id')::uuid
      and (item->>'form_id')::uuid=any(c.forms_ids) order by c.id loop
     perform rm_private.assert_allocation_available_v1(a.projeto_id,a.celula_id,a.id);
    end loop;
   end if;
  else
   project_id:=(item->>'projeto_id')::uuid; cell_id:=(item->>'celula_id')::uuid;
   allocation_id:=(item->>'celula_projeto_id')::uuid;
   if tg_table_name='rm_aprovacoes_etapas' then
    cell_id:=(item->>'celula_origem_id')::uuid;
    perform rm_private.assert_allocation_available_v1(project_id,(item->>'celula_destino_id')::uuid,null);
   end if;
  end if;
  perform rm_private.assert_allocation_available_v1(project_id,cell_id,allocation_id);
 end loop;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
revoke all on function rm_private.guard_allocation_child_v1() from public,anon,authenticated,service_role;
do $$ declare table_name text; begin
 foreach table_name in array array['rm_registros_formulario','rm_respostas','rm_respostas_temp','rm_fotos',
  'rm_aprovacoes_etapas','rm_comentarios','rm_logs_aprovacao','rm_form_reviewer_assignments'] loop
  execute format('create trigger rm_guard_allocation_child before insert or update or delete on public.%I for each row execute function rm_private.guard_allocation_child_v1()',table_name);
 end loop;
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_stage_rules_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype; project public.rm_projetos%rowtype;
 allocation public.rm_celulas_projeto%rowtype; action text; project_id uuid; allocation_id uuid; expected_project timestamptz;
 expected_allocation timestamptz; allowed text[]; before_record jsonb; snapshot jsonb; result jsonb; desired_visibility boolean;
 desired_retired boolean; changed uuid[]:='{}';
begin
 if p_operation is distinct from 'manage_cell_availability' then
  return rm_private.web_mutate_stage_rules_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then
  raise exception 'Operação restrita à administração/planejamento.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 action:=p_payload->>'action';
 allowed:=array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','expected_context_version','confirm_change'];
 if action='set_visibility' then allowed:=allowed||array['visibilidade'];
 elsif action is null or action not in('retire','restore') then raise exception 'Ação de disponibilidade inválida.' using errcode='22023'; end if;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or exists(select 1 from unnest(array['action','projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','expected_context_version']) k where jsonb_typeof(p_payload->k) is distinct from 'string')
  or p_payload->'confirm_change' is distinct from 'true'::jsonb
  or p_payload->>'expected_context_version' !~ '^[0-9a-f]{64}$'
  or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or (action='set_visibility' and jsonb_typeof(p_payload->'visibilidade') is distinct from 'boolean') then
  raise exception 'Confirmação, contexto ou versão inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; allocation_id:=(p_payload->>'celula_projeto_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto não encontrado.' using errcode='P0002'; end if;
 select * into allocation from public.rm_celulas_projeto where id=allocation_id and projeto_id=project_id for update;
 if not found then raise exception 'Alocação não pertence ao projeto.' using errcode='P0002'; end if;
 perform 1 from public.rm_celulas where id=allocation.celula_id for share;
 snapshot:=public.rm_web_cell_availability_snapshot_v1(project_id,allocation_id);
 if project.updated_at<>expected_project or allocation.updated_at<>expected_allocation
  or snapshot->>'context_version' is distinct from p_payload->>'expected_context_version' then
  raise exception 'Projeto, alocação ou evidências alteradas. Recarregue antes de confirmar.' using errcode='PT409'; end if;
 if (snapshot->'project'->>'closed')::boolean then raise exception 'Projeto encerrado: somente consulta.' using errcode='22023'; end if;
 desired_visibility:=allocation.visibilidade; desired_retired:=allocation.retirada; before_record:=snapshot;
 if action='set_visibility' then
  if not(snapshot->>'can_set_visibility')::boolean then raise exception '%',snapshot->>'visibility_reason' using errcode='PT409'; end if;
  desired_visibility:=(p_payload->>'visibilidade')::boolean;
 elsif action='retire' and not allocation.retirada then
  if not(snapshot->>'can_retire')::boolean then raise exception '%',snapshot->>'retire_reason' using errcode='PT409'; end if;
  desired_retired:=true; desired_visibility:=false;
 elsif action='restore' then
  if not allocation.retirada and allocation.visibilidade then raise exception 'A alocação já está ativa. Use o comando de visibilidade.' using errcode='22023'; end if;
  desired_retired:=false; desired_visibility:=false;
 end if;
 if row(desired_visibility,desired_retired) is distinct from row(allocation.visibilidade,allocation.retirada) then
  insert into rm_private.cell_availability_events(projeto_id,celula_projeto_id,actor_id,action,old_visibility,new_visibility,old_retired,new_retired,allocation_version,client_submission_id)
   values(project_id,allocation_id,actor.id,action,allocation.visibilidade,desired_visibility,allocation.retirada,desired_retired,allocation.updated_at,p_client_submission_id);
  update public.rm_celulas_projeto set visibilidade=desired_visibility,retirada=desired_retired,modified_by_id=actor.id,sync_source='supabase'
   where id=allocation_id returning * into allocation;
  changed:=array[allocation_id];
 end if;
 snapshot:=public.rm_web_cell_availability_snapshot_v1(project_id,allocation_id);
 result:=jsonb_build_object('operation',p_operation,'id',allocation_id,'projeto_id',project_id,'updated_at',allocation.updated_at,
  'record',jsonb_build_object('projeto_id',project_id,'celula_projeto_id',allocation_id,'action',action,
   'visibilidade',allocation.visibilidade,'retirada',allocation.retirada,'context_version',snapshot->>'context_version','changed_ids',to_jsonb(changed)), 'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation='manage_cell_availability' then raise exception 'Identificador, data ou estado inválidos.' using errcode='22023'; end if; raise;
end $$;

-- Existing allocation editors continue showing history, with no mutation flags
-- for retired contexts. Do not redact the row from incremental mobile pulls.
do $$ declare definition text; marker text; begin
 definition:=pg_get_functiondef('public.rm_web_operational_photos_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'a.id allocation_id,a.celula_id,a.status,','a.id allocation_id,a.celula_id,a.status,a.retirada,');
 definition:=replace(definition,'not c.closed and','not c.closed and not c.retirada and');
 definition:=replace(definition,'''action_reason'',case when c.closed','''action_reason'',case when c.retirada then ''Alocação retirada: somente consulta.'' when c.closed');
 execute definition;
 definition:=pg_get_functiondef('public.rm_web_form_reviewer_assignments_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'a.id allocation_id,a.celula_id,a.status,','a.id allocation_id,a.celula_id,a.status,a.retirada,');
 definition:=replace(definition,'not c.closed and','not c.closed and not c.retirada and');
 definition:=replace(definition,'''action_reason'',case when c.closed','''action_reason'',case when c.retirada then ''Alocação retirada: somente consulta.'' when c.closed');
 execute definition;
 definition:=pg_get_functiondef('public.rm_web_stage_rules_snapshot_v1(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'a.id allocation_id,a.celula_id,a.status,','a.id allocation_id,a.celula_id,a.status,a.retirada,');
 definition:=replace(definition,'m.x,c.closed or','m.x,c.closed or c.retirada or');
 definition:=replace(definition,'and not coalesce(a.status in(''finalizado'',''n_a''),false)','and not a.retirada and not coalesce(a.status in(''finalizado'',''n_a''),false)');
 definition:=replace(definition,'''action_reason'',case when c.closed','''action_reason'',case when c.retirada then ''Alocação retirada: somente consulta.'' when c.closed');
 definition:=replace(definition,'''reason'',case when a.celula_id=c.celula_id','''reason'',case when a.retirada then ''Alocação de destino retirada.'' when a.celula_id=c.celula_id');
 execute definition;
 definition:=pg_get_functiondef('rm_private.web_mutate_operational_photos_core_v1(uuid,text,jsonb)'::regprocedure);
 marker:=' snapshot:=public.rm_web_operational_photos_snapshot_v1(project_id,allocation_id,true);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected operational photo editor'; end if;
 execute replace(definition,marker,' perform rm_private.assert_allocation_available_v1(project_id,allocation.celula_id,allocation_id);'||chr(10)||marker);
 definition:=pg_get_functiondef('rm_private.web_mutate_form_reviewer_core_v1(uuid,text,jsonb)'::regprocedure);
 marker:=' snapshot:=public.rm_web_form_reviewer_assignments_snapshot_v1(project_id,allocation_id,true);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected reviewer assignment editor'; end if;
 execute replace(definition,marker,' perform rm_private.assert_allocation_available_v1(project_id,allocation.celula_id,allocation_id);'||chr(10)||marker);
 definition:=pg_get_functiondef('rm_private.web_mutate_stage_rules_core_v1(uuid,text,jsonb)'::regprocedure);
 marker:=' snapshot:=public.rm_web_stage_rules_snapshot_v1(project_id,allocation_id,true);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected stage rule editor'; end if;
 execute replace(definition,marker,' perform rm_private.assert_allocation_available_v1(project_id,allocation.celula_id,allocation_id);'||chr(10)||marker);
end $$;

create or replace view rm_private.web_stage_effective_context_v1 with(security_invoker=true) as
 select v.id,v.projeto_id,v.celula_id,v.status,v.created_at,
  v.context||jsonb_build_object('stage',(v.context->'stage')||jsonb_build_object('ativo',a.ativo),
   'available_actions',case when a.ativo and not coalesce(origin.retirada,false) and not coalesce(destination.retirada,false) then v.context->'available_actions' else '[]'::jsonb end,
   'action_reason',case when coalesce(origin.retirada,false) or coalesce(destination.retirada,false) then to_jsonb('Alocação retirada: decisão indisponível até restauração do mesmo item.'::text)
    when a.ativo then v.context->'action_reason' else to_jsonb('Regra retirada do planejamento: somente consulta.'::text) end) context,
  a.ativo from rm_private.web_stage_approval_context_v1 v join public.rm_aprovacoes_etapas a on a.id=v.id
  left join public.rm_celulas_projeto origin on origin.projeto_id=a.projeto_id and origin.celula_id=a.celula_origem_id
  left join public.rm_celulas_projeto destination on destination.projeto_id=a.projeto_id and destination.celula_id=a.celula_destino_id;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
  'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
  'set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules','manage_cell_availability'));
do $$ declare definition text; needle text:='when ''manage_stage_rules'' then ''em.planning.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected availability permit map'; end if;
 execute replace(definition,needle,'when ''manage_stage_rules'' then ''em.planning.manage'' when ''manage_cell_availability'' then ''em.planning.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 execute pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_stage_rules_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Patch shared primitives, not the authentication/receipt envelope. Completed
-- mobile receipts are resolved before these guards, including old protocols.
do $$ declare definition text; marker text; begin
 definition:=pg_get_functiondef('public.rm_submit_form_inspection_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,jsonb)'::regprocedure);
 marker:='  v_codigo := rm_private.next_form_sequence_v1(p_form_id);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected inspection sequence'; end if;
 execute replace(definition,marker,'  perform rm_private.assert_allocation_available_v1(p_projeto_id,p_celula_id,null);'||chr(10)||marker);
 definition:=pg_get_functiondef('public.rm_submit_form_revision_v1(uuid,uuid,jsonb)'::regprocedure);
 marker:='  select * into r from public.rm_registros_formulario where id=p_registro_formulario_id for update;';
 if strpos(definition,marker)=0 then raise exception 'Unexpected revision row lock'; end if;
 execute replace(definition,marker,marker||chr(10)||'  perform rm_private.assert_allocation_available_v1(r.projeto_id,r.celula_id,null);');
 definition:=pg_get_functiondef('public.rm_record_cell_photo_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,public.rm_categoria_foto_enum)'::regprocedure);
 marker:='  if p_foto_id is not null then';
 if strpos(definition,marker)=0 then raise exception 'Unexpected photo branch'; end if;
 definition:=replace(definition,marker,$patch$
  if p_foto_id is null then
   perform pg_advisory_xact_lock(hashtextextended(p_projeto_id::text,11));
   perform 1 from public.rm_projetos where id=p_projeto_id for update;
   perform rm_private.assert_allocation_available_v1(p_projeto_id,p_celula_id,p_celula_projeto_id);
  end if;
$patch$||marker);
 marker:='    if v_foto.lixeira then';
 if strpos(definition,marker)=0 then raise exception 'Unexpected photo slot guard'; end if;
 execute replace(definition,marker,'    perform rm_private.assert_allocation_available_v1(v_foto.projeto_id,v_foto.celula_id,v_foto.celula_projeto_id);'||chr(10)||marker);
 definition:=pg_get_functiondef('rm_private.update_cell_status_v1(uuid,uuid,text)'::regprocedure);
 marker:='  select * into cp from public.rm_celulas_projeto where id=p_cell_project for update;';
 if strpos(definition,marker)=0 then raise exception 'Unexpected cell status lock'; end if;
 execute replace(definition,marker,'  perform 1 from public.rm_projetos where id=cp.projeto_id for update;'||chr(10)||marker||chr(10)||'  perform rm_private.assert_allocation_available_v1(cp.projeto_id,cp.celula_id,cp.id);');
 definition:=pg_get_functiondef('rm_private.add_cell_comment_v1(uuid,uuid,text)'::regprocedure);
 marker:='  perform rm_private.assert_cell_access(p_operator,cp.celula_id);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected comment context'; end if;
 definition:=replace(definition,'comment_id uuid;','comment_id uuid; locked_project uuid;');
 execute replace(definition,marker,$patch$
  locked_project:=cp.projeto_id;
  perform pg_advisory_xact_lock(hashtextextended(locked_project::text,11));
  perform 1 from public.rm_projetos where id=locked_project for update;
  select * into cp from public.rm_celulas_projeto where id=p_cell_project for update;
  if not found or cp.projeto_id is distinct from locked_project then raise exception 'Contexto da célula alterado. Sincronize novamente.' using errcode='PT409'; end if;
  perform rm_private.assert_allocation_available_v1(cp.projeto_id,cp.celula_id,cp.id);
$patch$||marker);
 definition:=pg_get_functiondef('public.rm_transition_stage_approval_v1(uuid,uuid,text,text)'::regprocedure);
 marker:='  perform rm_private.assert_cell_access(p_operador_id,cp.celula_id);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected stage context'; end if;
 execute replace(definition,marker,$patch$
  perform rm_private.assert_allocation_available_v1(a.projeto_id,a.celula_origem_id,a.celula_projeto_id);
  perform rm_private.assert_allocation_available_v1(a.projeto_id,a.celula_destino_id,null);
$patch$||marker);
 definition:=pg_get_functiondef('rm_private.clone_engineering_children_v1(uuid,uuid,uuid)'::regprocedure);
 marker:='  insert into public.rm_fotos(';
 if strpos(definition,marker)=0 then raise exception 'Unexpected engineering cloning'; end if;
 execute replace(definition,marker,'  perform rm_private.assert_allocation_available_v1(cp.projeto_id,cp.celula_id,cp.id);'||chr(10)||marker);
 -- 018 materialization already INSERTs only absent pairs, ON CONFLICT DO
 -- NOTHING, and skips cloning when no ID was inserted. Retired pairs remain.
 definition:=pg_get_functiondef('rm_private.web_mutate_project_core_v1(uuid,text,jsonb)'::regprocedure);
 marker:='    next_cell := jsonb_populate_record(cell,changes);';
 if strpos(definition,marker)=0 then raise exception 'Unexpected existing planning edit'; end if;
 definition:=replace(definition,marker,marker||$patch$
    if not is_new then
     perform rm_private.assert_allocation_available_v1(cell.projeto_id,cell.celula_id,cell.id);
     if next_cell.visibilidade is distinct from cell.visibilidade then
      raise exception 'Altere a visibilidade pelo comando de disponibilidade da alocação.' using errcode='22023'; end if;
    end if;
$patch$);
 marker:='    select * into registration from public.rm_registros_formulario where id=record_id for update;';
 if strpos(definition,marker)=0 then raise exception 'Unexpected form review context'; end if;
 definition:=replace(definition,marker,marker||chr(10)||'    perform rm_private.assert_allocation_available_v1(registration.projeto_id,registration.celula_id,null);');
 -- Historical allocations continue protecting type changes. Only the current
 -- active scope participates in billing obligations; captured/history guards
 -- prevented real work from being withdrawn in the first place.
 definition:=replace(definition,'if not exists(select 1 from public.rm_celulas_projeto where projeto_id=project.id)',
  'if not exists(select 1 from public.rm_celulas_projeto where projeto_id=project.id and not retirada)');
 definition:=replace(definition,'where projeto_id=project.id and status not in (''finalizado'',''n_a'')',
  'where projeto_id=project.id and not retirada and status not in (''finalizado'',''n_a'')');
 definition:=replace(definition,'where cp.projeto_id=project.id and cp.status<>''n_a''',
  'where cp.projeto_id=project.id and not cp.retirada and cp.status<>''n_a''');
 marker:='where projeto_id=project.id and not lixeira and categoria_foto=''obrigat_ria''';
 if strpos(definition,marker)=0 then raise exception 'Unexpected billing photo scope'; end if;
 definition:=replace(definition,marker,marker||$patch$
          and not exists(select 1 from public.rm_celulas_projeto retired where retired.retirada
            and retired.projeto_id=public.rm_fotos.projeto_id and (retired.id=public.rm_fotos.celula_projeto_id or retired.celula_id=public.rm_fotos.celula_id))
$patch$);
 execute definition;
end $$;

-- Preserve the existing view column order after adding cp.retirada.
do $$ declare projection text; begin
 select string_agg('a.'||quote_ident(attname),',' order by attnum) into projection
 from pg_attribute where attrelid='rm_private.web_open_cell_allocations_v1'::regclass
  and attnum>0 and not attisdropped and attname<>'project_updated_at';
 execute format($view$create or replace view rm_private.web_open_cell_allocations_v1 with(security_invoker=true) as
 select %s,p.updated_at as project_updated_at from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id
 where not a.retirada and p.data_real_de_entrega is null
 and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
 and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
 and a.status is distinct from 'finalizado'::public.rm_status_cel_proj_enum
 and a.status is distinct from 'n_a'::public.rm_status_cel_proj_enum$view$,projection);
end $$;

create or replace function public.rm_web_project_route_snapshot_v1(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 with route as materialized (
  select a.*,c.nome as celula_nome,c.updated_at as cell_updated_at
  from public.rm_celulas_projeto a left join public.rm_celulas c on c.id=a.celula_id
  where a.projeto_id=p_project_id and not a.retirada
 ), aggregate as (
  select count(*) total,
   coalesce(jsonb_agg(jsonb_build_object('id',a.id,'updated_at',a.updated_at,'indice',a.indice,
    'celula_id',a.celula_id,'cell_updated_at',a.cell_updated_at) order by a.indice nulls last,a.id),'[]'::jsonb) revisions,
   coalesce(jsonb_agg(jsonb_build_object('id',a.id,'celula_id',a.celula_id,'celula_nome',a.celula_nome,
    'status',a.status,'visibilidade',a.visibilidade,'indice',a.indice,'updated_at',a.updated_at)
    order by a.indice nulls last,a.id),'[]'::jsonb) items
  from route a
 ), project as (
  select p.id,p.updated_at,jsonb_build_object('id',p.id,'numero',p.numero,'nome',p.nome,'status_pcp',p.status_pcp,
   'data_real_de_entrega',p.data_real_de_entrega,'updated_at',p.updated_at,
   'closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in ('cancelado','finalizando_para_faturar'),false)) dto
  from public.rm_projetos p where p.id=p_project_id
 )
 select jsonb_build_object('project',p.dto,'total',a.total,'complete',a.total<=2000,
  'items',case when a.total<=2000 then a.items else '[]'::jsonb end,
  'route_version',encode(sha256(convert_to(jsonb_build_object('project',p.dto,'revisions',a.revisions)::text,'UTF8')),'hex'))
 from project p cross join aggregate a;
$$;

create or replace function public.rm_web_receivings_v1(p_reason text default 'all',p_search text default '',
  p_page integer default 1,p_page_size integer default 25) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if p_reason is null or p_reason not in ('all','without_number','without_type','without_allocation','awaiting_arrival','legacy_type_locked')
    or p_search is null or length(p_search)>200 or p_page is null or p_page<1 or p_page>10000
    or p_page_size is null or p_page_size<1 or p_page_size>100 then
    raise exception 'Filtros de recebimento inválidos.' using errcode='22023'; end if;
  with allocations as (
    select projeto_id,count(*) filter(where not retirada) allocation_count,count(*) historical_allocation_count from public.rm_celulas_projeto group by projeto_id
  ), projects as (
    select p.*,c.nome cliente_nome,t.nome tipo_equipamento_nome,coalesce(a.allocation_count,0) allocation_count,coalesce(a.historical_allocation_count,0) historical_allocation_count,
      array_remove(array[
        case when nullif(btrim(p.numero),'') is null then 'without_number' end,
        case when p.tipo_equipamento_id is null then 'without_type' end,
        case when coalesce(a.allocation_count,0)=0 then 'without_allocation' end,
        case when p.chegada_do_equipamento is null then 'awaiting_arrival' end,
        case when p.tipo_equipamento_id is null and coalesce(a.historical_allocation_count,0)>0 then 'legacy_type_locked' end
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
    'status_pcp',p.status_pcp,'updated_at',p.updated_at,'allocation_count',p.allocation_count,'historical_allocation_count',p.historical_allocation_count,'reasons',p.reasons)
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


notify pgrst,'reload schema';
commit;
