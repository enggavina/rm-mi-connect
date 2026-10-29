-- Complete the existing photo-title CRUD without deleting operational history.
-- No data migration, Central grants, outbound bridge jobs or new capabilities.
begin;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_project_photo_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
  title_row public.rm_cadastro_fotos%rowtype; record_id uuid; expected timestamptz; result jsonb;
begin
  if p_operation is distinct from 'delete_photo_title' then
    return rm_private.web_mutate_project_photo_core_v1(p_client_submission_id,p_operation,p_payload); end if;
  select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
  if actor.id is null or actor.perfil is distinct from 'administrador' then
    raise exception 'Títulos de fotos restritos à administração.' using errcode='42501'; end if;
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
  if not p_payload ?& array['id','expected_updated_at']
    or exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('id','expected_updated_at'))
    or jsonb_typeof(p_payload->'id') is distinct from 'string'
    or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string'
    or (p_payload->>'expected_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'Identificador e versão são obrigatórios.' using errcode='22023'; end if;
  record_id:=(p_payload->>'id')::uuid; expected:=(p_payload->>'expected_updated_at')::timestamptz;
  if record_id is null or expected is null or not isfinite(expected) then
    raise exception 'Identificador ou versão inválidos.' using errcode='22023'; end if;
  -- Same order as title save, cell rename and engineering-photo writes (018).
  -- Exclusive catalog lock also serializes a new model reference with deletion.
  perform pg_advisory_xact_lock(hashtextextended('rm.web.catalogs',17));
  select * into title_row from public.rm_cadastro_fotos where id=record_id for update;
  if not found or title_row.updated_at<>expected then
    raise exception 'Título alterado ou removido. Atualize antes de excluir.' using errcode='PT409'; end if;
  -- Keep the 018 FK ON DELETE RESTRICT. Every reference blocks deletion,
  -- including retired model rows, deleted photos and operational project rows.
  -- Never clear a reference or rewrite a photo's title snapshot to allow delete.
  begin
    delete from public.rm_cadastro_fotos where id=record_id;
  exception when foreign_key_violation or restrict_violation then
    raise exception 'Título vinculado a fotos ou modelos; exclusão não permitida.' using errcode='23503';
  end;
  result:=jsonb_build_object('operation',p_operation,'id',record_id,'projeto_id',null,'updated_at',title_row.updated_at,
    'record',jsonb_build_object('id',title_row.id,'titulo',title_row.titulo,'numero',title_row.numero,
      'celula_nome',title_row.celula_nome,'updated_at',title_row.updated_at),'idempotent_replay',false);
  insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
    values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,to_jsonb(title_row));
  return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
  if p_operation='delete_photo_title' then
    raise exception 'Identificador ou data inválidos.' using errcode='22023'; end if;
  raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
  check(operation in ('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
    'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
    'set_project_photo_selection','delete_photo_title'));

do $$ declare definition text; needle text:='when ''set_project_photo_selection'' then ''em.projects.manage'' end;'; begin
  definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
  if strpos(definition,needle)=0 then raise exception 'Unexpected permit capability map'; end if;
  execute replace(definition,needle,'when ''set_project_photo_selection'' then ''em.projects.manage'' when ''delete_photo_title'' then ''em.engineering.manage'' end;');
  -- Warm public sessions must resolve the new dispatcher after the core rename.
  execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),
  rm_private.web_mutate_project_photo_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
