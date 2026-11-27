begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The captured reference remains stable for catalog rows and offline caches.
create table rm_private.workshop_archive_files (
 workshop_id uuid not null references rm_private.workshop_references(id),
 reference_sha256 text not null check(reference_sha256 ~ '^[a-f0-9]{64}$'),
 content_sha256 text not null check(content_sha256 ~ '^[a-f0-9]{64}$'),
 mime_type text not null check(mime_type in('application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif')),
 byte_size integer not null check(byte_size between 1 and 52428800),
 object_id uuid not null,
 object_path text unique not null,
 confirmed_at timestamptz not null default clock_timestamp(),
 primary key(workshop_id,reference_sha256),
 check(object_path like 'acervo-oficina/'||workshop_id::text||'/'||reference_sha256||'.%')
);
alter table rm_private.workshop_archive_files enable row level security;
revoke all on rm_private.workshop_archive_files from public,anon,authenticated,service_role;

create policy rm_workshop_archive_private on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id is distinct from 'rm-documentos' or name not like 'acervo-oficina/%')
 with check(bucket_id is distinct from 'rm-documentos' or name not like 'acervo-oficina/%');
update storage.buckets b set allowed_mime_types=(select array_agg(distinct m order by m)
 from unnest(b.allowed_mime_types||array['image/webp','image/heic','image/heif']) m)
 where b.id='rm-documentos' and not b.public and b.allowed_mime_types is not null
  and not b.allowed_mime_types @> array['image/webp','image/heic','image/heif'];

create view rm_private.workshop_archive_sources as
 with candidate as (
  select o.workshop_id,p.projeto_id project_id,p.foto_url reference
  from public.rm_fotos p join rm_private.workshop_project_ownership o on o.id=p.projeto_id
  where not p.lixeira and rm_private.workshop_media_reference_v1(jsonb_build_object('id',p.id,'source','project_photo'),o.workshop_id) is not null
  union all
  select o.workshop_id,r.projeto_id,f.reference
  from public.rm_respostas a join public.rm_registros_formulario r on r.id=a.registro_formulario_id
  join rm_private.workshop_project_ownership o on o.id=r.projeto_id
  cross join lateral unnest(a.fotos_urls||array[a.assinatura_url]) f(reference)
  where rm_private.workshop_form_record_owned_v1(r.projeto_id,r.celula_id,r.form_id,o.workshop_id)
  union all
  select o.workshop_id,d.projeto_id,d.arquivo_url from public.rm_documentos d join rm_private.workshop_project_ownership o on o.id=d.projeto_id
  union all
  select o.workshop_id,d.projeto_id,d.arquivo_url from public.rm_docs d join rm_private.workshop_project_ownership o on o.id=d.projeto_id
  union all
  select o.workshop_id,p.id,f.reference from public.rm_projetos p join rm_private.workshop_project_ownership o on o.id=p.id
  cross join lateral unnest(array[p.arquivo_nota_fiscal_url,p.documento_proposta_url]) f(reference)
 )
 select c.*,encode(sha256(convert_to(c.reference,'UTF8')),'hex') reference_sha256,
  case when c.reference like 'https://ellpxfbsrbhblyizvbbk.supabase.co/%' then 'em' else 'bubble' end provider
 from candidate c
 where length(c.reference) between 9 and 2048 and c.reference !~ '[[:space:][:cntrl:]#]'
 and (c.reference ~ '^https://[a-zA-Z0-9.-]+\.cdn\.bubble\.io/[^/]'
  or c.reference ~ '^https://ellpxfbsrbhblyizvbbk\.supabase\.co/storage/v1/object/(public/rm-(fotos|assinaturas|documentos)|authenticated/rm-documentos)/[^/?]+(/[^?]*)?$'
   and c.reference !~ '/rm-documentos/(acervo-oficina|mobile-oficina|web-dossier)/');
revoke all on rm_private.workshop_archive_sources from public,anon,authenticated,service_role;

create function public.rm_workshop_archive_queue_v1(p_workshop uuid,p_provider text,p_project uuid,p_after text,p_limit integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_workshop is null or p_provider is null or p_provider not in('em','bubble')
  or p_after is not null and p_after !~ '^[a-f0-9]{64}$' or p_limit is null or p_limit not between 1 and 100 then
  raise exception 'Lote de acervo inválido.' using errcode='22023';
 end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.reference_sha256) from (
  select distinct s.reference,s.reference_sha256 from rm_private.workshop_archive_sources s
  where s.workshop_id=p_workshop and s.provider=p_provider and (p_project is null or s.project_id=p_project)
   and (p_after is null or s.reference_sha256>p_after)
   and not exists(select 1 from rm_private.workshop_archive_files a where a.workshop_id=p_workshop and a.reference_sha256=s.reference_sha256)
  order by s.reference_sha256 limit p_limit
 ) q),'[]'::jsonb);
