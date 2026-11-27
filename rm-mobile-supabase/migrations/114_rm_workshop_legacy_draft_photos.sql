begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The draft, current file owner, storage namespace and independent office
-- evidence must agree. Registering a copy never grants the device or operator access.
create view rm_private.workshop_legacy_draft_photos as
with candidates as materialized (
select distinct d.id draft_id,d.auth_user_id,d.operator_id,scope.workshop_id,photo.reference,o.id object_id,o.name
from rm_private.receiving_drafts d
cross join lateral (select rm_private.receiving_draft_evidence_workshop_v1(d.id,d.payload) workshop_id) scope
cross join lateral jsonb_array_elements(case when jsonb_typeof(d.payload->'fotos')='array' then d.payload->'fotos' else '[]'::jsonb end) f
cross join lateral (select coalesce(f->>'uri',case when jsonb_typeof(f)='string' then f#>>'{}' end) reference) photo
join storage.objects o on o.bucket_id='rm-fotos' and o.owner_id=d.auth_user_id::text
 and o.name=d.auth_user_id::text||'/'||split_part(o.name,'/',2) and split_part(o.name,'/',2)~*'^[a-z0-9_-]+\.(jpe?g|png|webp)$'
 and photo.reference in(
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||o.name,
  'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-fotos/'||o.name)
where d.state='draft' and scope.workshop_id is not null
)
select d.draft_id,d.auth_user_id,d.operator_id,d.workshop_id,d.reference from candidates d
where not exists(select 1 from candidates other where other.object_id=d.object_id and other.workshop_id<>d.workshop_id)
 and not exists(select 1 from rm_private.workshop_archive_files a
  where a.workshop_id<>d.workshop_id and a.reference_sha256 in(
   encode(sha256(convert_to('https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||d.name,'UTF8')),'hex'),
   encode(sha256(convert_to('https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/authenticated/rm-fotos/'||d.name,'UTF8')),'hex')));
revoke all on rm_private.workshop_legacy_draft_photos from public,anon,authenticated,service_role;

do $extend$
declare
 sources text:=rtrim(pg_get_viewdef('rm_private.workshop_archive_sources'::regclass),E';\r\n ');
 media text:=pg_get_functiondef('public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[])'::regprocedure);
 readiness text:=pg_get_functiondef('rm_private.workshop_legacy_media_readiness_v1(text)'::regprocedure);
 media_marker constant text:=$original$u.url like 'https://ellpxfbsrbhblyizvbbk.supabase.co/storage/v1/object/public/rm-fotos/'||p_auth_user_id::text||'/%'$original$;
 readiness_marker constant text:=$original$(strpos(d.payload::text,public_prefix)>0 or strpos(d.payload::text,authenticated_prefix)>0)$original$;
begin
 if array_length(string_to_array(media,media_marker),1) is distinct from 2
  or array_length(string_to_array(readiness,readiness_marker),1) is distinct from 2 then
  raise exception 'Unexpected legacy draft photo contract';
 end if;
 execute 'create or replace view rm_private.workshop_archive_sources as select * from ('||sources||$draft$) project_sources
  union all
  select d.workshop_id,null::uuid,d.reference,encode(sha256(convert_to(d.reference,'UTF8')),'hex'),'em'
   from rm_private.workshop_legacy_draft_photos d$draft$;
 execute replace(media,media_marker,$allowed$exists(select 1 from rm_private.workshop_legacy_draft_photos l
     where l.reference=u.url and l.auth_user_id=p_auth_user_id and l.operator_id=actor_id and l.workshop_id=office_id)$allowed$);
 execute replace(readiness,readiness_marker,$pending$exists(
   select 1 from jsonb_path_query(d.payload,'strict $.** ? (@.type() == "string")') part
   cross join lateral (select part#>>'{}' reference) value
   where (starts_with(value.reference,public_prefix) or starts_with(value.reference,authenticated_prefix))
    and not exists(select 1 from rm_private.workshop_legacy_draft_photos legacy join confirmed copy
     on copy.reference=legacy.reference and copy.workshop_id=legacy.workshop_id
     where legacy.draft_id=d.id and legacy.reference=value.reference)
  )$pending$);
end
$extend$;

notify pgrst,'reload schema';
commit;
