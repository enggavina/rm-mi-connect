begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.mobile_workshop_uploads (
 id uuid primary key,
 submission_id uuid not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 project_id uuid not null,
 operation text not null,
 auth_user_id uuid not null,
 operator_id uuid not null,
 intent_sha256 text not null check(intent_sha256~'^[a-f0-9]{64}$'),
 kind text not null check(kind in('photo','signature','document')),
 mime_type text not null check(mime_type in('image/jpeg','image/png','application/pdf')),
 byte_size integer not null check(byte_size between 1 and 20971520),
 content_sha256 text not null check(content_sha256~'^[a-f0-9]{64}$'),
 object_path text not null unique,
 created_at timestamptz not null default clock_timestamp(),
 stored_at timestamptz
);
create index mobile_workshop_uploads_submission on rm_private.mobile_workshop_uploads(submission_id);
alter table rm_private.mobile_workshop_uploads enable row level security;
revoke all on rm_private.mobile_workshop_uploads from public,anon,authenticated,service_role;

-- Older documents retain their existing policy. The new namespace is served
-- only by an authorized download issuing a short-lived storage credential.
create policy rm_mobile_workshop_uploads_private on storage.objects as restrictive for select to authenticated
 using(bucket_id is distinct from 'rm-documentos' or coalesce(name not like 'mobile-oficina/%',true));

create function rm_private.mobile_workshop_upload_reference_v1(p_operation text,p_payload jsonb,p_kind text,p_reference text)
returns boolean language sql immutable set search_path='' as $$
 select case p_operation
  when 'rm_submit_recebimento_v1' then (p_kind='document' and p_payload->>'p_arquivo_nota_fiscal_url'=p_reference)
   or (p_kind='photo' and exists(select 1 from jsonb_array_elements(case when jsonb_typeof(p_payload->'p_fotos_recebimento')='array'
    then p_payload->'p_fotos_recebimento' else '[]'::jsonb end) f where f->>'foto_url'=p_reference))
  when 'rm_record_cell_photo_v1' then p_kind='photo' and p_payload->>'p_foto_url'=p_reference
  when 'rm_submit_form_inspection_v1' then exists(select 1 from jsonb_array_elements(case when jsonb_typeof(p_payload->'p_respostas')='array'
    then p_payload->'p_respostas' else '[]'::jsonb end) a
   where (p_kind='signature' and a->>'assinatura_url'=p_reference)
    or (p_kind='photo' and jsonb_typeof(a->'fotos_urls')='array' and a->'fotos_urls' ? p_reference))
  when 'rm_submit_form_revision_v1' then exists(select 1 from jsonb_array_elements(case when jsonb_typeof(p_payload->'p_respostas_corrigidas')='array'
    then p_payload->'p_respostas_corrigidas' else '[]'::jsonb end) a
   where (p_kind='signature' and a->>'assinatura_url'=p_reference)
    or (p_kind='photo' and jsonb_typeof(a->'fotos_urls')='array' and a->'fotos_urls' ? p_reference))
  else false end
$$;
revoke all on function rm_private.mobile_workshop_upload_reference_v1(text,jsonb,text,text) from public,anon,authenticated,service_role;

create function public.rm_mobile_workshop_upload_v1(p_auth_user_id uuid,p_session_id uuid,p_operator_token text,
 p_workshop_context jsonb,p_workshop_origin uuid,p_submission uuid,p_operation text,p_payload jsonb,
 p_asset uuid,p_kind text,p_reference text,p_mime text,p_size integer,p_sha256 text,p_mark_stored boolean) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
 actor_id uuid;
 office uuid;
 project uuid;
 cell uuid;
 client_id uuid;
 extension text;
 byte_limit integer;
 canonical_path text;
 payload_hash text;
 upload rm_private.mobile_workshop_uploads;
 storage_meta record;
