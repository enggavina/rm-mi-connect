begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Preserve the legacy collaborator catalog from recorded workshop activity.
-- Imported profiles with no evidence of origin remain stored and unassigned.
create view rm_private.workshop_legacy_bma_people_rows as
select u.id
from public.rm_users u
cross join rm_private.workshop_legacy_adoption b
where b.singleton and rm_private.workshop_mobile_actor_visible_v1(u.id,null,b.legacy_workshop_id)
union
select p.created_by_user_id from public.rm_projetos p
join rm_private.workshop_legacy_bma_projects visible on visible.id=p.id
where p.created_by_user_id is not null;

revoke all on rm_private.workshop_legacy_bma_people_rows from public,anon,authenticated,service_role;

create function rm_private.workshop_legacy_bma_people_ids_v1()
returns setof uuid language sql stable security definer set search_path='' as $$
 select p.id from rm_private.workshop_legacy_bma_people_rows p
 where (select rm_private.workshop_legacy_bma_device_v1());
$$;
revoke all on function rm_private.workshop_legacy_bma_people_ids_v1() from public,anon,authenticated,service_role;
grant execute on function rm_private.workshop_legacy_bma_people_ids_v1() to authenticated;

create function rm_private.activate_workshop_legacy_bma_people_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop-legacy-bma-catalog',119));
 if not exists(select 1 from rm_private.workshop_legacy_catalog_access where singleton)
  or not exists(select 1 from pg_policy where polrelid='public.rm_projetos'::regclass
   and polname='rm_legacy_bma_operations_read' and not polpermissive and polcmd='r') then
  raise exception 'Ative o recorte de operações do dispositivo legado antes do cadastro de pessoas.' using errcode='PT409';
 end if;
 if not exists(select 1 from pg_policy where polrelid='public.rm_users'::regclass and polname='rm_legacy_bma_people_read') then
  create policy rm_legacy_bma_people_read on public.rm_users as restrictive for select to authenticated
   using (auth_user_id=(select auth.uid()) or id in(select rm_private.workshop_legacy_bma_people_ids_v1()));
 end if;
end
$$;
revoke all on function rm_private.activate_workshop_legacy_bma_people_v1() from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;
