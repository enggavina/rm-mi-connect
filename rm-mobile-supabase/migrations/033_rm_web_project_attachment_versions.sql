-- New immutable files form an explicit linear history. No old file or row is replaced.
begin;
create table rm_private.project_attachment_versions (
 id uuid primary key references rm_private.project_attachment_uploads(id) on delete restrict,
 projeto_id uuid not null references public.rm_projetos(id) on delete restrict,
 root_doc_id uuid not null references public.rm_docs(id) on delete restrict,
 replaces_doc_id uuid not null references public.rm_docs(id) on delete restrict,
 revision integer not null check(revision>1),
 auth_user_id uuid not null,
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 reserve_submission_id uuid not null unique,
 expected_project_updated_at timestamptz not null,
 expected_attachment_updated_at timestamptz not null,
 expected_context_version text not null check(expected_context_version ~ '^[a-f0-9]{64}$'),
 motivo text not null check(length(motivo) between 1 and 2000),
 before_record jsonb not null,
 after_record jsonb,
 finalized_doc_id uuid unique references public.rm_docs(id) on delete restrict,
 created_at timestamptz not null default clock_timestamp(),
 completed_at timestamptz,
 check(id<>root_doc_id and id<>replaces_doc_id),
 check(finalized_doc_id is null or finalized_doc_id=id),
 check((finalized_doc_id is null)=(completed_at is null)),
 check((finalized_doc_id is null)=(after_record is null))
);
create unique index project_attachment_published_parent_v1 on rm_private.project_attachment_versions(replaces_doc_id) where finalized_doc_id is not null;
create unique index project_attachment_published_revision_v1 on rm_private.project_attachment_versions(root_doc_id,revision) where finalized_doc_id is not null;
revoke all on rm_private.project_attachment_versions from public,anon,authenticated,service_role;

