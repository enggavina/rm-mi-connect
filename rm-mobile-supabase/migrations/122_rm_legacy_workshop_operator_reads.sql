begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.workshop_legacy_operator_read_settings (
 singleton boolean primary key check(singleton),
 activated_at timestamptz not null
);
alter table rm_private.workshop_legacy_operator_read_settings enable row level security;
revoke all on rm_private.workshop_legacy_operator_read_settings from public,anon,authenticated,service_role;

-- Identity and delegation still work for every device. The previous cell catalog
-- is only needed by the verified BMA device while earlier Android clients migrate.
create function rm_private.workshop_legacy_operator_office_v1(p_operator uuid)
returns uuid language sql stable set search_path='' as $$
 select a.workshop_id from rm_private.workshop_legacy_catalog_access a
 where a.singleton and a.auth_user_id=auth.uid() and a.revoked_at is null
  and (select rm_private.workshop_legacy_bma_device_v1())
  and (rm_private.workshop_mobile_actor_visible_v1(p_operator,null,a.workshop_id)
   or exists(select 1 from rm_private.workshop_android_observations o join auth.sessions s on s.id=o.session_id
    where o.operator_id=p_operator and o.workshop_id=a.workshop_id and s.user_id=a.auth_user_id
     and s.id::text=auth.jwt()->>'session_id'));
$$;
revoke all on function rm_private.workshop_legacy_operator_office_v1(uuid) from public,anon,authenticated,service_role;

create or replace function rm_private.operator_context(p_operator uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  with access as materialized (
    select exists(select 1 from rm_private.workshop_legacy_operator_read_settings where singleton) scoped,
           rm_private.workshop_legacy_operator_office_v1(p_operator) office
  )
  select jsonb_build_object('operador_id',u.id,'bubble_id',u.bubble_id,'matricula',u.matricula,
    'nome',u.nome,'cargo',u.cargo,'perfil',u.perfil,'perfil_assinante',u.perfil_assinante,
    'equipe_id',u.equipe_id,'criar_form',u.criar_form,'cell_access_policy_version',2,
    'celulas_vinculadas',coalesce((select jsonb_agg(jsonb_build_object('celula_id',c.id,
      'bubble_id',c.bubble_id,'codigo',c.codigo,'nome',c.nome,'ordem',c.ordem)
      order by c.ordem nulls last,c.indice nulls last,c.id)
      from public.rm_celulas c where (not access.scoped or rm_private.workshop_cell_owned_v1(c.id,access.office))
       and rm_private.operator_can_access_cell(u.id,c.id)),'[]'::jsonb))
  from public.rm_users u cross join access where u.id=p_operator and u.status='ativo';
$$;

do $readers$
declare
 login text:=pg_get_functiondef('rm_private.rm_authenticate_operator_v1(text,text,uuid,uuid,text,text)'::regprocedure);
 mobile text:=pg_get_functiondef('public.rm_mobile_execution_snapshot_v1(text,uuid)'::regprocedure);
 check_cell constant text:='  if p_celula_id is not null then perform rm_private.assert_cell_access(v_user.id,p_celula_id); end if;';
 query_allocation constant text:=' select * into a from public.rm_celulas_projeto where id=p_allocation_id;';
 declaration constant text:='declare d rm_private.operator_delegations%rowtype;';
begin
 if array_length(string_to_array(login,check_cell),1) is distinct from 2
  or array_length(string_to_array(mobile,query_allocation),1) is distinct from 2
  or array_length(string_to_array(mobile,declaration),1) is distinct from 2 then
  raise exception 'Unexpected operator read contract';
 end if;
 execute replace(login,check_cell,$guard$
  if p_celula_id is not null then
    if exists(select 1 from rm_private.workshop_legacy_operator_read_settings where singleton)
      and not rm_private.workshop_cell_owned_v1(p_celula_id,rm_private.workshop_legacy_operator_office_v1(v_user.id)) then
      raise exception 'Operador sem permissão cadastrada para esta célula.' using errcode='42501';
    end if;
    perform rm_private.assert_cell_access(v_user.id,p_celula_id);
  end if;$guard$);
 mobile:=replace(mobile,declaration,declaration||' scope_office uuid;');
 execute replace(mobile,query_allocation,$guard$
 if exists(select 1 from rm_private.workshop_legacy_operator_read_settings where singleton) then
  scope_office:=rm_private.workshop_legacy_operator_office_v1(d.operator_id);
  if scope_office is null then
   raise exception 'A etapa do projeto não está disponível.' using errcode='P0002';
  end if;
  return rm_private.workshop_mobile_execution_projection_v1(d.operator_id,p_allocation_id,scope_office);
 end if;
$guard$||query_allocation);
end
$readers$;

create function rm_private.activate_workshop_legacy_operator_reads_v1()
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop-legacy-bma-catalog',119));
 if not exists(select 1 from pg_policy where polrelid='public.rm_users'::regclass and polname='rm_legacy_bma_people_read'
   and not polpermissive and polcmd='r') then
  raise exception 'Ative o recorte de pessoas antes das consultas de operador.' using errcode='PT409';
 end if;
 insert into rm_private.workshop_legacy_operator_read_settings(singleton,activated_at)
  values(true,clock_timestamp()) on conflict(singleton) do nothing;
 grant execute on function public.rm_user_has_element_permission(uuid,text) to service_role;
 revoke execute on function public.rm_user_has_element_permission(uuid,text) from public,anon,authenticated;
 perform pg_notify('pgrst','reload schema');
end
$$;
revoke all on function rm_private.activate_workshop_legacy_operator_reads_v1() from public,anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;
