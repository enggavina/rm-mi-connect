begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- An attachment may be stored before a project exists. It acquires its
-- project in the same transaction that completes the original receiving.
alter table rm_private.mobile_workshop_uploads alter column project_id drop not null;
alter table rm_private.mobile_workshop_uploads add constraint mobile_receiving_draft_media_scope
 check (project_id is not null or operation='receiving_draft');

create function rm_private.workshop_receiving_media_refs_v1(p_document text,p_photos jsonb,p_photo_key text)
returns table(reference text,kind text) language sql immutable set search_path='' as $$
 select p_document,'document' where nullif(p_document,'') is not null
 union
 select f->>p_photo_key,'photo' from jsonb_array_elements(case when jsonb_typeof(p_photos)='array'
  then p_photos else '[]'::jsonb end) f where nullif(f->>p_photo_key,'') is not null
$$;

create function rm_private.receiving_private_media_path_v1(p_reference text) returns text
language sql immutable set search_path='' as $$
 select case when p_reference like
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/mobile-oficina/%'
 then substring(p_reference from length('https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/')+1) end
$$;

create function rm_private.assert_receiving_draft_media_v1(p_draft uuid,p_actor uuid,p_device uuid,p_office uuid,p_payload jsonb)
returns uuid[] language plpgsql stable set search_path='' as $$
declare files uuid[]; expected bigint; matched bigint;
begin
 with refs as materialized (
  select rm_private.receiving_private_media_path_v1(reference) path,kind
  from rm_private.workshop_receiving_media_refs_v1(p_payload->>'arquivoNotaFiscal',p_payload->'fotos','uri')
 ), linked as (
  select r.path,u.id from refs r left join rm_private.mobile_workshop_uploads u on u.object_path=r.path
   and u.submission_id=p_draft and u.workshop_id=p_office and u.auth_user_id=p_device and u.operator_id=p_actor
   and u.stored_at is not null and u.kind=r.kind and u.operation in('receiving_draft','rm_submit_recebimento_v1')
  where r.path is not null
 )
 select count(*),count(id),coalesce(array_agg(id) filter(where id is not null),'{}') into expected,matched,files from linked;
 if matched<>expected then
  raise exception 'O anexo não pertence ao rascunho e à oficina confirmados.' using errcode='42501';
 end if;
 return files;
end
$$;

create function rm_private.assert_receiving_draft_upload_v1(p_draft uuid,p_actor uuid,p_device uuid,p_office uuid,p_payload jsonb)
returns void language plpgsql set search_path='' as $$
declare customer uuid; project uuid; opened rm_private.receiving_openings; current_draft rm_private.receiving_drafts;
begin
 if p_payload->>'p_receiving_draft_id' is distinct from p_draft::text or p_payload-'p_receiving_draft_id'-'p_operador_id'
   -'p_cliente_id'-'p_projeto_id'-'p_arquivo_nota_fiscal_url'-'p_fotos_recebimento'<>'{}'::jsonb then
  raise exception 'Contexto do anexo de rascunho inválido.' using errcode='22023';
 end if;
 customer:=nullif(p_payload->>'p_cliente_id','')::uuid;
 project:=nullif(p_payload->>'p_projeto_id','')::uuid;
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||p_device||':'||p_actor,45));
 select * into current_draft from rm_private.receiving_drafts where id=p_draft;
 select * into opened from rm_private.receiving_openings where client_submission_id=p_draft;
 if current_draft.id is not null and (current_draft.auth_user_id<>p_device or current_draft.operator_id<>p_actor
   or current_draft.state<>'draft'
   or rm_private.receiving_draft_evidence_workshop_v1(p_draft,current_draft.payload) is distinct from p_office)
  or opened.project_id is null and exists(select 1 from rm_private.receiving_drafts
   where auth_user_id=p_device and operator_id=p_actor and state='draft' and id<>p_draft)
  or opened.project_id is not null and (opened.auth_user_id<>p_device or opened.operator_id<>p_actor
   or not rm_private.workshop_project_owned_v1(opened.project_id,p_office))
  or exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=p_draft)
  or project is not null and not rm_private.workshop_project_owned_v1(project,p_office)
  or customer is not null and not rm_private.workshop_read_visible_v1('client',customer,p_office)
  or current_draft.id is null and opened.project_id is null and customer is null and project is null then
  raise exception 'O rascunho do arquivo não está disponível nesta oficina.' using errcode='42501';
 end if;
