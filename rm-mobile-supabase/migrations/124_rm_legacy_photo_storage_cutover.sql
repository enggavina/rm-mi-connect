begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The original client policy still requires the account's own folder. This
-- adds the previously confirmed BMA device and the private bucket as guards.
create function rm_private.workshop_legacy_photo_storage_allowed_v1()
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from storage.buckets where id='rm-fotos' and public is false)
  and rm_private.workshop_legacy_bma_device_v1();
$$;
revoke all on function rm_private.workshop_legacy_photo_storage_allowed_v1() from public,anon,authenticated,service_role;
grant execute on function rm_private.workshop_legacy_photo_storage_allowed_v1() to authenticated;

create function rm_private.prepare_workshop_legacy_photo_cutover_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 if not exists(select 1 from rm_private.workshop_legacy_mobile_write_settings where singleton) then
  raise exception 'Ative o recorte de gravações móveis antes de trocar a visibilidade das fotos.' using errcode='PT409';
 end if;
 -- Serialize the check and policy installation with Storage writes. The
 -- Storage API updates bucket visibility separately after this commits.
 lock table storage.objects in share row exclusive mode;
 if exists(select 1 from pg_policy where polrelid='storage.objects'::regclass
   and polname='rm_legacy_photo_private_device' and not polpermissive and polcmd='*') then return;end if;
 perform rm_private.assert_workshop_legacy_media_ready_v1('rm-fotos');
 create policy rm_legacy_photo_private_device on storage.objects as restrictive for all to authenticated
  using(bucket_id is distinct from 'rm-fotos' or (select rm_private.workshop_legacy_photo_storage_allowed_v1()))
  with check(bucket_id is distinct from 'rm-fotos' or (select rm_private.workshop_legacy_photo_storage_allowed_v1()));
end
$$;
revoke all on function rm_private.prepare_workshop_legacy_photo_cutover_v1() from public,anon,authenticated,service_role;

commit;
