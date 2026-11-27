begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create or replace function rm_private.require_new_workshop_root_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 all_writers_guarded boolean;
 office uuid;
 kind text;
begin
 select activated_at is not null into strict all_writers_guarded
 from rm_private.workshop_root_enforcement where singleton for share;

 -- Direct imports and other privileged writers must supply origin now.
 -- End-user RPCs retain the existing receiving transition until pilot acceptance.
 if not all_writers_guarded and auth.uid() is not null and auth.jwt()->>'role'='authenticated' then
  return null;
 end if;
 if tg_table_schema<>'public' or tg_table_name not in('rm_projetos','rm_celulas') then
  raise exception 'Origem operacional desconhecida.' using errcode='42501';
 end if;
 if tg_table_name='rm_projetos' then
  kind:='project';
  if not exists(select 1 from public.rm_projetos where id=new.id) then return null; end if;
  select workshop_id into office from rm_private.workshop_project_ownership where id=new.id;
 else
  kind:='cell';
  if not exists(select 1 from public.rm_celulas where id=new.id) then return null; end if;
  select workshop_id into office from rm_private.workshop_cell_ownership where cell_id=new.id;
 end if;
 if office is null then
  raise exception 'A oficina de origem precisa ser confirmada antes de criar o registro. Preserve o protocolo para nova tentativa.'
   using errcode='PT409';
 end if;
 perform rm_private.workshop_assert_origin_v1(kind,new.id,office);
 return null;
end
$$;

create function rm_private.activate_workshop_direct_root_enforcement_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 lock table public.rm_celulas,public.rm_projetos in share row exclusive mode;
 if not exists(select 1 from rm_private.root_creation_settings where singleton and deployment_id is not null) then
  raise exception 'Ative primeiro a criação por oficina no portal.' using errcode='PT409';
 end if;
 alter table public.rm_projetos enable trigger workshop_new_project_origin;
 alter table public.rm_celulas enable trigger workshop_new_cell_origin;
end
$$;
revoke all on function rm_private.activate_workshop_direct_root_enforcement_v1() from public,anon,authenticated,service_role;

commit;