-- Internal proof only: no client may call a reader exposing these complete rows.
create function rm_private.project_attachment_publication_v1(p_attachment_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d public.rm_docs%rowtype; u rm_private.project_attachment_uploads%rowtype; o storage.objects%rowtype;
 valid boolean; has_file boolean:=false;
 prefix constant text:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/';
begin
 select * into d from public.rm_docs where id=p_attachment_id;
 if not found then return null; end if;
 select * into u from rm_private.project_attachment_uploads where id=d.id and finalized_doc_id=d.id;
 valid:=u.id is not null and u.projeto_id=d.projeto_id and u.completed_at is not null and d.visivel_cliente=false
  and d.created_by=u.actor_id and d.nome=u.nome and d.descricao is not distinct from u.descricao
  and d.tipo_arquivo=u.mime_type and d.status=u.status_documento and d.data_vencimento is not distinct from u.data_vencimento
  and u.object_path='web-dossier/'||d.projeto_id::text||'/'||d.id::text||case u.mime_type when 'application/pdf' then '.pdf' when 'image/jpeg' then '.jpg' else '.png' end
  and d.arquivo_url=prefix||u.object_path;
 valid:=coalesce(valid,false);
 if valid then
  select * into o from storage.objects where bucket_id='rm-documentos' and name=u.object_path;
  if o.id is not null and coalesce(o.metadata->>'size','') ~ '^[0-9]+$' then
   has_file:=(o.metadata->>'size')::numeric=u.byte_size and o.metadata->>'mimetype'=u.mime_type and o.user_metadata->>'sha256'=u.sha256;
  end if;
 end if;
 return jsonb_build_object('valid',valid,'has_file',coalesce(has_file,false),'document',to_jsonb(d),'upload',case when valid then to_jsonb(u) else null end,'object',case when valid then to_jsonb(o) else null end);
end $$;
revoke all on function rm_private.project_attachment_publication_v1(uuid) from public,anon,authenticated,service_role;

create function rm_private.project_attachment_version_context_v1(p_project_id uuid,p_attachment_id uuid,p_history_page integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.rm_projetos%rowtype; d public.rm_docs%rowtype; actor public.rm_users%rowtype;
 proof jsonb; root_proof jsonb; head_proof jsonb; selected_projection jsonb; history jsonb; membership jsonb; selected_token jsonb; head_token jsonb;
 root_id uuid; head_id uuid; selected_revision integer; head_revision integer; published_count integer; page_no integer;
 known boolean:=false; closed boolean; reason text; context_hash text;
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501'; end if;
 if p_history_page is null or p_history_page not between 1 and 100000 then raise exception 'Página do histórico inválida.' using errcode='22023'; end if;
 select * into p from public.rm_projetos where id=p_project_id;
 select * into d from public.rm_docs where id=p_attachment_id and projeto_id=p_project_id;
 if p.id is null or d.id is null then return null; end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 proof:=rm_private.project_attachment_publication_v1(d.id);
 if coalesce((proof->>'valid')::boolean,false) then
  select v.root_doc_id,v.revision into root_id,selected_revision from rm_private.project_attachment_versions v where v.finalized_doc_id=d.id;
  root_id:=coalesce(root_id,d.id); selected_revision:=coalesce(selected_revision,1);
  root_proof:=rm_private.project_attachment_publication_v1(root_id);
  select count(*),coalesce(max(v.revision),1) into published_count,head_revision from rm_private.project_attachment_versions v where v.root_doc_id=root_id and v.finalized_doc_id is not null;
  select v.id into head_id from rm_private.project_attachment_versions v where v.root_doc_id=root_id and v.finalized_doc_id is not null order by v.revision desc limit 1;
  head_id:=coalesce(head_id,root_id);
  head_proof:=rm_private.project_attachment_publication_v1(head_id);
  known:=coalesce((root_proof->>'valid')::boolean,false) and coalesce((head_proof->>'valid')::boolean,false)
   and root_proof->'document'->>'projeto_id'=p.id::text and head_proof->'document'->>'projeto_id'=p.id::text
   and published_count=head_revision-1 and not exists(select 1 from rm_private.project_attachment_versions v
    where v.root_doc_id=root_id and v.finalized_doc_id is not null and (v.projeto_id<>p.id
     or (v.revision=2 and v.replaces_doc_id<>root_id)
     or (v.revision>2 and not exists(select 1 from rm_private.project_attachment_versions previous
      where previous.root_doc_id=root_id and previous.revision=v.revision-1 and previous.finalized_doc_id=v.replaces_doc_id))));
 end if;
 known:=coalesce(known,false);
 select jsonb_build_object('id',d.id,'projeto_id',d.projeto_id,'nome',d.nome,'descricao',d.descricao,'tipo_arquivo',d.tipo_arquivo,'status',d.status,
  'data_vencimento',d.data_vencimento,'created_at',d.created_at,'updated_at',d.updated_at,'created_by',d.created_by,'visivel_cliente',d.visivel_cliente,
  'author_name',u.nome,'author_registration',u.matricula,'has_file',case when (proof->>'valid')::boolean then (proof->>'has_file')::boolean else coalesce(length(d.arquivo_url)>0,false) end,
  'filename',case when (proof->>'valid')::boolean then proof->'upload'->>'filename' else null end,
  'byte_size',case when (proof->>'valid')::boolean then (proof->'upload'->>'byte_size')::integer else null end)
 into selected_projection from (select 1) singleton left join public.rm_users u on u.id=d.created_by;
 closed:=p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false);
 reason:=case when not known then 'Este registro não possui publicação privada comprovada para versionamento. O arquivo permanece disponível para consulta.'
  when d.id<>head_id then 'Esta versão foi substituída. Abra a versão atual para registrar uma nova substituição.'
  when closed then 'Projeto encerrado: somente consulta.'
  when not coalesce((proof->>'has_file')::boolean,false) then 'O arquivo atual está indisponível ou exige conferência antes da substituição.'
  when actor.perfil not in('administrador','padr_o') then 'Seu perfil permite consultar as versões deste anexo.' else null end;
 if known then
  page_no:=least(p_history_page,greatest(1,ceil(head_revision::numeric/25)::integer));
  with members as (
   select root_id id,1 revision,null::text motivo
   union all select v.id,v.revision,v.motivo from rm_private.project_attachment_versions v where v.root_doc_id=root_id and v.finalized_doc_id is not null
  ), windowed as (select * from members order by revision desc limit 25 offset(page_no-1)*25)
  select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'projeto_id',h.projeto_id,'nome',h.nome,'descricao',h.descricao,'tipo_arquivo',h.tipo_arquivo,'status',h.status,
   'data_vencimento',h.data_vencimento,'created_at',h.created_at,'updated_at',h.updated_at,'created_by',h.created_by,'visivel_cliente',h.visivel_cliente,
   'author_name',u.nome,'author_registration',u.matricula,'has_file',coalesce((file->>'has_file')::boolean,false),
   'filename',case when (file->>'valid')::boolean then file->'upload'->>'filename' else null end,
   'byte_size',case when (file->>'valid')::boolean then (file->'upload'->>'byte_size')::integer else null end,
   'revision',w.revision,'motivo',w.motivo,'current',w.id=head_id) order by w.revision desc),'[]') into history
   from windowed w join public.rm_docs h on h.id=w.id and h.projeto_id=p.id left join public.rm_users u on u.id=h.created_by
   cross join lateral (select rm_private.project_attachment_publication_v1(h.id) file) publication;
 else page_no:=1; history:='[]'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'revision',v.revision,'parent',v.replaces_doc_id) order by v.revision),'[]') into membership
  from rm_private.project_attachment_versions v where v.root_doc_id=root_id and v.finalized_doc_id is not null;
 -- Access timestamps and unrelated Storage metadata do not change a file's
 -- publication identity. Bind only the stable object identity/content proof.
 selected_token:=jsonb_build_object('valid',proof->'valid','has_file',proof->'has_file','upload',proof->'upload',
  'object_id',proof->'object'->'id','bucket',proof->'object'->'bucket_id','name',proof->'object'->'name',
  'size',proof->'object'->'metadata'->'size','mime',proof->'object'->'metadata'->'mimetype','sha256',proof->'object'->'user_metadata'->'sha256',
  'generation',proof->'object'->'version','etag',proof->'object'->'metadata'->'eTag','etag_lower',proof->'object'->'metadata'->'etag');
 head_token:=jsonb_build_object('valid',head_proof->'valid','has_file',head_proof->'has_file','upload',head_proof->'upload','document',head_proof->'document',
  'object_id',head_proof->'object'->'id','bucket',head_proof->'object'->'bucket_id','name',head_proof->'object'->'name',
  'size',head_proof->'object'->'metadata'->'size','mime',head_proof->'object'->'metadata'->'mimetype','sha256',head_proof->'object'->'user_metadata'->'sha256',
  'generation',head_proof->'object'->'version','etag',head_proof->'object'->'metadata'->'eTag','etag_lower',head_proof->'object'->'metadata'->'etag');
 context_hash:=encode(sha256(convert_to(jsonb_build_object('project',to_jsonb(p),'selected',to_jsonb(d),'selected_proof',selected_token,
  'root',root_id,'head',head_id,'head_proof',head_token,'membership',membership,'known',known)::text,'UTF8')),'hex');
 return jsonb_build_object('project',jsonb_build_object('id',p.id,'numero',p.numero,'updated_at',p.updated_at,'status_pcp',p.status_pcp,'data_real_de_entrega',p.data_real_de_entrega,'closed',closed),
  'attachment',selected_projection,'series',case when known then jsonb_build_object('root_id',root_id,'head_id',head_id,'head_updated_at',head_proof->'document'->'updated_at','selected_revision',selected_revision,'head_revision',head_revision) else null end,
  'can_replace',reason is null,'reason',reason,'context_version',context_hash,
  'history',jsonb_build_object('items',history,'total',case when known then head_revision else 0 end,'page',page_no,'page_size',25));
