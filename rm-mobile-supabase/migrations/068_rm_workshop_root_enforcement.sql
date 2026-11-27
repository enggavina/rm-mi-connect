begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- The first adoption receipt remains an immutable snapshot of BMA, BRJ and
-- BBH. Future reference codes follow the authority's contract.
alter table rm_private.workshop_references drop constraint workshop_references_code_check;
alter table rm_private.workshop_references add constraint workshop_references_code_check
 check(code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$');

create table rm_private.workshop_root_enforcement (
 singleton boolean primary key default true check(singleton),
 activated_at timestamptz,
 activated_by text
);
insert into rm_private.workshop_root_enforcement(singleton) values(true);
alter table rm_private.workshop_root_enforcement enable row level security;
revoke all on rm_private.workshop_root_enforcement from public,anon,authenticated,service_role;

create function rm_private.require_new_workshop_root_v1()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 guarded boolean;
 office uuid;
 kind text;
begin
 select activated_at is not null into guarded from rm_private.workshop_root_enforcement where singleton for share;
 if guarded is false then return null; end if;
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
revoke all on function rm_private.require_new_workshop_root_v1() from public,anon,authenticated,service_role;

create constraint trigger workshop_new_project_origin
after insert on public.rm_projetos deferrable initially deferred for each row
execute function rm_private.require_new_workshop_root_v1();
create constraint trigger workshop_new_cell_origin
after insert on public.rm_celulas deferrable initially deferred for each row
execute function rm_private.require_new_workshop_root_v1();
alter table public.rm_projetos disable trigger workshop_new_project_origin;
alter table public.rm_celulas disable trigger workshop_new_cell_origin;

-- This separate switch is used only after the receiving pilot and the review
-- of the remaining writers. It cannot assign workshop ownership retroactively.
create function rm_private.activate_workshop_root_enforcement_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
declare
 active timestamptz;
begin
 lock table public.rm_celulas,public.rm_projetos in share row exclusive mode;
 select activated_at into strict active from rm_private.workshop_root_enforcement where singleton for update;
 if active is not null then return; end if;
 if not exists(select 1 from rm_private.root_creation_settings where singleton and deployment_id is not null)
  or exists(select 1 from public.rm_projetos p where not exists(select 1 from rm_private.workshop_project_ownership o where o.id=p.id))
  or exists(select 1 from public.rm_celulas c where not exists(select 1 from rm_private.workshop_cell_ownership o where o.cell_id=c.id)) then
  raise exception 'Há criações ou origens pendentes de validação.' using errcode='PT409';
 end if;
 alter table public.rm_projetos enable trigger workshop_new_project_origin;
 alter table public.rm_celulas enable trigger workshop_new_cell_origin;
 update rm_private.workshop_root_enforcement set activated_at=clock_timestamp(),activated_by=session_user where singleton;
end
$$;
revoke all on function rm_private.activate_workshop_root_enforcement_v1() from public,anon,authenticated,service_role;
commit;
