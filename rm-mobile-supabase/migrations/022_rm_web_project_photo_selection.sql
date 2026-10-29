-- Reuse the imported per-photo flag. Installing this migration changes no rows.
-- Selection does not generate a report or enable the outbound Bubble bridge.
begin;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_pcp_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  project_id uuid; photo_id uuid; expected timestamptz; selected boolean;
  photo public.rm_fotos%rowtype; before_record jsonb; result jsonb;
begin
  if p_operation is distinct from 'set_project_photo_selection' then
    return rm_private.web_mutate_pcp_core_v1(p_client_submission_id,p_operation,p_payload); end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or not coalesce(actor.perfil in ('administrador','padr_o'),false) then
    raise exception 'Operação restrita à administração/PCP.' using errcode='42501'; end if;
  if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
    and (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
  if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Envio inválido.' using errcode='22023'; end if;
  -- Same lock order as the existing envelope and project writers. Replays are
  -- serialized before reading receipts; the public envelope still needs a fresh
  -- SSO permit before entering this core, even for an exact replay.
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
  select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
  if found then
    if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
      raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
    return receipt.result||jsonb_build_object('idempotent_replay',true);
  end if;
  if not p_payload ?& array['projeto_id','foto_id','expected_updated_at','selected']
    or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('projeto_id','foto_id','expected_updated_at','selected'))
    or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string'
    or jsonb_typeof(p_payload->'foto_id') is distinct from 'string'
    or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string'
    or jsonb_typeof(p_payload->'selected') is distinct from 'boolean'
    or (p_payload->>'expected_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'Seleção ou versão inválida.' using errcode='22023'; end if;
  project_id:=(p_payload->>'projeto_id')::uuid;
  photo_id:=(p_payload->>'foto_id')::uuid;
  expected:=(p_payload->>'expected_updated_at')::timestamptz;
  selected:=(p_payload->>'selected')::boolean;
  if not isfinite(expected) then raise exception 'Versão inválida.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
  perform 1 from public.rm_projetos where id=project_id for update;
  if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
  -- Closed projects remain selectable: historical reports also use this flag.
  select * into photo from public.rm_fotos where id=photo_id for update;
  if not found then raise exception 'Foto inexistente.' using errcode='P0002'; end if;
  -- In this schema a template is identified by projeto_id IS NULL; there is no
  -- is_template column. Do not invent a second source of template identity.
  if photo.projeto_id is distinct from project_id or photo.lixeira
    or nullif(btrim(photo.foto_url),'') is null then
    raise exception 'Foto indisponível neste projeto.' using errcode='22023'; end if;
  if expected<>photo.updated_at then
    raise exception 'A foto foi alterada. Atualize antes de salvar.' using errcode='PT409'; end if;
  before_record:=to_jsonb(photo);
  if photo.selecao_relatorio is distinct from selected then
    update public.rm_fotos set selecao_relatorio=selected,modified_by_id=actor.id,sync_source='supabase'
      where id=photo.id returning * into photo;
  end if;
  result:=jsonb_build_object('operation',p_operation,'id',photo.id,'projeto_id',project_id,'updated_at',photo.updated_at,
    'record',jsonb_build_object('foto_id',photo.id,'projeto_id',project_id,'selecao_relatorio',photo.selecao_relatorio,
      'updated_at',photo.updated_at),'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
  if p_operation='set_project_photo_selection' then
    raise exception 'Identificador, seleção ou data inválida.' using errcode='22023'; end if;
  raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
    'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
    'set_project_photo_selection'));
do $$ declare definition text; needle text:='when ''save_cell_queue'' then ''em.planning.manage'' end;'; begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
  execute replace(definition,needle,'when ''save_cell_queue'' then ''em.planning.manage'' when ''set_project_photo_selection'' then ''em.projects.manage'' end;');
  -- Recompile the warm wrapper after the core rename, as in 017/020/021. Its
  -- cached call must resolve to the new dispatcher rather than the old OID.
  execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),
  rm_private.web_mutate_pcp_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