begin
 extension:=case p_mime when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png' end;
 byte_limit:=case p_kind when 'photo' then 15728640 when 'signature' then 5242880 else 20971520 end;
 if p_submission is null or p_asset is null or p_workshop_origin is null or p_mark_stored is null
  or p_kind is null or p_kind not in('photo','signature','document') or extension is null
  or p_kind='photo' and p_mime not in('image/jpeg','image/png') or p_kind='signature' and p_mime<>'image/png'
  or p_size is null or p_size not between 1 and byte_limit
  or p_sha256 is null or p_sha256!~'^[a-f0-9]{64}$' or jsonb_typeof(p_payload) is distinct from 'object'
  or octet_length(p_payload::text)>2097152 or p_reference is null or length(p_reference)>1024
  or p_reference!~'^file:///' or right(p_reference,37+length(extension)+1) is distinct from '/'||p_asset::text||'.'||extension
  or not coalesce(rm_private.mobile_workshop_upload_reference_v1(p_operation,p_payload,p_kind,p_reference),false) then
  raise exception 'O arquivo não corresponde ao registro original.' using errcode='22023';
 end if;
 select i.operator_subject into actor_id from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
 if actor_id is null then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 office:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,actor_id);
 if office is distinct from p_workshop_origin or p_payload->>'p_operador_id' is distinct from actor_id::text then
  raise exception 'O arquivo pertence a outra oficina ou operador.' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_submission::text,0));

 if p_operation='rm_submit_recebimento_v1' then
  select o.project_id into project from rm_private.receiving_openings o where o.client_submission_id=p_submission
   and o.auth_user_id=p_auth_user_id and o.operator_id=actor_id;
  if project is null or not rm_private.workshop_project_owned_v1(project,office) then
   raise exception 'Confirme a abertura do recebimento para enviar o arquivo.' using errcode='42501';
  end if;
  client_id:=nullif(p_payload->>'p_cliente_id','')::uuid;
  if client_id is not null and not rm_private.workshop_read_owned_v1('client',client_id,office) then
   raise exception 'O cliente do recebimento pertence a outra oficina.' using errcode='42501';
  end if;
 else
  project:=rm_private.mobile_mutation_workshop_project_v1(p_operation,p_payload,office);
  if p_operation='rm_submit_form_revision_v1' then
   select f.celula_id into cell from public.rm_registros_formulario f where f.id=(p_payload->>'p_registro_formulario_id')::uuid;
  elsif p_operation='rm_record_cell_photo_v1' and nullif(p_payload->>'p_foto_id','') is not null then
   select f.celula_id into cell from public.rm_fotos f where f.id=(p_payload->>'p_foto_id')::uuid;
  else
   cell:=nullif(p_payload->>'p_celula_id','')::uuid;
  end if;
  if project is null or not rm_private.operator_can_access_cell(actor_id,cell)
   or not exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=project and a.celula_id=cell and a.visibilidade and not a.retirada) then
   raise exception 'O projeto e a célula do arquivo não estão disponíveis.' using errcode='42501';
  end if;
 end if;

 perform pg_advisory_xact_lock(hashtextextended(project::text,11));
 if not rm_private.workshop_project_owned_v1(project,office) then raise exception 'Oficina do projeto indisponível.' using errcode='42501';end if;
 if p_operation<>'rm_submit_recebimento_v1' and (not rm_private.operator_can_access_cell(actor_id,cell)
  or not exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=project and a.celula_id=cell and a.visibilidade and not a.retirada)) then
  raise exception 'A célula deixou de estar disponível.' using errcode='42501';
 end if;
 if not exists(select 1 from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token)
  where expires_at>clock_timestamp()) or clock_timestamp()>=least((p_workshop_context->>'expires_at')::timestamptz,
   (p_workshop_context->>'issued_at')::timestamptz+interval '15 seconds') then
  raise exception 'Confirme novamente a oficina antes de enviar o arquivo.' using errcode='PT503';
 end if;
 canonical_path:='mobile-oficina/'||office||'/'||p_submission||'/'||p_asset||'.'||extension;
 payload_hash:=encode(sha256(convert_to(p_payload::text,'UTF8')),'hex');
 select * into upload from rm_private.mobile_workshop_uploads where id=p_asset for update;
 if found and (upload.submission_id,upload.workshop_id,upload.project_id,upload.operation,upload.auth_user_id,upload.operator_id,
  upload.intent_sha256,upload.kind,upload.mime_type,upload.byte_size,upload.content_sha256,upload.object_path) is distinct from
  (p_submission,office,project,p_operation,p_auth_user_id,actor_id,payload_hash,p_kind,p_mime,p_size,p_sha256,canonical_path) then
  raise exception 'Este arquivo já foi vinculado a outro protocolo.' using errcode='PT409';
 end if;
 if upload.id is null then
  if p_mark_stored then raise exception 'Autorização do arquivo indisponível.' using errcode='42501';end if;
  insert into rm_private.mobile_workshop_uploads(id,submission_id,workshop_id,project_id,operation,auth_user_id,operator_id,
   intent_sha256,kind,mime_type,byte_size,content_sha256,object_path)
  values(p_asset,p_submission,office,project,p_operation,p_auth_user_id,actor_id,payload_hash,p_kind,p_mime,p_size,p_sha256,canonical_path)
  returning * into upload;
 end if;
 if p_mark_stored then
  select o.metadata,o.user_metadata into storage_meta from storage.objects o where o.bucket_id='rm-documentos' and o.name=canonical_path;
  if not found or storage_meta.metadata->>'size' is distinct from p_size::text
   or storage_meta.metadata->>'mimetype' is distinct from p_mime
   or storage_meta.user_metadata->>'sha256' is distinct from p_sha256 then
   raise exception 'O armazenamento não confirmou o arquivo original.' using errcode='PT409';
  end if;
  update rm_private.mobile_workshop_uploads set stored_at=coalesce(stored_at,clock_timestamp()) where id=p_asset returning * into upload;
 end if;
 return jsonb_build_object('asset_id',upload.id,'workshop_id',upload.workshop_id,'submission_id',upload.submission_id,
  'path',upload.object_path,'stored',upload.stored_at is not null);
