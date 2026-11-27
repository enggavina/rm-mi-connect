begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_portal_read_settings (
 singleton boolean primary key default true check(singleton),
 activated_at timestamptz
);
insert into rm_private.workshop_portal_read_settings(singleton) values(true);

-- Retain the Auth identity after a binding is disabled, replaced or deleted.
create table rm_private.workshop_portal_auth_users (auth_user_id uuid primary key);
alter table rm_private.workshop_portal_read_settings enable row level security;
alter table rm_private.workshop_portal_auth_users enable row level security;
revoke all on rm_private.workshop_portal_read_settings,rm_private.workshop_portal_auth_users from public,anon,authenticated,service_role;

create function rm_private.workshop_portal_gateway_required_v1() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from rm_private.workshop_portal_auth_users where auth_user_id=auth.uid());
$$;
revoke all on function rm_private.workshop_portal_gateway_required_v1() from public,anon,authenticated,service_role;
grant execute on function rm_private.workshop_portal_gateway_required_v1() to authenticated;

-- Existing native accounts retain their policies during this portal-only cutover.
do $policies$
declare relation record;
begin
 for relation in
  select c.relname,c.relkind,c.relrowsecurity from pg_class c
  where c.relnamespace='public'::regnamespace and left(c.relname,3)='rm_'
   and c.relkind in('r','p','v','m','f') and has_any_column_privilege('authenticated',c.oid,'select')
   and c.relname<>'rm_option_sets'
  order by c.relname
 loop
  if relation.relkind not in('r','p') or not relation.relrowsecurity then
   raise exception 'Unexpected directly readable relation: %',relation.relname;
  end if;
  execute format('create policy rm_portal_gateway_read on public.%I as restrictive for select to authenticated using (%s)',
   relation.relname,case when relation.relname='rm_users' then 'auth_user_id=(select auth.uid()) or ' else '' end||
   'not (select rm_private.workshop_portal_gateway_required_v1())');
 end loop;
end
$policies$;

create function rm_private.workshop_portal_used_by_mobile_v1(p_auth_user uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from rm_private.operator_delegations where auth_user_id=p_auth_user)
  or exists(select 1 from rm_private.receiving_drafts where auth_user_id=p_auth_user)
  or exists(select 1 from rm_private.mobile_mutation_receipts where auth_user_id=p_auth_user)
  or exists(select 1 from rm_private.mobile_workshop_uploads where auth_user_id=p_auth_user);
$$;

create function rm_private.capture_workshop_portal_auth_user_v1() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from rm_private.workshop_portal_read_settings where singleton and activated_at is not null) then
  if rm_private.workshop_portal_used_by_mobile_v1(new.auth_user_id) then
   raise exception 'A identidade do portal precisa ser distinta da identidade do dispositivo.' using errcode='PT409';
  end if;
  insert into rm_private.workshop_portal_auth_users(auth_user_id) values(new.auth_user_id) on conflict do nothing;
 end if;
 return new;
end
$$;

create trigger rm_capture_workshop_portal_auth_user after insert or update of auth_user_id
 on rm_private.sso_identity_bindings for each row execute function rm_private.capture_workshop_portal_auth_user_v1();

create function rm_private.activate_workshop_portal_reads_v1() returns void
language plpgsql set search_path='' as $$
begin
 lock table rm_private.sso_identity_bindings in share row exclusive mode;
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso)
  or not exists(select 1 from rm_private.workshop_dossier_settings where singleton and enforced)
  or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced) then
  raise exception 'As consultas por oficina do portal ainda não estão ativas.' using errcode='PT409';
 end if;
 if exists(select 1 from rm_private.sso_identity_bindings where rm_private.workshop_portal_used_by_mobile_v1(auth_user_id)) then
  raise exception 'Existe uma identidade de dispositivo também vinculada ao portal.' using errcode='PT409';
 end if;
 insert into rm_private.workshop_portal_auth_users(auth_user_id)
  select auth_user_id from rm_private.sso_identity_bindings on conflict do nothing;
 update rm_private.workshop_portal_read_settings set activated_at=clock_timestamp() where singleton and activated_at is null;
 revoke execute on function public.rm_web_capacity_snapshot_v1(jsonb),public.rm_web_form_source_snapshot_v1(uuid),
  public.rm_web_form_template_snapshot_v1(uuid) from authenticated;
end
$$;

create function rm_private.workshop_project_equipment_type_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare
 required constant text[]:=array['project','equipment','type'];
 result jsonb;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' or p_args-required<>'{}'
  or exists(select 1 from unnest(required) key where jsonb_typeof(p_args->key) is distinct from 'string') then
  raise exception 'Consulta de tipo de equipamento inválida.' using errcode='22023';
 end if;
 select jsonb_build_object('id',t.id,'nome',t.nome,'sigla',t.sigla) into result
 from public.rm_projetos p join public.rm_equipamentos e on e.id=p.equipamento_id and e.projeto_id=p.id
 join public.rm_tipos_equipamento t on t.id=e.tipo_equipamento_id
 where p.id=(p_args->>'project')::uuid and e.id=(p_args->>'equipment')::uuid and t.id=(p_args->>'type')::uuid
  and rm_private.workshop_project_owned_v1(p.id,p_office)
  and rm_private.workshop_read_visible_v1('equipment_type',t.id,p_office)
  and not exists(select 1 from public.rm_projetos peer where peer.equipamento_id=e.id and peer.id<>p.id);
 return result;
exception when invalid_text_representation then
 raise exception 'Consulta de tipo de equipamento inválida.' using errcode='22023';
end
$$;

revoke all on function rm_private.workshop_portal_used_by_mobile_v1(uuid),rm_private.capture_workshop_portal_auth_user_v1(),
 rm_private.activate_workshop_portal_reads_v1(),rm_private.workshop_project_equipment_type_v1(jsonb,uuid) from public,anon,authenticated,service_role;

do $extend$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 allowed constant text:='''project_detail'',''form_record_detail'')';
 dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 constraint_definition text;
begin
 if array_length(string_to_array(issuer,allowed),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2 then
  raise exception 'Unexpected workshop equipment type permit contract';
 end if;
 select pg_get_constraintdef(oid) into strict constraint_definition from pg_constraint
 where conrelid='rm_private.workshop_read_permits'::regclass and conname='workshop_read_permits_resource_check';
 alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
 execute 'alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (('||
  substring(constraint_definition from 8 for char_length(constraint_definition)-8)||') or resource=''project_equipment_type'')';
 execute replace(issuer,allowed,left(allowed,-1)||',''project_equipment_type'')');
 execute replace(reader,dispatch,$query$  when 'project_equipment_type' then rm_private.workshop_project_equipment_type_v1(p_args,permit.workshop_id)
$query$||dispatch);
end
$extend$;

notify pgrst,'reload schema';
commit;