end
$$;

create function rm_private.attach_receiving_draft_media_v1(p_submission uuid,p_actor uuid,p_device uuid,p_office uuid,
 p_project uuid,p_payload jsonb) returns void language plpgsql set search_path='' as $$
declare ids uuid[];
begin
 ids:=rm_private.assert_receiving_draft_media_v1(p_submission,p_actor,p_device,p_office,jsonb_build_object(
  'arquivoNotaFiscal',p_payload->>'p_arquivo_nota_fiscal_url',
  'fotos',(select coalesce(jsonb_agg(jsonb_build_object('uri',r.reference)),'[]') from
   rm_private.workshop_receiving_media_refs_v1(null,p_payload->'p_fotos_recebimento','foto_url') r)));
 if p_payload?'p_receiving_draft_snapshot' then
  perform rm_private.assert_receiving_draft_media_v1(p_submission,p_actor,p_device,p_office,p_payload->'p_receiving_draft_snapshot');
 end if;
 if exists(select 1 from rm_private.mobile_workshop_uploads where id=any(ids) and project_id is distinct from p_project
   and (operation<>'receiving_draft' or project_id is not null)) then
  raise exception 'O anexo já está vinculado a outro projeto.' using errcode='42501';
 end if;
 update rm_private.mobile_workshop_uploads set project_id=p_project
 where operation='receiving_draft' and id=any(ids) and project_id is null;
end
$$;

create function rm_private.receiving_draft_media_readable_v1(p_reference text,p_source text,p_office uuid,p_device uuid,p_actor uuid)
returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from rm_private.mobile_workshop_uploads u join rm_private.receiving_drafts d on d.id=u.submission_id
  where u.object_path=rm_private.receiving_private_media_path_v1(p_reference)
   and u.operation in('receiving_draft','rm_submit_recebimento_v1') and u.stored_at is not null
   and u.workshop_id=p_office and u.auth_user_id=p_device and u.operator_id=p_actor
   and d.auth_user_id=p_device and d.operator_id=p_actor and d.state='draft'
   and rm_private.receiving_draft_evidence_workshop_v1(d.id,d.payload)=p_office
   and exists(select 1 from rm_private.workshop_receiving_media_refs_v1(d.payload->>'arquivoNotaFiscal',d.payload->'fotos','uri') f
    where f.reference=p_reference and f.kind=u.kind and p_source=case f.kind when 'document' then 'document' else 'project_photo' end))
$$;

revoke all on function rm_private.workshop_receiving_media_refs_v1(text,jsonb,text),rm_private.receiving_private_media_path_v1(text),
 rm_private.assert_receiving_draft_media_v1(uuid,uuid,uuid,uuid,jsonb),
 rm_private.assert_receiving_draft_upload_v1(uuid,uuid,uuid,uuid,jsonb),
 rm_private.attach_receiving_draft_media_v1(uuid,uuid,uuid,uuid,uuid,jsonb),
 rm_private.receiving_draft_media_readable_v1(text,text,uuid,uuid,uuid) from public,anon,authenticated,service_role;

do $extend$
declare
 reference_guard text:=pg_get_functiondef('rm_private.mobile_workshop_upload_reference_v1(text,jsonb,text,text)'::regprocedure);
 uploader text:=pg_get_functiondef('public.rm_mobile_workshop_upload_v1(uuid,uuid,text,jsonb,uuid,uuid,text,jsonb,uuid,text,text,text,integer,text,boolean)'::regprocedure);
 draft text:=pg_get_functiondef('public.rm_mobile_receiving_draft_workshop_v1(uuid,jsonb,text)'::regprocedure);
 completion text:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 owner_check text:=pg_get_functiondef('rm_private.workshop_stored_media_owned_v1(text,uuid,text)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[])'::regprocedure);
 reference_case constant text:='  when ''rm_submit_recebimento_v1'' then';
 upload_case constant text:=' if p_operation=''rm_submit_recebimento_v1'' then';
 project_lock constant text:=' perform pg_advisory_xact_lock(hashtextextended(project::text,11));';
 start_check constant text:=' if not exists(select 1 from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token)';
 hash_marker constant text:=' payload_hash:=encode(sha256(convert_to(p_payload::text,''UTF8'')),''hex'');';
 prior_row constant text:=' if found and (upload.submission_id';
 save_marker constant text:='  value:=public.rm_receiving_draft_v1(p_operator_token,''save'',draft,snapshot,';
 finish_marker constant text:=' if permit.expires_at<=clock_timestamp() or not exists(';
 owner_marker constant text:='where u.workshop_id=p_workshop and u.stored_at is not null';
 reader_marker constant text:='into files from matches where rm_private.workshop_stored_media_owned_v1(url,office_id,source);';
 old_matches constant text:='select * from photos union select * from answers union select * from documents union select * from draft_files';
