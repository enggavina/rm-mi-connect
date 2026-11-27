begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Temporary permission for the existing tablet account while older Android
-- installations still read catalog tables directly.
create table rm_private.workshop_legacy_catalog_access (
 singleton boolean primary key default true check(singleton),
 auth_user_id uuid not null,
 workshop_id uuid not null,
 verified_at timestamptz not null,
 activated_at timestamptz not null default clock_timestamp(),
 revoked_at timestamptz,
 database_actor text not null default session_user
);
alter table rm_private.workshop_legacy_catalog_access enable row level security;
revoke all on rm_private.workshop_legacy_catalog_access from public,anon,authenticated,service_role;

create view rm_private.workshop_legacy_bma_catalog_rows as
with bma as (select legacy_workshop_id id from rm_private.workshop_legacy_adoption where singleton)
select 'rm_clientes'::text resource,r.id from public.rm_clientes r cross join bma
 where rm_private.workshop_read_owned_v1('client',r.id,bma.id)
union all select 'rm_tipos_equipamento',r.id from public.rm_tipos_equipamento r cross join bma
 where rm_private.workshop_read_owned_v1('equipment_type',r.id,bma.id)
union all select 'rm_celulas',r.id from public.rm_celulas r cross join bma
 where rm_private.workshop_cell_owned_v1(r.id,bma.id)
union all select 'rm_tablet_celula_users',r.id from public.rm_tablet_celula_users r cross join bma
 where rm_private.workshop_cell_owned_v1(r.celula_id,bma.id)
union all select 'rm_forms',r.id from public.rm_forms r cross join bma
 where rm_private.workshop_read_visible_v1('form_model',r.id,bma.id)
union all select 'rm_questoes',r.id from public.rm_questoes r cross join bma
 where rm_private.workshop_read_owned_v1('form_model',r.form_id,bma.id)
union all select 'rm_itens_questoes',r.id from rm_private.workshop_form_options_v1 r cross join bma
 where rm_private.workshop_read_owned_v1('form_model',r.form_id,bma.id)
union all select 'rm_celula_tipos_equipamento',r.id from public.rm_celula_tipos_equipamento r cross join bma
 where rm_private.workshop_mobile_cell_type_owned_v1(r.id,bma.id)
union all select 'rm_celula_form_tipos_equipamento',r.id from public.rm_celula_form_tipos_equipamento r cross join bma
 where rm_private.workshop_mobile_cell_type_owned_v1(r.celula_tipo_equipamento_id,bma.id)
  and rm_private.workshop_read_owned_v1('form_model',r.form_id,bma.id)
union all select 'rm_cadastro_fotos',r.id from public.rm_cadastro_fotos r
 join rm_private.engineering_photo_title_scope s on s.title_id=r.id join bma on bma.id=s.workshop_id
 where s.cell_id is null or rm_private.workshop_cell_owned_v1(s.cell_id,bma.id)
union all select 'rm_form_template_drafts',r.id from public.rm_form_template_drafts r cross join bma
 where rm_private.workshop_read_visible_v1('draft',r.id,bma.id)
union all select 'rm_form_template_versions',r.form_id from public.rm_form_template_versions r cross join bma
 where rm_private.workshop_read_owned_v1('family',r.family_id,bma.id)
  and rm_private.workshop_read_visible_v1('form_model',r.form_id,bma.id)
  and (r.draft_id is null or rm_private.workshop_read_owned_v1('draft',r.draft_id,bma.id));
revoke all on rm_private.workshop_legacy_bma_catalog_rows from public,anon,authenticated,service_role;

create function rm_private.workshop_legacy_bma_catalog_ids_v1(p_resource text)
returns setof uuid language sql stable security definer set search_path='' as $$
 select r.id from rm_private.workshop_legacy_bma_catalog_rows r
 where r.resource=p_resource and exists(
  select 1 from rm_private.workshop_legacy_catalog_access a
  join rm_private.workshop_legacy_adoption b on b.singleton and b.legacy_workshop_id=a.workshop_id
  where a.singleton and a.auth_user_id=auth.uid() and a.revoked_at is null
   and exists(select 1 from public.rm_users u where u.auth_user_id=a.auth_user_id and u.status='ativo')
 );
$$;
revoke all on function rm_private.workshop_legacy_bma_catalog_ids_v1(text) from public,anon,authenticated,service_role;
grant execute on function rm_private.workshop_legacy_bma_catalog_ids_v1(text) to authenticated;

