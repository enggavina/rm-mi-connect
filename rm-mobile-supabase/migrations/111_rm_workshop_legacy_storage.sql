begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Keep legacy uploads and retries under the device that created the file.
-- Project and team reads go through the scoped web and mobile signers.
alter policy rm_mobile_documents_read on storage.objects using (
 bucket_id='rm-documentos' and rm_private.is_rm_authenticated()
 and (storage.foldername(name))[1]=auth.uid()::text
);
alter policy rm_mobile_media_select on storage.objects using (
 bucket_id in('rm-fotos','rm-assinaturas') and rm_private.is_rm_authenticated()
 and (storage.foldername(name))[1]=auth.uid()::text
);

create function rm_private.workshop_legacy_media_readiness_v1(p_bucket text)
returns jsonb language plpgsql stable set search_path='' as $$
declare
 public_prefix text;
 authenticated_prefix text;
 result jsonb;
begin
 if p_bucket is null or p_bucket not in('rm-fotos','rm-assinaturas') then
  raise exception 'Armazenamento legado inválido.' using errcode='22023';
 end if;
 public_prefix:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/'||p_bucket||'/';
 authenticated_prefix:='https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/'||p_bucket||'/';

 with catalog as materialized (
  select distinct s.workshop_id,s.reference,s.reference_sha256
  from rm_private.workshop_archive_sources s
  where s.provider='em' and (starts_with(s.reference,public_prefix) or starts_with(s.reference,authenticated_prefix))
 ), confirmed as materialized (
  select s.reference,s.workshop_id,s.reference_sha256
  from catalog s join rm_private.workshop_archive_files a using(workshop_id,reference_sha256)
  join storage.objects copy on copy.id=a.object_id and copy.bucket_id='rm-documentos' and copy.name=a.object_path
  join storage.buckets private on private.id=copy.bucket_id and not private.public
  where copy.metadata->>'size'=a.byte_size::text and copy.metadata->>'mimetype'=a.mime_type
    and copy.user_metadata->>'sha256'=a.content_sha256
 ), referenced as materialized (
  select f.foto_url reference from public.rm_fotos f where not f.lixeira
  union select unnest(f.fotos_arquivos_urls) from public.rm_fotos f where not f.lixeira
  union select unnest(a.fotos_urls||array[a.assinatura_url]) from public.rm_respostas a
  union select d.arquivo_url from public.rm_docs d
  union select d.arquivo_url from public.rm_documentos d
  union select unnest(array[p.arquivo_nota_fiscal_url,p.documento_proposta_url]) from public.rm_projetos p
 ), pending_drafts as (
  select count(*) n from rm_private.receiving_drafts d
  where d.state='draft' and (strpos(d.payload::text,public_prefix)>0 or strpos(d.payload::text,authenticated_prefix)>0)
 )
 select jsonb_build_object('bucket',b.id,'public',b.public,
  'references',(select count(*) from catalog),'verified_copies',(select count(*) from confirmed),
  'uncatalogued_references',(select count(*) from referenced r where
    (starts_with(r.reference,public_prefix) or starts_with(r.reference,authenticated_prefix))
    and not exists(select 1 from catalog s where s.reference=r.reference)),
  'direct_profile_links',(select count(*) from public.rm_users u where
    starts_with(u.foto_url,public_prefix) or starts_with(u.foto_url,authenticated_prefix)),
  'legacy_objects',(select count(*) from storage.objects o where o.bucket_id=b.id),
  'objects_without_confirmed_reference',(select count(*) from storage.objects o where o.bucket_id=b.id
   and not exists(select 1 from confirmed s where s.reference in (public_prefix||o.name,authenticated_prefix||o.name))),
  'pending_drafts',(select n from pending_drafts)
 ) into result from storage.buckets b where b.id=p_bucket;
 return result;
end
$$;

create function rm_private.activate_workshop_legacy_media_v1(p_bucket text)
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
declare evidence jsonb;
begin
 -- Prevent a new legacy upload from passing between the inventory and switch.
 lock table storage.buckets,storage.objects in share row exclusive mode;
 evidence:=rm_private.workshop_legacy_media_readiness_v1(p_bucket);
 if evidence is null or evidence->'references' is distinct from evidence->'verified_copies'
  or evidence->'uncatalogued_references' is distinct from '0'::jsonb
  or evidence->'direct_profile_links' is distinct from '0'::jsonb
  or evidence->'objects_without_confirmed_reference' is distinct from '0'::jsonb
  or evidence->'pending_drafts' is distinct from '0'::jsonb then
  raise exception 'Há arquivos ou rascunhos legados pendentes de conferência.' using errcode='PT409';
 end if;
 update storage.buckets set public=false where id=p_bucket and public;
end
$$;

revoke all on function rm_private.workshop_legacy_media_readiness_v1(text),rm_private.activate_workshop_legacy_media_v1(text)
 from public,anon,authenticated,service_role;
commit;
