-- Atomic project/equipment edits. Reuse the existing project and equipment
-- transactions, audit and offline guard; never repair ambiguous legacy links.
begin;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_equipment_bundle_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 p public.rm_projetos%rowtype; snap jsonb; eq jsonb; project_result jsonb; result jsonb;
 project_id uuid; equipment_id uuid; expected timestamptz; is_new boolean;
begin
 if p_operation is distinct from 'save_project_with_equipment' then
  return rm_private.web_mutate_before_equipment_bundle_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload ?& array['id','expected_updated_at','changes','equipment']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','expected_updated_at','changes','equipment'))
  or jsonb_typeof(p_payload->'id') is distinct from 'string' or jsonb_typeof(p_payload->'changes') is distinct from 'object'
  or jsonb_typeof(p_payload->'equipment') is distinct from 'object' then raise exception 'Dados do projeto e equipamento inválidos.' using errcode='22023'; end if;
 if (p_payload->'changes') ?| array['tipo_equipamento_id','descricao_equipamento'] then raise exception 'Classificação e dados técnicos usam seus próprios fluxos.' using errcode='22023'; end if;
 eq:=p_payload->'equipment';
 if not eq ?& array['id','expected_updated_at','expected_context_version','changes']
  or exists(select 1 from jsonb_object_keys(eq) k where k not in('id','expected_updated_at','expected_context_version','changes'))
  or jsonb_typeof(eq->'id') is distinct from 'string' or jsonb_typeof(eq->'changes') is distinct from 'object'
  or jsonb_typeof(eq->'expected_updated_at') not in('string','null') or jsonb_typeof(eq->'expected_context_version') not in('string','null')
  then raise exception 'Contexto do equipamento inválido.' using errcode='22023'; end if;
 project_id:=(p_payload->>'id')::uuid; equipment_id:=(eq->>'id')::uuid;
 if project_id is null or equipment_id is null then raise exception 'Identificadores inválidos.' using errcode='22023'; end if;
 expected:=(p_payload->>'expected_updated_at')::timestamptz;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into p from public.rm_projetos where id=project_id for update;
 is_new:=not found;
 if is_new then
  if expected is not null or eq->'expected_updated_at'<>'null'::jsonb or eq->'expected_context_version'<>'null'::jsonb then raise exception 'O projeto mudou. Atualize antes de salvar.' using errcode='PT409'; end if;
 else
  -- Lock the referenced equipment before checking the snapshot. A direct
  -- writer/ETL may not acquire project11; the original version must remain
  -- stable until the nested 031 command takes its own lock.
  if p.equipamento_id is not null then perform 1 from public.rm_equipamentos where id=p.equipamento_id for update; end if;
  snap:=public.rm_web_project_equipment_snapshot_v1(project_id);
  if expected is null or p.updated_at<>expected or snap->>'context_version' is distinct from eq->>'expected_context_version'
    or snap->>'binding_state' not in('linked','missing') or (snap->'project'->>'closed')::boolean then raise exception 'O projeto ou vínculo do equipamento mudou. Atualize antes de salvar.' using errcode='PT409'; end if;
  if snap->>'binding_state'='linked' and ((snap->'equipment'->>'id')::uuid<>equipment_id or (snap->'equipment'->>'updated_at')::timestamptz is distinct from (eq->>'expected_updated_at')::timestamptz)
   or snap->>'binding_state'='missing' and eq->'expected_updated_at'<>'null'::jsonb then raise exception 'O equipamento mudou. Atualize antes de salvar.' using errcode='PT409'; end if;
 end if;
 if p_payload->'changes'<>'{}'::jsonb then
  project_result:=rm_private.web_mutate_before_equipment_bundle_v1(gen_random_uuid(),'save_project',jsonb_build_object('id',project_id,'expected_updated_at',p_payload->'expected_updated_at','changes',p_payload->'changes'));
 elsif is_new then raise exception 'Informe os dados do projeto.' using errcode='22023'; end if;
 if is_new or snap->>'binding_state'='missing' then
  if exists(select 1 from public.rm_equipamentos where id=equipment_id or projeto_id=project_id) then raise exception 'Vínculo de equipamento já existente.' using errcode='PT409'; end if;
  insert into public.rm_equipamentos(id,projeto_id) values(equipment_id,project_id);
  update public.rm_projetos set equipamento_id=equipment_id where id=project_id;
 end if;
 snap:=public.rm_web_project_equipment_snapshot_v1(project_id);
 if snap->>'binding_state'<>'linked' or (snap->'equipment'->>'id')::uuid<>equipment_id then raise exception 'Vínculo do equipamento inconsistente.' using errcode='PT409'; end if;
 if eq->'changes'<>'{}'::jsonb then
  perform rm_private.web_mutate_before_equipment_bundle_v1(gen_random_uuid(),'save_project_equipment',jsonb_build_object(
   'projeto_id',project_id,'equipamento_id',equipment_id,'expected_project_updated_at',snap->'project'->>'updated_at',
   'expected_equipment_updated_at',snap->'equipment'->>'updated_at','expected_context_version',snap->>'context_version',
   'confirm_change',true,'changes',eq->'changes'));
 end if;
 select * into p from public.rm_projetos where id=project_id;
 result:=jsonb_build_object('operation',p_operation,'id',project_id,'projeto_id',project_id,'updated_at',p.updated_at,
  'record',jsonb_build_object('id',project_id,'equipamento_id',equipment_id),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation='save_project_with_equipment' then raise exception 'Identificador, versão ou dados técnicos inválidos.' using errcode='22023'; end if; raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check check(operation in(
 'save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title','create_form_template','save_form_template','publish_form_template',
 'transition_stage_approval','save_cell_queue','set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules','manage_cell_availability',
 'add_project_comment','reserve_project_attachment','finalize_project_attachment','save_project_equipment','edit_project_comment','reserve_project_attachment_version','finalize_project_attachment_version','save_project_with_equipment'));
do $$ declare definition text; marker text:='when ''finalize_project_attachment_version'' then ''em.projects.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1 then raise exception 'Unexpected project permit map'; end if;
 execute replace(definition,marker,'when ''finalize_project_attachment_version'' then ''em.projects.manage'' when ''save_project_with_equipment'' then ''em.projects.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_equipment_bundle_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
