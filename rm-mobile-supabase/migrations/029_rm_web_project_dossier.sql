-- Append-only project comments and reserved, private project attachments.
-- Target: oficina-em-mi-off. No legacy row, bucket or mobile policy is rewritten.
begin;

create table rm_private.project_attachment_uploads (
 id uuid primary key,
 auth_user_id uuid not null,
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 nome text not null check(length(nome) between 1 and 200),
 descricao text check(length(descricao)<=2000),
 filename text not null check(length(filename) between 1 and 180),
 mime_type text not null check(mime_type in('application/pdf','image/jpeg','image/png')),
 byte_size integer not null check(byte_size between 1 and 20971520),
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 object_path text not null unique,
 status_documento text not null check(status_documento in('No prazo','Vencido')),
 data_vencimento timestamptz,
 finalized_doc_id uuid unique references public.rm_docs(id) on delete restrict,
 created_at timestamptz not null default clock_timestamp(),
 completed_at timestamptz,
 check((finalized_doc_id is null)=(completed_at is null)),
 check(finalized_doc_id is null or finalized_doc_id=id)
);
revoke all on rm_private.project_attachment_uploads from public,anon,authenticated,service_role;

create function rm_private.guard_project_attachment_doc_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from rm_private.project_attachment_uploads u where u.finalized_doc_id=old.id) then
  raise exception 'Este anexo é imutável. Inclua um novo arquivo.' using errcode='22023'; end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
revoke all on function rm_private.guard_project_attachment_doc_v1() from public,anon,authenticated,service_role;
create trigger rm_guard_web_dossier before update or delete on public.rm_docs
 for each row execute function rm_private.guard_project_attachment_doc_v1();

-- New attachments are internal even when a legacy customer identity has a
-- direct Auth JWT. Keep every old row's read rule unchanged.
create function rm_private.can_read_project_dossier_v1() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rm_users u where u.auth_user_id=auth.uid()
  and u.status='ativo' and u.perfil in('administrador','padr_o','auditor'));
