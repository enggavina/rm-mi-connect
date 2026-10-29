-- Explicit approved EM-only role promotion; no Auth identity or tablet mutation.
-- Verify project ellpxfbsrbhblyizvbbk/name/org before running. ROLLBACK default.
-- Private settings: em.promotion.subject, .binding_id, .rm_user_id, .auth_user_id,
-- .matricula, .requestor_subject. Existing identity approval stays untouched.
begin;
set local lock_timeout='10s';
set local statement_timeout='30s';
set local request.jwt.claims='{}';
-- APPROVED_INPUTS
create temporary view em_web_promotion_preserved as select jsonb_build_object(
 'users',(select md5(coalesce(jsonb_agg(to_jsonb(u) order by u.id)::text,'[]')) from public.rm_users u where id<>current_setting('em.promotion.rm_user_id')::uuid),
 'target_columns',(select to_jsonb(u)-'perfil'-'updated_at' from public.rm_users u where id=current_setting('em.promotion.rm_user_id')::uuid),
 'bindings',(select md5(coalesce(jsonb_agg(to_jsonb(b) order by b.id)::text,'[]')) from rm_private.sso_identity_bindings b where id<>current_setting('em.promotion.binding_id')::uuid),
 'binding_columns',(select to_jsonb(b)-'approval_metadata' from rm_private.sso_identity_bindings b where id=current_setting('em.promotion.binding_id')::uuid),
 'prior_approval',(select approval_metadata-'em_admin_upgrade_20261029' from rm_private.sso_identity_bindings where id=current_setting('em.promotion.binding_id')::uuid),
 'credentials',(select md5(coalesce(jsonb_agg(to_jsonb(c) order by c.user_id)::text,'[]')) from rm_private.user_credentials c),
 'operator_cells',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id)::text,'[]')) from public.rm_tablet_celula_users t),
 'auth_identity',(select md5(to_jsonb(a)::text) from auth.users a where id=current_setting('em.promotion.auth_user_id')::uuid),
 'settings',(select jsonb_agg(to_jsonb(s)) from rm_private.sso_settings s),
 'outbox',(select md5(coalesce(jsonb_agg(to_jsonb(o) order by o.id)::text,'[]')) from public.rm_sync_outbox o)
) state;
create temporary table em_web_promotion_before on commit drop as select state from em_web_promotion_preserved;
do $promote_web$
declare b rm_private.sso_identity_bindings%rowtype; u public.rm_users%rowtype; marker jsonb;
begin
 if auth.uid() is not null or (select require_sso from rm_private.sso_settings where singleton) is distinct from true
   or not exists(select 1 from supabase_migrations.schema_migrations where version='018') then
   raise exception 'Unexpected technical actor, SSO setting or migration.'; end if;
 select * into strict b from rm_private.sso_identity_bindings where id=current_setting('em.promotion.binding_id')::uuid for update;
 select * into strict u from public.rm_users where id=current_setting('em.promotion.rm_user_id')::uuid for update;
 if b.issuer<>'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1' or b.subject<>current_setting('em.promotion.subject')::uuid
   or b.rm_user_id<>u.id or b.auth_user_id<>u.auth_user_id or b.auth_user_id<>current_setting('em.promotion.auth_user_id')::uuid
   or not b.enabled or b.approved_by is null or b.approved_at is null or u.status<>'ativo'
   or u.matricula<>current_setting('em.promotion.matricula') or u.matricula not like 'WEB-%' or u.bubble_id is not null
   or u.perfil not in ('auditor','administrador')
   or exists(select 1 from rm_private.user_credentials where user_id=u.id)
   or exists(select 1 from public.rm_tablet_celula_users where identidade_id=u.id or usuario_id=u.id)
   or not exists(select 1 from auth.users a where a.id=b.auth_user_id and a.email='em-sso-'||b.subject::text||'@identity.invalid')
   or not exists(select 1 from rm_private.sso_identity_bindings r join public.rm_users p on p.id=r.rm_user_id and p.auth_user_id=r.auth_user_id
     where r.issuer=b.issuer and r.subject=current_setting('em.promotion.requestor_subject')::uuid and r.enabled and p.status='ativo' and p.perfil='administrador')
 then raise exception 'Approved dedicated web identity differs; no legacy account may be promoted.'; end if;
 marker:=b.approval_metadata->'em_admin_upgrade_20261029';
 if u.perfil='administrador' then
   if marker->>'new_profile' is distinct from 'administrador' or marker->>'authorization' is distinct from 'explicit-user-request'
     or marker->>'requestor_subject' is distinct from current_setting('em.promotion.requestor_subject') then
     raise exception 'Existing promotion audit differs.'; end if;
 else
   if marker is not null then raise exception 'Promotion audit already exists with inconsistent role.'; end if;
   update public.rm_users set perfil='administrador' where id=u.id;
   update rm_private.sso_identity_bindings set approval_metadata=approval_metadata||jsonb_build_object('em_admin_upgrade_20261029',
     jsonb_build_object('technical_actor','codex:em-approved-admin-promotion:2026-10-29','database_actor',current_user,
       'authorization','explicit-user-request','requestor_subject',current_setting('em.promotion.requestor_subject'),
       'previous_profile','auditor','new_profile','administrador','changed_at',clock_timestamp(),
       'legacy_tablet_changed',false,'auth_metadata_changed',false,'sso_login_proved',false)) where id=b.id;
 end if;
 if (select state from em_web_promotion_before) is distinct from (select state from em_web_promotion_preserved) then
   raise exception 'Identity, tablet, credential, outbox or unrelated profile changed.'; end if;
end;
$promote_web$;
select 'em' application,(select perfil from public.rm_users where id=current_setting('em.promotion.rm_user_id')::uuid) profile,
 (select require_sso from rm_private.sso_settings where singleton) require_sso,
 ((select state from em_web_promotion_before)=(select state from em_web_promotion_preserved)) unrelated_state_preserved;
drop view em_web_promotion_preserved;
ROLLBACK;
