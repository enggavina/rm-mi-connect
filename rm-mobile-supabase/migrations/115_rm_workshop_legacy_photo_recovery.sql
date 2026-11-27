begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Recovery custody records the original Storage owner and version. These files
-- never enter a project's archive or a workshop's media routes.
create table rm_private.workshop_legacy_photo_recovery (
 source_id uuid not null,
 source_version text not null,
 source_path text not null,
 owner_auth_user_id uuid not null,
 copy_id uuid not null,
 copy_version text not null,
 copy_path text not null,
 content_sha256 text not null check(content_sha256 ~ '^[a-f0-9]{64}$'),
 mime_type text not null check(mime_type in('image/jpeg','image/png','image/webp')),
 byte_size integer not null check(byte_size between 1 and 15728640),
 verified_at timestamptz not null default clock_timestamp(),
 primary key(source_id,source_version)
);
alter table rm_private.workshop_legacy_photo_recovery enable row level security;
revoke all on rm_private.workshop_legacy_photo_recovery from public,anon,authenticated,service_role;

create policy rm_workshop_photo_recovery_private on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id is distinct from 'rm-documentos' or not starts_with(name,'recuperacao-fotos-legadas/'))
 with check(bucket_id is distinct from 'rm-documentos' or not starts_with(name,'recuperacao-fotos-legadas/'));

create view rm_private.workshop_legacy_photo_recovery_candidates as
with originals as materialized (
 select o.id,o.version,o.name,u.id owner_auth_user_id,o.metadata->>'mimetype' mime_type,
  case when o.metadata->>'size' ~ '^[1-9][0-9]{0,7}$' then (o.metadata->>'size')::integer end byte_size,
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||o.name public_url,
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-fotos/'||o.name private_url
 from storage.objects o join auth.users u on u.id::text=o.owner_id
 where o.bucket_id='rm-fotos' and o.archived_at is null and not o.is_delete_marker and nullif(o.version,'') is not null
  and o.name=u.id::text||'/'||split_part(o.name,'/',2) and split_part(o.name,'/',2)~*'^[a-z0-9_-]+\.(jpe?g|png|webp)$'
  and exists(select 1 from public.rm_users profile where profile.auth_user_id=u.id)
), unassigned as materialized (
 select o.* from originals o where o.byte_size between 1 and 15728640 and o.mime_type in('image/jpeg','image/png','image/webp')
 and not exists(select 1 from rm_private.workshop_archive_sources s where s.provider='em' and s.reference in(o.public_url,o.private_url))
 and not exists(select 1 from rm_private.workshop_archive_files f where f.reference_sha256 in(
  encode(sha256(convert_to(o.public_url,'UTF8')),'hex'),encode(sha256(convert_to(o.private_url,'UTF8')),'hex')))
)
select o.id,o.version,o.name,o.owner_auth_user_id,o.mime_type,o.byte_size from unassigned o
where not exists(select 1 from public.rm_fotos f where strpos(f.foto_url,o.name)>0 or strpos(f.fotos_arquivos_urls::text,o.name)>0)
 and not exists(select 1 from public.rm_respostas r where strpos(r.fotos_urls::text,o.name)>0 or strpos(r.assinatura_url,o.name)>0)
 and not exists(select 1 from public.rm_docs d where strpos(d.arquivo_url,o.name)>0)
 and not exists(select 1 from public.rm_documentos d where strpos(d.arquivo_url,o.name)>0)
 and not exists(select 1 from public.rm_projetos p where strpos(p.arquivo_nota_fiscal_url,o.name)>0 or strpos(p.documento_proposta_url,o.name)>0)
 and not exists(select 1 from public.rm_users u where strpos(u.foto_url,o.name)>0)
 and not exists(select 1 from rm_private.receiving_drafts d where strpos(d.payload::text,o.name)>0)
 and not exists(select 1 from rm_private.mobile_mutation_receipts m where strpos(m.params::text,o.name)>0 or strpos(m.result::text,o.name)>0);
revoke all on rm_private.workshop_legacy_photo_recovery_candidates from public,anon,authenticated,service_role;

create view rm_private.workshop_legacy_photos_preserved as
select o.id from rm_private.workshop_legacy_photo_recovery_candidates o
 join rm_private.workshop_legacy_photo_recovery r on r.source_id=o.id and r.source_version=o.version
  and r.source_path=o.name and r.owner_auth_user_id=o.owner_auth_user_id and r.mime_type=o.mime_type and r.byte_size=o.byte_size
 join storage.objects copy on copy.id=r.copy_id and copy.version=r.copy_version and copy.bucket_id='rm-documentos' and copy.name=r.copy_path
  and copy.archived_at is null and not copy.is_delete_marker
 join storage.buckets b on b.id=copy.bucket_id and b.public is false
where copy.metadata->>'size'=r.byte_size::text and copy.metadata->>'mimetype'=r.mime_type
 and copy.user_metadata->>'sha256'=r.content_sha256;