$$;
revoke all on function rm_private.can_read_project_dossier_v1() from public,anon,authenticated,service_role;
grant execute on function rm_private.can_read_project_dossier_v1() to authenticated;
create policy rm_web_dossier_internal_read on public.rm_docs as restrictive
 for select to authenticated using (
  coalesce(arquivo_url not like 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/web-dossier/%',true)
  or rm_private.can_read_project_dossier_v1()
 );

-- The existing permissive policy still reads legacy documents. This additional
-- restriction hides new incomplete uploads; legacy names/buckets are unchanged.
-- New names begin with web-dossier/, so the old auth.uid() INSERT/UPDATE policies
-- never authorize writing them. Only the narrowly scoped server uploader writes.
create policy rm_web_dossier_published_read on storage.objects as restrictive
 for select to authenticated using (
  bucket_id is distinct from 'rm-documentos' or coalesce(name not like 'web-dossier/%',true)
  or exists(select 1 from public.rm_docs d where d.arquivo_url=
   'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/'||name)
 );

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_cell_availability_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype;
 project public.rm_projetos%rowtype; allocation public.rm_celulas_projeto%rowtype;
 upload rm_private.project_attachment_uploads%rowtype; document public.rm_docs%rowtype;
 comment public.rm_comentarios%rowtype; object storage.objects%rowtype;
 project_id uuid; allocation_id uuid; upload_id uuid; expected_project timestamptz; expected_allocation timestamptz;
 expiry timestamptz; body text; object_count integer; result jsonb; allowed text[];
 url_prefix constant text:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/';
begin
 if p_operation not in('add_project_comment','reserve_project_attachment','finalize_project_attachment') or p_operation is null then
  return rm_private.web_mutate_cell_availability_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then
  raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified')
  and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then
  raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then
   raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 allowed:=case p_operation
  when 'add_project_comment' then array['projeto_id','celula_projeto_id','expected_project_updated_at','expected_allocation_updated_at','evento']
  when 'reserve_project_attachment' then array['upload_id','projeto_id','expected_project_updated_at','nome','descricao','filename','mime_type','byte_size','sha256','data_vencimento','status']
  else array['projeto_id','upload_id'] end;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string' then
  raise exception 'Contexto ou campos inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid;
 if p_operation<>'finalize_project_attachment' then
  if jsonb_typeof(p_payload->'expected_project_updated_at') is distinct from 'string'
   or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
   raise exception 'Versão do projeto inválida.' using errcode='22023'; end if;
  expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz;
  if not isfinite(expected_project) then raise exception 'Versão do projeto inválida.' using errcode='22023'; end if;
 end if;
 if p_operation='add_project_comment' then
  if jsonb_typeof(p_payload->'celula_projeto_id') is distinct from 'string'
   or jsonb_typeof(p_payload->'expected_allocation_updated_at') is distinct from 'string'
   or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
   or jsonb_typeof(p_payload->'evento') is distinct from 'string' then
   raise exception 'Célula, versão ou comentário inválido.' using errcode='22023'; end if;
  allocation_id:=(p_payload->>'celula_projeto_id')::uuid;
  expected_allocation:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
  body:=btrim(p_payload->>'evento');
  if not isfinite(expected_allocation) or length(body)<1 or length(body)>10000 then
   raise exception 'Informe um comentário de até 10000 caracteres.' using errcode='22023'; end if;
 else
  if jsonb_typeof(p_payload->'upload_id') is distinct from 'string' then raise exception 'Protocolo do arquivo inválido.' using errcode='22023'; end if;
  upload_id:=(p_payload->>'upload_id')::uuid;
  if p_operation='finalize_project_attachment' and p_client_submission_id<>upload_id then
   raise exception 'Use o mesmo protocolo do arquivo.' using errcode='22023'; end if;
 end if;
 if p_operation='reserve_project_attachment' then
  if p_client_submission_id=upload_id then raise exception 'Protocolo de reserva deve ser distinto do envio final.' using errcode='22023'; end if;
  if jsonb_typeof(p_payload->'nome') is distinct from 'string' or length(btrim(p_payload->>'nome')) not between 1 and 200
   or jsonb_typeof(p_payload->'descricao') not in('string','null') or length(btrim(p_payload->>'descricao'))>2000
   or jsonb_typeof(p_payload->'filename') is distinct from 'string' or length(p_payload->>'filename') not between 1 and 180
   or p_payload->>'filename' ~ '[[:cntrl:]/\\]'
   or jsonb_typeof(p_payload->'mime_type') is distinct from 'string' or p_payload->>'mime_type' not in('application/pdf','image/jpeg','image/png')
   or jsonb_typeof(p_payload->'byte_size') is distinct from 'number' or p_payload->>'byte_size' !~ '^[0-9]+$'
   or (p_payload->>'byte_size')::numeric not between 1 and 20971520
   or jsonb_typeof(p_payload->'sha256') is distinct from 'string' or p_payload->>'sha256' !~ '^[a-f0-9]{64}$'
   or jsonb_typeof(p_payload->'status') is distinct from 'string' or p_payload->>'status' not in('No prazo','Vencido')
   or jsonb_typeof(p_payload->'data_vencimento') not in('string','null') then
   raise exception 'Dados do anexo inválidos. Use PDF, JPEG ou PNG de até 20 MiB.' using errcode='22023'; end if;
  if jsonb_typeof(p_payload->'data_vencimento')='string' then
   if p_payload->>'data_vencimento' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'Vencimento inválido.' using errcode='22023'; end if;
   expiry:=(p_payload->>'data_vencimento')::timestamptz;
   if not isfinite(expiry) then raise exception 'Vencimento inválido.' using errcode='22023'; end if;
  end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into project from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 if p_operation<>'finalize_project_attachment' and project.updated_at<>expected_project then
  raise exception 'O projeto mudou. Atualize antes de enviar.' using errcode='PT409'; end if;
 if project.data_real_de_entrega is not null or coalesce(project.status_pcp in('cancelado','finalizando_para_faturar'),false) then
  raise exception 'Projeto encerrado: somente consulta.' using errcode='22023'; end if;
 if p_operation='add_project_comment' then
  select * into allocation from public.rm_celulas_projeto where id=allocation_id for update;
  if not found or allocation.projeto_id is distinct from project_id then
   raise exception 'A célula não pertence a este projeto.' using errcode='22023'; end if;
  perform rm_private.assert_allocation_available_v1(project_id,allocation.celula_id,allocation.id);
  if allocation.updated_at<>expected_allocation then raise exception 'A célula mudou. Atualize antes de enviar.' using errcode='PT409'; end if;
  insert into public.rm_comentarios(id,projeto_id,celula_id,cadastrado_por_id,evento,sync_source)
   values(p_client_submission_id,project_id,allocation.celula_id,actor.id,body,'supabase') returning * into comment;
  perform rm_private.enqueue_sync_event('bubble_data_api','Comentario_Celula','create',comment.id,null,
   jsonb_build_object('comentario_id',comment.id,'projeto_id',project_id,'celula_id',allocation.celula_id));
  result:=jsonb_build_object('operation',p_operation,'id',comment.id,'projeto_id',project_id,'updated_at',comment.updated_at,
   'record',jsonb_build_object('comment_id',comment.id,'projeto_id',project_id,'celula_projeto_id',allocation.id,'celula_id',allocation.celula_id,
    'cadastrado_por_id',actor.id,'evento',comment.evento,'created_at',comment.created_at),'idempotent_replay',false);
 elsif p_operation='reserve_project_attachment' then
  if exists(select 1 from rm_private.project_attachment_uploads where id=upload_id) or exists(select 1 from public.rm_docs where id=upload_id) then
   raise exception 'Identificador do anexo já utilizado.' using errcode='23505'; end if;
  insert into rm_private.project_attachment_uploads(id,auth_user_id,actor_id,projeto_id,nome,descricao,filename,mime_type,byte_size,sha256,object_path,status_documento,data_vencimento)
   values(upload_id,auth.uid(),actor.id,project_id,btrim(p_payload->>'nome'),nullif(btrim(p_payload->>'descricao'),''),p_payload->>'filename',
    p_payload->>'mime_type',(p_payload->>'byte_size')::integer,p_payload->>'sha256',
    'web-dossier/'||project_id::text||'/'||upload_id::text||case p_payload->>'mime_type' when 'application/pdf' then '.pdf' when 'image/jpeg' then '.jpg' else '.png' end,
    p_payload->>'status',expiry) returning * into upload;
  result:=jsonb_build_object('operation',p_operation,'id',upload.id,'projeto_id',project_id,'updated_at',upload.created_at,
   'record',jsonb_build_object('upload_id',upload.id,'projeto_id',project_id,'path',upload.object_path,'mime_type',upload.mime_type,'byte_size',upload.byte_size,'sha256',upload.sha256),
   'idempotent_replay',false);
 else
  select * into upload from rm_private.project_attachment_uploads where id=upload_id for update;
  if not found or upload.projeto_id is distinct from project_id then raise exception 'Reserva do anexo inexistente neste projeto.' using errcode='P0002'; end if;
  if upload.auth_user_id<>auth.uid() or upload.actor_id<>actor.id then raise exception 'Reserva vinculada a outra identidade.' using errcode='42501'; end if;
  if upload.finalized_doc_id is not null then raise exception 'Anexo já concluído. Repita o protocolo original.' using errcode='23505'; end if;
  select count(*) into object_count from storage.objects where bucket_id='rm-documentos' and name=upload.object_path;
  if object_count=0 then raise exception 'O arquivo ainda não foi confirmado. Repita o mesmo envio.' using errcode='PT503'; end if;
  if object_count<>1 then raise exception 'O arquivo exige reconciliação antes de concluir.' using errcode='PT409'; end if;
  select * into object from storage.objects where bucket_id='rm-documentos' and name=upload.object_path for share;
  if coalesce(object.metadata->>'size','') !~ '^[0-9]+$' then
   raise exception 'O arquivo não corresponde ao envio reservado.' using errcode='PT409'; end if;
  if (object.metadata->>'size')::numeric<>upload.byte_size
   or object.metadata->>'mimetype' is distinct from upload.mime_type or object.user_metadata->>'sha256' is distinct from upload.sha256 then
   raise exception 'O arquivo não corresponde ao envio reservado.' using errcode='PT409'; end if;
  insert into public.rm_docs(id,projeto_id,nome,descricao,arquivo_url,tipo_arquivo,visivel_cliente,created_by,status,data_vencimento,sync_source)
   values(upload.id,project_id,upload.nome,upload.descricao,url_prefix||upload.object_path,upload.mime_type,false,actor.id,upload.status_documento,upload.data_vencimento,'supabase') returning * into document;
  update rm_private.project_attachment_uploads set finalized_doc_id=document.id,completed_at=clock_timestamp() where id=upload.id;
  result:=jsonb_build_object('operation',p_operation,'id',document.id,'projeto_id',project_id,'updated_at',document.updated_at,
   'record',jsonb_build_object('upload_id',upload.id,'projeto_id',project_id,'attachment_id',document.id,'nome',document.nome,'descricao',document.descricao,
    'tipo_arquivo',document.tipo_arquivo,'status',document.status,'data_vencimento',document.data_vencimento,'visivel_cliente',false,'updated_at',document.updated_at),'idempotent_replay',false);
 end if;
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation in('add_project_comment','reserve_project_attachment','finalize_project_attachment') then
  raise exception 'Identificador, data ou dados do dossiê inválidos.' using errcode='22023'; end if; raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check
 check(operation in('save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title',
 'create_form_template','save_form_template','publish_form_template','transition_stage_approval','save_cell_queue',
 'set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules','manage_cell_availability',
 'add_project_comment','reserve_project_attachment','finalize_project_attachment'));
do $$ declare definition text; needle text:='when ''manage_cell_availability'' then ''em.planning.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected dossier permit map'; end if;
 execute replace(definition,needle,'when ''manage_cell_availability'' then ''em.planning.manage'' when ''add_project_comment'' then ''em.projects.manage'' when ''reserve_project_attachment'' then ''em.projects.manage'' when ''finalize_project_attachment'' then ''em.projects.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_cell_availability_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
