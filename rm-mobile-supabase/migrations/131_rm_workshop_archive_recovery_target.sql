begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The recovery tool can locate one historical PNG and its existing archive
-- receipt. Upload and confirmation still use the original private archive path.
create function public.rm_workshop_archive_recovery_target_v1(p_workshop uuid,p_project uuid,p_reference_sha256 text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if p_workshop is null or p_project is null or p_reference_sha256 is null or p_reference_sha256 !~ '^[a-f0-9]{64}$' then
  raise exception 'Identificação da recuperação inválida.' using errcode='22023';
 end if;
 select distinct jsonb_build_object('reference',s.reference,'reference_sha256',s.reference_sha256,
  'existing',case when a.reference_sha256 is not null then jsonb_build_object(
   'sha256',a.content_sha256,'size',a.byte_size,'mime',a.mime_type,'path',a.object_path) end) into strict result
 from rm_private.workshop_archive_sources s
 left join rm_private.workshop_archive_files a on a.workshop_id=s.workshop_id and a.reference_sha256=s.reference_sha256
 where s.workshop_id=p_workshop and s.project_id=p_project and s.reference_sha256=p_reference_sha256
  and s.provider='bubble' and split_part(s.reference,'?',1) ~* '\.png$'
  and rm_private.workshop_project_owned_v1(s.project_id,p_workshop);
 return result;
exception when no_data_found then return null;
end
$$;
revoke all on function public.rm_workshop_archive_recovery_target_v1(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.rm_workshop_archive_recovery_target_v1(uuid,uuid,text) to service_role;

notify pgrst,'reload schema';
commit;