exception when invalid_text_representation then
 raise exception 'Referência de registro inválida.' using errcode='22023';
end
$$;
revoke all on function public.rm_mobile_workshop_upload_v1(uuid,uuid,text,jsonb,uuid,uuid,text,jsonb,uuid,text,text,text,integer,text,boolean)
 from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_workshop_upload_v1(uuid,uuid,text,jsonb,uuid,uuid,text,jsonb,uuid,text,text,text,integer,text,boolean)
 to service_role;

create function rm_private.workshop_stored_media_owned_v1(p_url text,p_workshop uuid,p_source text) returns boolean
language sql stable set search_path='' as $$
 with target as (select '/storage/v1/object/authenticated/rm-documentos/'::text as prefix)
 select coalesce(p_url not like 'https://ellpxfbsrbhblyizvbbk.supabase.co'||target.prefix||'mobile-oficina/%',true)
  or exists(select 1 from rm_private.mobile_workshop_uploads u
   where u.workshop_id=p_workshop and u.stored_at is not null and u.object_path=split_part(p_url,target.prefix,2)
    and u.kind=case p_source when 'document' then 'document' when 'answer_signature' then 'signature' else 'photo' end)
 from target
$$;
revoke all on function rm_private.workshop_stored_media_owned_v1(text,uuid,text) from public,anon,authenticated,service_role;

-- The canonical path must also belong to the workshop when loading a link.
-- A reference copied into an unrelated project never authorizes its bytes.
do $readers$
declare
 native_definition text:=pg_get_functiondef('public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[])'::regprocedure);
 media_definition text:=pg_get_functiondef('rm_private.workshop_media_reference_v1(jsonb,uuid)'::regprocedure);
 document_definition text:=pg_get_functiondef('rm_private.workshop_project_link_v1(text,jsonb,uuid)'::regprocedure);
 native_return constant text:='into files from matches;';
 web_return constant text:=' return result;';
begin
 if array_length(string_to_array(native_definition,native_return),1) is distinct from 2
  or array_length(string_to_array(media_definition,web_return),1) is distinct from 2
  or array_length(string_to_array(document_definition,web_return),1) is distinct from 2 then raise exception 'Unexpected workshop media authorization';end if;
 execute replace(native_definition,native_return,'into files from matches where rm_private.workshop_stored_media_owned_v1(url,office_id,source);');
 execute replace(media_definition,web_return,' if not rm_private.workshop_stored_media_owned_v1(result->>''file'',p_office,source) then return null;end if;'||chr(10)||web_return);
 execute replace(document_definition,web_return,' if not rm_private.workshop_stored_media_owned_v1(result->>''file'',p_office,''document'') then return null;end if;'||chr(10)||web_return);
end
$readers$;
notify pgrst,'reload schema';
commit;