end
$$;

create function public.rm_confirm_workshop_archive_v1(p_workshop uuid,p_reference text,p_content_sha256 text,p_mime text,p_size integer)
returns text language plpgsql security definer set search_path='' as $$
declare
 ref_sha text;
 extension text:=case p_mime when 'application/pdf' then 'pdf' when 'image/jpeg' then 'jpg' when 'image/png' then 'png'
  when 'image/webp' then 'webp' when 'image/heic' then 'heic' when 'image/heif' then 'heif' end;
 path text;
 target record;
 archive rm_private.workshop_archive_files;
begin
 if p_workshop is null or p_reference is null or length(p_reference) not between 9 and 2048
  or p_content_sha256 is null or p_content_sha256 !~ '^[a-f0-9]{64}$' or extension is null
  or p_size is null or p_size not between 1 and 52428800 then
  raise exception 'Prova de acervo inválida.' using errcode='22023';
 end if;
 if not exists(select 1 from rm_private.workshop_archive_sources s where s.workshop_id=p_workshop and s.reference=p_reference) then
  raise exception 'Arquivo sem origem comprovada na oficina.' using errcode='42501';
 end if;
 ref_sha:=encode(sha256(convert_to(p_reference,'UTF8')),'hex');
 path:='acervo-oficina/'||p_workshop::text||'/'||ref_sha||'.'||extension;
 select o.id,o.metadata,o.user_metadata into target from storage.objects o join storage.buckets b on b.id=o.bucket_id
 where b.id='rm-documentos' and b.public is false and o.name=path for share of o;
 if target.id is null or target.metadata->>'size' is distinct from p_size::text
  or target.metadata->>'mimetype' is distinct from p_mime
  or target.user_metadata->>'sha256' is distinct from p_content_sha256 then
  raise exception 'Cópia privada não confirmada.' using errcode='PT409';
 end if;
 insert into rm_private.workshop_archive_files(workshop_id,reference_sha256,content_sha256,mime_type,byte_size,object_id,object_path)
 values(p_workshop,ref_sha,p_content_sha256,p_mime,p_size,target.id,path) on conflict(workshop_id,reference_sha256) do nothing;
 select * into strict archive from rm_private.workshop_archive_files a where a.workshop_id=p_workshop and a.reference_sha256=ref_sha;
 if (archive.object_id,archive.object_path,archive.content_sha256,archive.mime_type,archive.byte_size)
  is distinct from (target.id,path,p_content_sha256,p_mime,p_size) then
  raise exception 'A cópia confirmada não corresponde ao arquivo original.' using errcode='PT409';
 end if;
 return archive.object_path;
end
$$;
revoke all on function public.rm_workshop_archive_queue_v1(uuid,text,uuid,text,integer),
 public.rm_confirm_workshop_archive_v1(uuid,text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.rm_workshop_archive_queue_v1(uuid,text,uuid,text,integer),
 public.rm_confirm_workshop_archive_v1(uuid,text,text,text,integer) to service_role;

create function rm_private.workshop_archive_link_v1(p_reference text,p_workshop uuid) returns jsonb
language sql stable set search_path='' as $$
 select coalesce((select jsonb_build_object('archive_path',a.object_path) from rm_private.workshop_archive_files a
  where a.workshop_id=p_workshop and a.reference_sha256=encode(sha256(convert_to(p_reference,'UTF8')),'hex')),'{}'::jsonb)
$$;
revoke all on function rm_private.workshop_archive_link_v1(text,uuid) from public,anon,authenticated,service_role;

do $readers$
declare
 native text:=pg_get_functiondef('public.rm_mobile_workshop_media_v1(uuid,uuid,text,jsonb,text[])'::regprocedure);
 media text:=pg_get_functiondef('rm_private.workshop_media_reference_v1(jsonb,uuid)'::regprocedure);
 docs text:=pg_get_functiondef('rm_private.workshop_project_link_v1(text,jsonb,uuid)'::regprocedure);
 mobile_marker constant text:='jsonb_build_object(''url'',url,''source'',source) order by url,source';
 web_marker constant text:=' return result;';
begin
 if array_length(string_to_array(native,mobile_marker),1) is distinct from 2
  or array_length(string_to_array(media,web_marker),1) is distinct from 2
  or array_length(string_to_array(docs,web_marker),1) is distinct from 2 then
  raise exception 'Unexpected workshop archive read contract';
 end if;
 execute replace(native,mobile_marker,'jsonb_build_object(''url'',url,''source'',source)||rm_private.workshop_archive_link_v1(url,office_id) order by url,source');
 execute replace(media,web_marker,' return result||rm_private.workshop_archive_link_v1(result->>''file'',p_office);');
 execute replace(docs,web_marker,' return result||rm_private.workshop_archive_link_v1(result->>''file'',p_office);');
end
$readers$;
notify pgrst,'reload schema';
commit;