revoke all on rm_private.workshop_legacy_photos_preserved from public,anon,authenticated,service_role;

create function public.rm_workshop_legacy_photo_recovery_target_v1(p_object uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('path',o.name,'version',o.version,'mime',o.mime_type,'size',o.byte_size)
 from rm_private.workshop_legacy_photo_recovery_candidates o where o.id=p_object
$$;

create function public.rm_confirm_workshop_legacy_photo_recovery_v1(p_object uuid,p_source_version text,p_content_sha256 text)
returns text language plpgsql security definer set search_path='' as $$
declare
 source rm_private.workshop_legacy_photo_recovery_candidates%rowtype;
 target_path text;
 target_id uuid;
 target_version text;
begin
 if p_object is null or nullif(p_source_version,'') is null or p_content_sha256 is null or p_content_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Identificador de recuperação inválido.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('legacy-photo-recovery:'||p_object::text,0));
 perform 1 from storage.objects o where o.id=p_object and o.version=p_source_version for share;
 select * into source from rm_private.workshop_legacy_photo_recovery_candidates o where o.id=p_object and o.version=p_source_version;
 if not found then raise exception 'A origem da foto legada mudou ou possui vínculo operacional.' using errcode='PT409'; end if;

 target_path:='recuperacao-fotos-legadas/'||source.id::text||'/'||p_content_sha256||'.'||
  case source.mime_type when 'image/jpeg' then 'jpg' when 'image/png' then 'png' else 'webp' end;
 select o.id,o.version into target_id,target_version from storage.objects o join storage.buckets b on b.id=o.bucket_id
 where o.bucket_id='rm-documentos' and b.public is false and o.name=target_path and nullif(o.version,'') is not null
  and o.archived_at is null and not o.is_delete_marker and o.metadata->>'size'=source.byte_size::text
  and o.metadata->>'mimetype'=source.mime_type and o.user_metadata->>'sha256'=p_content_sha256
 for share of o;
 if not found then raise exception 'A cópia privada ainda não foi conferida.' using errcode='PT409'; end if;

 insert into rm_private.workshop_legacy_photo_recovery(source_id,source_version,source_path,owner_auth_user_id,
  copy_id,copy_version,copy_path,content_sha256,mime_type,byte_size)
 values(source.id,source.version,source.name,source.owner_auth_user_id,target_id,target_version,target_path,
  p_content_sha256,source.mime_type,source.byte_size) on conflict(source_id,source_version) do nothing;
 if not exists(select 1 from rm_private.workshop_legacy_photo_recovery r
  where (r.source_id,r.source_version,r.source_path,r.owner_auth_user_id,r.copy_id,r.copy_version,r.copy_path,
      r.content_sha256,r.mime_type,r.byte_size)=(source.id,source.version,source.name,source.owner_auth_user_id,
      target_id,target_version,target_path,p_content_sha256,source.mime_type,source.byte_size)) then
  raise exception 'O comprovante de recuperação diverge da versão verificada.' using errcode='PT409';
 end if;
 return target_path;
end
$$;
revoke all on function public.rm_workshop_legacy_photo_recovery_target_v1(uuid),
 public.rm_confirm_workshop_legacy_photo_recovery_v1(uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.rm_workshop_legacy_photo_recovery_target_v1(uuid),
 public.rm_confirm_workshop_legacy_photo_recovery_v1(uuid,text,text) to service_role;

-- Keep the operational reference counts separate from owner-only custody.
do $extend$
declare
 readiness text:=pg_get_functiondef('rm_private.workshop_legacy_media_readiness_v1(text)'::regprocedure);
 checklist text:=pg_get_functiondef('rm_private.assert_workshop_legacy_media_ready_v1(text)'::regprocedure);
 counts_marker constant text:=$old$  'pending_drafts',(select n from pending_drafts)$old$;
 guard_marker constant text:=$old$evidence->'objects_without_confirmed_reference' is distinct from '0'::jsonb$old$;
begin
 if array_length(string_to_array(readiness,counts_marker),1) is distinct from 2
  or array_length(string_to_array(checklist,guard_marker),1) is distinct from 2 then
  raise exception 'Unexpected legacy storage readiness contract';
 end if;
 execute replace(readiness,counts_marker,$counts$  'pending_drafts',(select n from pending_drafts),
  'preserved_without_workshop',case when b.id='rm-fotos' then (select count(*) from rm_private.workshop_legacy_photos_preserved) else 0 end,
  'objects_without_verified_preservation',(select count(*) from storage.objects o where o.bucket_id=b.id
   and not exists(select 1 from confirmed s where s.reference in(public_prefix||o.name,authenticated_prefix||o.name))
   and not (b.id='rm-fotos' and exists(select 1 from rm_private.workshop_legacy_photos_preserved copy where copy.id=o.id)))$counts$);
 execute replace(checklist,guard_marker,$guard$evidence->'objects_without_verified_preservation' is distinct from '0'::jsonb$guard$);
end
$extend$;

notify pgrst,'reload schema';
commit;