begin
 if array_length(string_to_array(reference_guard,reference_case),1) is distinct from 2
 or array_length(string_to_array(uploader,upload_case),1) is distinct from 2
 or array_length(string_to_array(uploader,project_lock),1) is distinct from 2
 or array_length(string_to_array(uploader,start_check),1) is distinct from 2
 or array_length(string_to_array(uploader,hash_marker),1) is distinct from 2
 or array_length(string_to_array(uploader,prior_row),1) is distinct from 2
 or array_length(string_to_array(draft,save_marker),1) is distinct from 2
 or array_length(string_to_array(completion,finish_marker),1) is distinct from 2
 or array_length(string_to_array(owner_check,owner_marker),1) is distinct from 2
 or array_length(string_to_array(reader,reader_marker),1) is distinct from 2
 or array_length(string_to_array(reader,old_matches),1) is distinct from 2 then
  raise exception 'Unexpected receiving media contract';
 end if;
 execute replace(reference_guard,reference_case,$case$  when 'receiving_draft' then
   (p_kind='document' and p_payload->>'p_arquivo_nota_fiscal_url'=p_reference)
   or (p_kind='photo' and exists(select 1 from rm_private.workshop_receiving_media_refs_v1(null,p_payload->'p_fotos_recebimento','foto_url')
    where reference=p_reference))
$case$||reference_case);
 uploader:=replace(uploader,upload_case,$insert$ if p_operation='receiving_draft' then
  perform rm_private.assert_receiving_draft_upload_v1(p_submission,actor_id,p_auth_user_id,office,p_payload);
 elsif p_operation='rm_submit_recebimento_v1' then$insert$);
 uploader:=replace(uploader,project_lock,' if p_operation<>''receiving_draft'' then'||chr(10)||project_lock);
 uploader:=replace(uploader,start_check,' end if;'||chr(10)||start_check);
 uploader:=replace(uploader,hash_marker,$hash$ payload_hash:=encode(sha256(convert_to(case when p_operation='receiving_draft' then
  jsonb_build_array(p_submission,actor_id,p_reference)::text else p_payload::text end,'UTF8')),'hex');$hash$);
 execute replace(uploader,prior_row,$resume$ if upload.id is not null and p_operation='receiving_draft' and upload.operation='rm_submit_recebimento_v1'
  and exists(select 1 from rm_private.receiving_openings o where o.client_submission_id=p_submission
   and o.project_id=upload.project_id and o.auth_user_id=p_auth_user_id and o.operator_id=actor_id
   and rm_private.workshop_project_owned_v1(o.project_id,office)) then
  -- An update can resume an upload reserved by the previous APK.
  p_operation:=upload.operation;
  project:=upload.project_id;
  payload_hash:=upload.intent_sha256;
 end if;
 if upload.id is not null and (upload.submission_id$resume$);
 execute replace(draft,save_marker,$save$  perform rm_private.assert_receiving_draft_media_v1(draft,scope.operator_id,scope.auth_user_id,scope.workshop_id,snapshot);
$save$||save_marker);
 execute replace(completion,finish_marker,$finish$ if p_phase='complete' then
  perform rm_private.attach_receiving_draft_media_v1(p_client_submission_id,actor.operator_id,auth.uid(),permit.workshop_id,
   (result->>'projeto_id')::uuid,p_params);
 end if;
$finish$||finish_marker);
 execute replace(owner_check,owner_marker,owner_marker||' and u.project_id is not null');
 reader:=replace(reader,old_matches,old_matches||$reader$
  union select u.url,s.source from requested u cross join (values('document'),('project_photo')) s(source)
   where rm_private.receiving_draft_media_readable_v1(u.url,s.source,office_id,p_auth_user_id,actor_id)$reader$);
 execute replace(reader,reader_marker,$filter$into files from matches where rm_private.workshop_stored_media_owned_v1(url,office_id,source)
  or rm_private.receiving_draft_media_readable_v1(url,source,office_id,p_auth_user_id,actor_id);$filter$);
end
$extend$;
notify pgrst,'reload schema';
commit;