create function rm_private.activate_workshop_legacy_bma_catalog_v1(p_device uuid,p_session uuid)
returns void language plpgsql set search_path='' set lock_timeout='5s' as $$
declare
 office uuid;
 confirmed_at timestamptz;
 relation text;
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop-legacy-bma-catalog',119));
 if exists(select 1 from rm_private.workshop_legacy_catalog_access where singleton) then
  if exists(select 1 from rm_private.workshop_legacy_catalog_access where singleton and auth_user_id=p_device and revoked_at is null) then return; end if;
  raise exception 'O acesso de compatibilidade pertence ao dispositivo original.' using errcode='PT409';
 end if;
 select w.id into office from rm_private.workshop_legacy_adoption b
  join rm_private.workshop_references w on w.id=b.legacy_workshop_id and w.code='BMA' where b.singleton;
 select max(seen.observed_at) into confirmed_at
 from rm_private.workshop_android_observations seen join auth.sessions s on s.id=seen.session_id and s.user_id=p_device
 where seen.session_id=p_session and seen.workshop_id=office and seen.observed_at>=statement_timestamp()-interval '1 hour'
  and coalesce(nullif(to_jsonb(s)->>'not_after','')::timestamptz,'infinity')>statement_timestamp()
  and exists(select 1 from rm_private.operator_delegations d where d.auth_user_id=s.user_id and d.operator_id=seen.operator_id
   and not d.revoked and least(d.expires_at,d.created_at+interval '24 hours')>statement_timestamp());
 if confirmed_at is null or not exists(select 1 from public.rm_users u where u.auth_user_id=p_device and u.status='ativo')
  or exists(select 1 from rm_private.workshop_portal_auth_users p where p.auth_user_id=p_device)
  or exists(select 1 from rm_private.workshop_android_observations seen join auth.sessions s on s.id=seen.session_id
   where s.user_id=p_device and seen.workshop_id<>office and seen.observed_at>=confirmed_at) then
  raise exception 'Confirme o dispositivo e o operador da BMA antes de ativar o recorte legado.' using errcode='PT409';
 end if;

 insert into rm_private.workshop_legacy_catalog_access(auth_user_id,workshop_id,verified_at) values(p_device,office,confirmed_at);
 foreach relation in array array[
  'rm_clientes','rm_tipos_equipamento','rm_celulas','rm_tablet_celula_users','rm_forms','rm_questoes','rm_itens_questoes',
  'rm_celula_tipos_equipamento','rm_celula_form_tipos_equipamento','rm_cadastro_fotos','rm_form_template_drafts','rm_form_template_versions'
 ] loop
  execute format('create policy rm_legacy_bma_catalog_read on public.%I as restrictive for select to authenticated
   using(%I in(select rm_private.workshop_legacy_bma_catalog_ids_v1(%L)))',relation,
   case when relation='rm_form_template_versions' then 'form_id' else 'id' end,relation);
 end loop;
end
$$;
revoke all on function rm_private.activate_workshop_legacy_bma_catalog_v1(uuid,uuid) from public,anon,authenticated,service_role;

-- A later verified assignment to another office permanently retires this
-- exception, even after the session that observed the transfer has ended.
do $retire$
declare
 observer text:=pg_get_functiondef('public.rm_observe_mobile_workshop_android_v1(uuid,uuid,text,jsonb,text,integer)'::regprocedure);
 marker constant text:=' insert into rm_private.workshop_android_observations as current';
begin
 if array_length(string_to_array(observer,marker),1) is distinct from 2 then
  raise exception 'Unexpected Android workshop observer contract';
 end if;
 execute replace(observer,marker,$retirement$ perform pg_advisory_xact_lock_shared(hashtextextended('workshop-legacy-bma-catalog',119));
 if exists(select 1 from rm_private.workshop_legacy_catalog_access a
   where a.singleton and a.auth_user_id=p_auth_user_id and a.workshop_id<>office and a.revoked_at is null) then
  update rm_private.workshop_legacy_catalog_access set revoked_at=seen_at
   where singleton and auth_user_id=p_auth_user_id and workshop_id<>office and revoked_at is null;
 end if;

$retirement$||marker);
end
$retire$;

notify pgrst,'reload schema';
commit;