end $$;
revoke all on function rm_private.project_attachment_version_context_v1(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function rm_private.project_attachment_version_context_v1(uuid,uuid,integer) to authenticated;

create function public.rm_web_project_attachment_snapshot_v1(p_project_id uuid,p_attachment_id uuid,p_history_page integer default 1)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if not rm_private.can_read_project_dossier_v1() then raise exception 'Consulta restrita à equipe interna.' using errcode='42501'; end if;
 if not exists(select 1 from public.rm_projetos where id=p_project_id)
  or not exists(select 1 from public.rm_docs where id=p_attachment_id and projeto_id=p_project_id) then return null; end if;
 return rm_private.project_attachment_version_context_v1(p_project_id,p_attachment_id,p_history_page);
end $$;
revoke all on function public.rm_web_project_attachment_snapshot_v1(uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_project_attachment_snapshot_v1(uuid,uuid,integer) to authenticated;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_project_comment_core_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype; receipt rm_private.web_mutation_receipts%rowtype; p public.rm_projetos%rowtype;
 source public.rm_docs%rowtype; document public.rm_docs%rowtype; upload rm_private.project_attachment_uploads%rowtype;
 intent rm_private.project_attachment_versions%rowtype; object storage.objects%rowtype;
 project_id uuid; upload_id uuid; source_id uuid; expected_project timestamptz; expected_attachment timestamptz;
 expiry timestamptz; snapshot jsonb; result jsonb; allowed text[]; object_count integer;
 prefix constant text:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-documentos/';
begin
 if p_operation is null or p_operation not in('reserve_project_attachment_version','finalize_project_attachment_version','finalize_project_attachment')
 then return rm_private.web_mutate_project_comment_core_v1(p_client_submission_id,p_operation,p_payload); end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or actor.perfil not in('administrador','padr_o') then raise exception 'Operação restrita à gestão do projeto.' using errcode='42501'; end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and (auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501'; end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio já utilizado.' using errcode='23505'; end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 -- A version reservation shares the immutable Storage namespace, not the old
 -- publication command. The old finalizer must never detach a version intent
 -- from its current-head/project guards. Completed receipts remain above.
 if p_operation='finalize_project_attachment' then
  -- All old finalizers participate, including while a new reservation has not
  -- committed yet. A pre-lock existence check alone would allow a TOCTOU bypass.
  perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,33));
  if exists(select 1 from rm_private.project_attachment_versions v where v.id=p_client_submission_id) then
   raise exception 'Esta reserva pertence a uma substituição versionada. Use o envio original da versão.' using errcode='22023'; end if;
  return rm_private.web_mutate_project_comment_core_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 allowed:=case p_operation when 'reserve_project_attachment_version' then array['upload_id','projeto_id','source_attachment_id','expected_project_updated_at','expected_attachment_updated_at','expected_context_version','nome','descricao','filename','mime_type','byte_size','sha256','data_vencimento','status','motivo','confirm_change'] else array['projeto_id','upload_id'] end;
 if not p_payload ?& allowed or exists(select 1 from jsonb_object_keys(p_payload) k where not k=any(allowed))
  or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string' or jsonb_typeof(p_payload->'upload_id') is distinct from 'string' then raise exception 'Contexto ou campos inválidos.' using errcode='22023'; end if;
 project_id:=(p_payload->>'projeto_id')::uuid; upload_id:=(p_payload->>'upload_id')::uuid;
 if p_operation='reserve_project_attachment_version' then
  if upload_id=p_client_submission_id or jsonb_typeof(p_payload->'source_attachment_id') is distinct from 'string'
   or jsonb_typeof(p_payload->'expected_project_updated_at') is distinct from 'string' or jsonb_typeof(p_payload->'expected_attachment_updated_at') is distinct from 'string'
   or p_payload->>'expected_project_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
   or p_payload->>'expected_attachment_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
   or jsonb_typeof(p_payload->'expected_context_version') is distinct from 'string' or p_payload->>'expected_context_version' !~ '^[a-f0-9]{64}$'
   or p_payload->'confirm_change' is distinct from 'true'::jsonb
   or jsonb_typeof(p_payload->'nome') is distinct from 'string' or length(btrim(p_payload->>'nome')) not between 1 and 200 or p_payload->>'nome' !~ '[^[:space:]]'
   or jsonb_typeof(p_payload->'descricao') not in('string','null') or length(btrim(p_payload->>'descricao'))>2000
   or jsonb_typeof(p_payload->'filename') is distinct from 'string' or length(p_payload->>'filename') not between 1 and 180 or p_payload->>'filename' ~ '[[:cntrl:]/\\]'
   or jsonb_typeof(p_payload->'mime_type') is distinct from 'string' or p_payload->>'mime_type' not in('application/pdf','image/jpeg','image/png')
   or jsonb_typeof(p_payload->'byte_size') is distinct from 'number' or p_payload->>'byte_size' !~ '^[0-9]+$' or (p_payload->>'byte_size')::numeric not between 1 and 20971520
   or jsonb_typeof(p_payload->'sha256') is distinct from 'string' or p_payload->>'sha256' !~ '^[a-f0-9]{64}$'
   or jsonb_typeof(p_payload->'status') is distinct from 'string' or p_payload->>'status' not in('No prazo','Vencido')
   or jsonb_typeof(p_payload->'data_vencimento') not in('string','null')
   or jsonb_typeof(p_payload->'motivo') is distinct from 'string' or length(btrim(p_payload->>'motivo')) not between 1 and 2000 or p_payload->>'motivo' !~ '[^[:space:]]'
  then raise exception 'Confirmação, arquivo ou motivo inválidos. Use PDF, JPEG ou PNG de até 20 MiB.' using errcode='22023'; end if;
  source_id:=(p_payload->>'source_attachment_id')::uuid; expected_project:=(p_payload->>'expected_project_updated_at')::timestamptz; expected_attachment:=(p_payload->>'expected_attachment_updated_at')::timestamptz;
  if not isfinite(expected_project) or not isfinite(expected_attachment) then raise exception 'Versões inválidas.' using errcode='22023'; end if;
  if jsonb_typeof(p_payload->'data_vencimento')='string' then
   if p_payload->>'data_vencimento' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then raise exception 'Vencimento inválido.' using errcode='22023'; end if;
   expiry:=(p_payload->>'data_vencimento')::timestamptz; if not isfinite(expiry) then raise exception 'Vencimento inválido.' using errcode='22023'; end if;
  end if;
 else
  if p_client_submission_id<>upload_id then raise exception 'Use o protocolo original do arquivo.' using errcode='23505'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(upload_id::text,33));
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 select * into p from public.rm_projetos where id=project_id for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002'; end if;
 if p_operation='finalize_project_attachment_version' then
  select * into intent from rm_private.project_attachment_versions where id=upload_id and projeto_id=project_id for update;
  if not found then raise exception 'Reserva de versão inexistente neste projeto.' using errcode='P0002'; end if;
  select * into upload from rm_private.project_attachment_uploads where id=upload_id and projeto_id=project_id for update;
  if upload.id is null or intent.auth_user_id<>auth.uid() or intent.actor_id<>actor.id or upload.auth_user_id<>auth.uid() or upload.actor_id<>actor.id then raise exception 'Reserva vinculada a outra identidade.' using errcode='42501'; end if;
  if intent.finalized_doc_id is not null or upload.finalized_doc_id is not null then raise exception 'Versão já concluída. Repita o protocolo original.' using errcode='23505'; end if;
  source_id:=intent.replaces_doc_id; expected_project:=intent.expected_project_updated_at; expected_attachment:=intent.expected_attachment_updated_at;
 end if;
 select * into source from public.rm_docs where id=source_id and projeto_id=project_id for update;
 if not found then raise exception 'Anexo inexistente neste projeto.' using errcode='P0002'; end if;
 -- Lock the exact previous object before validating the frozen source snapshot.
 -- Other writers cannot change that proof between this read and publication.
 perform 1 from storage.objects o join rm_private.project_attachment_uploads u on u.object_path=o.name and o.bucket_id='rm-documentos'
  where u.finalized_doc_id=source.id for share of o;
 snapshot:=public.rm_web_project_attachment_snapshot_v1(project_id,source_id,1);
 if p.updated_at<>expected_project or source.updated_at<>expected_attachment
  or snapshot->>'context_version' is distinct from (case p_operation when 'reserve_project_attachment_version' then p_payload->>'expected_context_version' else intent.expected_context_version end)
 then raise exception 'O projeto ou a versão atual mudou. Recarregue antes de substituir o anexo.' using errcode='PT409'; end if;
 if not coalesce((snapshot->>'can_replace')::boolean,false) then raise exception '%',snapshot->>'reason' using errcode='42501'; end if;
 if p_operation='reserve_project_attachment_version' then
  if exists(select 1 from rm_private.project_attachment_uploads where id=upload_id) or exists(select 1 from public.rm_docs where id=upload_id) then raise exception 'Identificador do arquivo já utilizado.' using errcode='23505'; end if;
  insert into rm_private.project_attachment_uploads(id,auth_user_id,actor_id,projeto_id,nome,descricao,filename,mime_type,byte_size,sha256,object_path,status_documento,data_vencimento)
   values(upload_id,auth.uid(),actor.id,project_id,btrim(p_payload->>'nome'),nullif(btrim(p_payload->>'descricao'),''),p_payload->>'filename',p_payload->>'mime_type',(p_payload->>'byte_size')::integer,p_payload->>'sha256',
    'web-dossier/'||project_id::text||'/'||upload_id::text||case p_payload->>'mime_type' when 'application/pdf' then '.pdf' when 'image/jpeg' then '.jpg' else '.png' end,p_payload->>'status',expiry) returning * into upload;
  insert into rm_private.project_attachment_versions(id,projeto_id,root_doc_id,replaces_doc_id,revision,auth_user_id,actor_id,reserve_submission_id,expected_project_updated_at,expected_attachment_updated_at,expected_context_version,motivo,before_record)
   values(upload_id,project_id,(snapshot->'series'->>'root_id')::uuid,source.id,(snapshot->'series'->>'head_revision')::integer+1,auth.uid(),actor.id,p_client_submission_id,expected_project,expected_attachment,snapshot->>'context_version',btrim(p_payload->>'motivo'),to_jsonb(source)) returning * into intent;
  result:=jsonb_build_object('operation',p_operation,'id',upload.id,'projeto_id',project_id,'updated_at',upload.created_at,'idempotent_replay',false,
   'record',jsonb_build_object('upload_id',upload.id,'projeto_id',project_id,'path',upload.object_path,'mime_type',upload.mime_type,'byte_size',upload.byte_size,'sha256',upload.sha256,
    'source_attachment_id',source.id,'root_attachment_id',intent.root_doc_id,'revision',intent.revision,'context_version',intent.expected_context_version));
 else
  select count(*) into object_count from storage.objects where bucket_id='rm-documentos' and name=upload.object_path;
  if object_count=0 then raise exception 'O arquivo ainda não foi confirmado. Repita o mesmo envio.' using errcode='PT503'; end if;
  if object_count<>1 then raise exception 'O arquivo exige reconciliação antes de concluir.' using errcode='PT409'; end if;
  select * into object from storage.objects where bucket_id='rm-documentos' and name=upload.object_path for share;
  if coalesce(object.metadata->>'size','') !~ '^[0-9]+$' then raise exception 'O arquivo não corresponde à reserva.' using errcode='PT409'; end if;
  if (object.metadata->>'size')::numeric<>upload.byte_size or object.metadata->>'mimetype' is distinct from upload.mime_type or object.user_metadata->>'sha256' is distinct from upload.sha256 then raise exception 'O arquivo não corresponde à reserva.' using errcode='PT409'; end if;
  insert into public.rm_docs(id,projeto_id,nome,descricao,arquivo_url,tipo_arquivo,visivel_cliente,created_by,status,data_vencimento,sync_source)
   values(upload.id,project_id,upload.nome,upload.descricao,prefix||upload.object_path,upload.mime_type,false,actor.id,upload.status_documento,upload.data_vencimento,'supabase') returning * into document;
  update rm_private.project_attachment_uploads set finalized_doc_id=document.id,completed_at=clock_timestamp() where id=upload.id;
  update rm_private.project_attachment_versions set finalized_doc_id=document.id,after_record=to_jsonb(document),completed_at=clock_timestamp() where id=intent.id;
  snapshot:=public.rm_web_project_attachment_snapshot_v1(project_id,document.id,1);
  result:=jsonb_build_object('operation',p_operation,'id',document.id,'projeto_id',project_id,'updated_at',document.updated_at,'idempotent_replay',false,
   'record',jsonb_build_object('upload_id',upload.id,'projeto_id',project_id,'attachment_id',document.id,'source_attachment_id',source.id,'root_attachment_id',intent.root_doc_id,'revision',intent.revision,
    'nome',document.nome,'descricao',document.descricao,'tipo_arquivo',document.tipo_arquivo,'status',document.status,'data_vencimento',document.data_vencimento,'visivel_cliente',false,'updated_at',document.updated_at,'project_updated_at',p.updated_at,'context_version',snapshot->>'context_version'));
 end if;
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result) values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result);
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 if p_operation in('reserve_project_attachment_version','finalize_project_attachment_version') then raise exception 'Identificador, versão ou arquivo inválidos.' using errcode='22023'; end if; raise;
end $$;

alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check check(operation in(
 'save_project','plan_cell','review_form','save_catalog','delete_catalog','save_engineering','save_photo_title','create_form_template','save_form_template','publish_form_template',
 'transition_stage_approval','save_cell_queue','set_project_photo_selection','delete_photo_title','save_project_route','manage_operational_photos','assign_form_reviewer','manage_stage_rules','manage_cell_availability',
 'add_project_comment','reserve_project_attachment','finalize_project_attachment','save_project_equipment','edit_project_comment','reserve_project_attachment_version','finalize_project_attachment_version'));
do $$ declare definition text; marker text:='when ''edit_project_comment'' then ''em.projects.manage'' end;'; begin
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,marker)=0 then raise exception 'Unexpected attachment version permit map'; end if;
 execute replace(definition,marker,'when ''edit_project_comment'' then ''em.projects.manage'' when ''reserve_project_attachment_version'' then ''em.projects.manage'' when ''finalize_project_attachment_version'' then ''em.projects.manage'' end;');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_project_comment_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
