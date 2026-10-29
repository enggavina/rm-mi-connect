-- Project route order (indice) is distinct from a cell's queue order (posicao).
-- Installation is additive: no existing route, allocation or offline ID changes.
begin;

create function public.rm_web_project_route_snapshot_v1(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 with route as materialized (
  select a.*,c.nome as celula_nome,c.updated_at as cell_updated_at
  from public.rm_celulas_projeto a left join public.rm_celulas c on c.id=a.celula_id
  where a.projeto_id=p_project_id
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
revoke all on function public.rm_web_project_route_snapshot_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_route_snapshot_v1(uuid) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_photo_title_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 project public.rm_projetos%rowtype; project_id uuid; expected_project timestamptz; expected timestamptz;
 item jsonb; item_id uuid; n int; ordinal int:=0; submitted_ids uuid[]; route_ids uuid[];
 snapshot jsonb; before_record jsonb; result jsonb; changed uuid[]:='{}';
begin
 if p_operation is distinct from 'save_project_route' then
  return rm_private.web_mutate_photo_title_core_v1(p_client_submission_id,p_operation,p_payload); end if;
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
 if not p_payload ?& array['projeto_id','expected_project_updated_at','expected_route_version','items']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('projeto_id','expected_project_updated_at','expected_route_version','items'))
  or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string'
  or jsonb_typeof(p_payload->'expected_project_updated_at') is distinct from 'string'
  or (p_payload->>'expected_project_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or jsonb_typeof(p_payload->'expected_route_version') is distinct from 'string'
  or (p_payload->>'expected_route_version') !~ '^[0-9a-f]{64}$'
  or jsonb_typeof(p_payload->'items') is distinct from 'array' then
  raise exception 'Roteiro ou versão inválida.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid;
 expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz;
 if not isfinite(expected_project) then raise exception 'Versão inválida.' using errcode='22023'; end if;
 n:=jsonb_array_length(p_payload->'items');
 if n<1 or n>2000 then raise exception 'O roteiro deve conter entre 1 e 2000 alocações.' using errcode='22023'; end if;
 for item in select value from jsonb_array_elements(p_payload->'items') loop
  if jsonb_typeof(item)<>'object' or not item ?& array['id','expected_updated_at']
   or exists(select 1 from jsonb_object_keys(item) k where k not in ('id','expected_updated_at'))
   or jsonb_typeof(item->'id') is distinct from 'string'
   or jsonb_typeof(item->'expected_updated_at') is distinct from 'string'
   or (item->>'expected_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
   raise exception 'Item de roteiro inválido.' using errcode='22023'; end if;
  item_id:=(item->>'id')::uuid; expected:=(item->>'expected_updated_at')::timestamptz;
  if not isfinite(expected) then raise exception 'Versão inválida.' using errcode='22023'; end if;
 end loop;
 select array_agg((value->>'id')::uuid order by ordinality) into submitted_ids
  from jsonb_array_elements(p_payload->'items') with ordinality;
 if (select count(distinct id) from unnest(submitted_ids) id)<>n then
  raise exception 'Alocação repetida.' using errcode='22023'; end if;
 -- Matches plan_cell, materialization, queue saves and mobile status writers.
 -- The parent row lock also serializes FK insertions that omit the advisory lock.
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 perform 1 from public.rm_celulas_projeto where projeto_id=project_id order by id for update;
 before_record:=public.rm_web_project_route_snapshot_v1(project_id);
 if project.updated_at<>expected_project or before_record->>'route_version' is distinct from p_payload->>'expected_route_version'
  or not (before_record->>'complete')::boolean or (before_record->>'total')::integer<>n then
  raise exception 'O projeto ou roteiro foi alterado. Atualize antes de salvar.' using errcode='PT409'; end if;
 if (before_record->'project'->>'closed')::boolean then
  raise exception 'Projeto encerrado não aceita replanejamento.' using errcode='22023'; end if;
 select array_agg((value->>'id')::uuid order by ordinality) into route_ids
  from jsonb_array_elements(before_record->'items') with ordinality;
 if not submitted_ids @> route_ids or not route_ids @> submitted_ids then
  raise exception 'O roteiro deve conter todas e somente as alocações do projeto.' using errcode='22023'; end if;
 for item in select value from jsonb_array_elements(p_payload->'items') loop
  ordinal:=ordinal+1; item_id:=(item->>'id')::uuid; expected:=(item->>'expected_updated_at')::timestamptz;
  if not exists(select 1 from public.rm_celulas_projeto where id=item_id and projeto_id=project_id and updated_at=expected) then
   raise exception 'Alocação alterada. Atualize antes de salvar.' using errcode='PT409'; end if;
  update public.rm_celulas_projeto set indice=ordinal,modified_by_id=actor.id,replanejada_em=clock_timestamp(),
   replanejada_por_id=actor.id,sync_source='supabase' where id=item_id and indice is distinct from ordinal;
  if found then changed:=array_append(changed,item_id); end if;
 end loop;
 snapshot:=public.rm_web_project_route_snapshot_v1(project_id);
 result:=jsonb_build_object('operation',p_operation,'id',project_id,'projeto_id',project_id,'updated_at',clock_timestamp(),
  'record',jsonb_build_object('projeto_id',project_id,'route_version',snapshot->>'route_version','changed_ids',to_jsonb(changed)),
  'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation='save_project_route' then raise exception 'Identificador, ordem ou data inválida.' using errcode='22023'; end if;
 raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
  'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
  'set_project_photo_selection','delete_photo_title','save_project_route'));
do $$ declare definition text; needle text:='when ''delete_photo_title'' then ''em.engineering.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
 execute replace(definition,needle,'when ''delete_photo_title'' then ''em.engineering.manage'' when ''save_project_route'' then ''em.planning.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),
 rm_private.web_mutate_photo_title_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
