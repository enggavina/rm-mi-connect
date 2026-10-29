-- Run ONLY after the SSO BFF is deployed and its production checks pass.
-- In the same SQL connection, explicitly SET em.sso_bff_verified='true';
-- then execute this script. No application session or permission is fabricated.
-- Both dedicated web profiles are administrators after the user's 29/10/2026
-- approval. Activation only validates them; it never rewrites either profile.
begin;
set local lock_timeout='10s';
do $activation$
begin
  if current_setting('em.sso_bff_verified',true) is distinct from 'true' then
    raise exception 'Verify production BFF, callback and both central grants before activation.';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='016' and name='rm_web_sso_bridge') then
    raise exception 'SSO migration is not installed.';
  end if;
  if (select count(*) from rm_private.sso_identity_bindings b join public.rm_users u
    on u.id=b.rm_user_id and u.auth_user_id=b.auth_user_id
    where b.enabled and b.issuer='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1' and u.status='ativo'
      and ((b.subject='01316705-7361-459f-ba3b-9971777aa607' and u.matricula='WEB-MGAVINA' and u.perfil='administrador')
        or (b.subject='a9e45880-1924-4b2d-a2b1-dc12fd029bff' and u.matricula='WEB-SOFTDEV05' and u.perfil='administrador')))<>2 then
    raise exception 'Expected two approved web identities are not ready.';
  end if;
  if has_function_privilege('authenticated','rm_private.web_mutate_core_v1(uuid,text,jsonb)','execute')
    or has_function_privilege('authenticated','public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)','execute')
    or not has_function_privilege('authenticated','public.rm_web_mutate_v1(uuid,text,jsonb)','execute') then
    raise exception 'Unexpected RPC permissions.';
  end if;
  update rm_private.sso_settings set require_sso=true where singleton;
  if not found then raise exception 'SSO settings absent.'; end if;
end $activation$;
commit;
select require_sso from rm_private.sso_settings where singleton;
