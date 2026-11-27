begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create function rm_private.workshop_private_legacy_image_reference_v1(p_reference text)
returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from storage.buckets b where b.id in('rm-fotos','rm-assinaturas') and b.public is false
  and (starts_with(p_reference,'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/'||b.id||'/')
   or starts_with(p_reference,'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/'||b.id||'/')))
$$;

-- Only sign private originals from the established tablet folder. The caller
-- must first resolve the exact project photo or form answer in its workshop.
create function rm_private.workshop_private_legacy_image_path_v1(p_reference text,p_source text,p_office uuid)
returns text language sql stable set search_path='' as $$
 select o.name
 from rm_private.workshop_legacy_catalog_access a
 join rm_private.workshop_legacy_adoption b on b.singleton and b.legacy_workshop_id=a.workshop_id
 join storage.buckets bucket on bucket.id=case p_source
  when 'project_photo' then 'rm-fotos' when 'answer_photo' then 'rm-fotos' when 'answer_signature' then 'rm-assinaturas' end
  and bucket.public is false
 join storage.objects o on o.bucket_id=bucket.id and o.name=split_part(p_reference,'/'||bucket.id||'/',2)
 where a.singleton and a.workshop_id=p_office and o.owner_id=a.auth_user_id::text
  and o.archived_at is null and not o.is_delete_marker and nullif(o.version,'') is not null
  and (a.revoked_at is null or o.updated_at<=a.revoked_at)
  and o.name=a.auth_user_id::text||'/'||split_part(o.name,'/',2)
  and split_part(o.name,'/',2) ~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}\.(jpg|png)$'
  and p_reference in('https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/'||bucket.id||'/'||o.name,
   'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/'||bucket.id||'/'||o.name)
  and case when p_source='answer_signature' then right(o.name,4)='.png' and o.metadata->>'mimetype'='image/png'
           when right(o.name,4)='.png' then o.metadata->>'mimetype'='image/png'
           else o.metadata->>'mimetype'='image/jpeg' end
  and case when o.metadata->>'size' ~ '^[1-9][0-9]{0,7}$' then (o.metadata->>'size')::int<=15728640 else false end
$$;
revoke all on function rm_private.workshop_private_legacy_image_path_v1(text,text,uuid) from public,anon,authenticated,service_role;
revoke all on function rm_private.workshop_private_legacy_image_reference_v1(text) from public,anon,authenticated,service_role;

do $readers$
declare
 definition text:=pg_get_functiondef('rm_private.workshop_media_reference_v1(jsonb,uuid)'::regprocedure);
 android text:=pg_get_functiondef('public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[])'::regprocedure);
 marker constant text:=' return result||rm_private.workshop_archive_link_v1(result->>''file'',p_office);';
 android_marker constant text:='into files from matches where rm_private.workshop_stored_media_owned_v1(url,office_id,source);';
begin
 if array_length(string_to_array(definition,marker),1) is distinct from 2
  or array_length(string_to_array(android,android_marker),1) is distinct from 2 then
  raise exception 'Unexpected legacy image read boundary';
 end if;
 execute replace(definition,marker,$replacement$ result:=result||rm_private.workshop_archive_link_v1(result->>'file',p_office);
 if not (result?'archive_path') and rm_private.workshop_private_legacy_image_reference_v1(result->>'file') then
  result:=result||jsonb_strip_nulls(jsonb_build_object('private_legacy_image_path',
   rm_private.workshop_private_legacy_image_path_v1(result->>'file',source,p_office)));
  if not (result?'private_legacy_image_path') then result:=result||'{"file":null}'::jsonb;end if;
 end if;
 return result;$replacement$);
 execute replace(android,android_marker,$native$into files from matches where rm_private.workshop_stored_media_owned_v1(url,office_id,source)
  and (not rm_private.workshop_private_legacy_image_reference_v1(url)
   or rm_private.workshop_archive_link_v1(url,office_id)?'archive_path'
   or rm_private.workshop_private_legacy_image_path_v1(url,source,office_id) is not null);$native$);
end
$readers$;

notify pgrst,'reload schema';
commit;
