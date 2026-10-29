-- STAGED ONLY: opaque BFF sessions and explicitly approved corporate bindings.
-- No identity is provisioned and no central grant is inferred by this migration.
begin;

create table rm_private.sso_settings (
  singleton boolean primary key default true check(singleton),
  require_sso boolean not null default false
);
insert into rm_private.sso_settings(singleton,require_sso) values(true,false);

create table rm_private.sso_identity_bindings (
  id uuid primary key default gen_random_uuid(),
  issuer text not null check(issuer='https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'),
  subject uuid not null,
  rm_user_id uuid not null unique references public.rm_users(id) on delete restrict,
  auth_user_id uuid not null unique references auth.users(id) on delete restrict,
  enabled boolean not null default false,
  approved_by uuid references public.rm_users(id) on delete restrict,
  approved_at timestamptz,
  approval_metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(approval_metadata)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(issuer,subject),
  check(not enabled or (approved_by is not null and approved_at is not null))
);
create table rm_private.sso_flows (
  hash text primary key check(hash ~ '^[0-9a-f]{64}$'),
  ciphertext text not null check(octet_length(ciphertext) between 16 and 65536),
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp()
);
create table rm_private.sso_sessions (
  hash text primary key check(hash ~ '^[0-9a-f]{64}$'),
  binding_id uuid not null references rm_private.sso_identity_bindings(id) on delete cascade,
  local_session_id uuid not null references auth.sessions(id) on delete cascade,
  ciphertext text not null check(octet_length(ciphertext) between 16 and 65536),
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index rm_sso_sessions_binding on rm_private.sso_sessions(binding_id);
create index rm_sso_sessions_local_session on rm_private.sso_sessions(local_session_id);
create table rm_private.sso_action_permits (
  submission_id uuid primary key,
  session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
  operation text not null check(operation in ('save_project','plan_cell','review_form')),
  payload_hash bytea not null,
  capability text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp()
);
create index rm_sso_permits_session on rm_private.sso_action_permits(session_hash);
revoke all on rm_private.sso_settings,rm_private.sso_identity_bindings,rm_private.sso_flows,
  rm_private.sso_sessions,rm_private.sso_action_permits from public,anon,authenticated,service_role;

create function public.rm_sso_binding_v1(p_issuer text,p_subject uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('binding_id',b.id,'rm_user_id',u.id,'auth_user_id',b.auth_user_id,
    'profile',jsonb_build_object('id',u.id,'nome',u.nome,'perfil',u.perfil,'cargo',u.cargo,'matricula',u.matricula))
  from rm_private.sso_identity_bindings b join public.rm_users u on u.id=b.rm_user_id and u.auth_user_id=b.auth_user_id
  where b.issuer=p_issuer and b.subject=p_subject and b.enabled and u.status='ativo'
    and u.perfil in ('administrador','padr_o','auditor');
$$;

create function public.rm_sso_flow_put_v1(p_hash text,p_ciphertext text,p_expires_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_ciphertext is null or octet_length(p_ciphertext) not between 16 and 65536
    or p_expires_at is null or p_expires_at<=clock_timestamp() or p_expires_at>clock_timestamp()+interval '10 minutes' then
    raise exception 'Fluxo SSO inválido.' using errcode='22023'; end if;
  delete from rm_private.sso_flows where expires_at<=clock_timestamp();
  insert into rm_private.sso_flows(hash,ciphertext,expires_at) values(p_hash,p_ciphertext,p_expires_at);
end $$;

create function public.rm_sso_flow_take_v1(p_hash text) returns text
language plpgsql security definer set search_path='' as $$
declare item rm_private.sso_flows%rowtype;
begin
  delete from rm_private.sso_flows where hash=p_hash returning * into item;
  if item.expires_at>clock_timestamp() then return item.ciphertext; end if;
  return null;
end $$;

create function public.rm_sso_flow_get_v1(p_hash text) returns text
language sql stable security definer set search_path='' as $$
  select ciphertext from rm_private.sso_flows where hash=p_hash and expires_at>statement_timestamp();
$$;

create function public.rm_sso_session_put_v1(p_hash text,p_binding_id uuid,p_local_session_id uuid,
  p_ciphertext text,p_expires_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare binding rm_private.sso_identity_bindings%rowtype;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_ciphertext is null or octet_length(p_ciphertext) not between 16 and 65536
    or p_expires_at is null or p_expires_at<=clock_timestamp() or p_expires_at>clock_timestamp()+interval '1 hour' then
    raise exception 'Sessão SSO inválida.' using errcode='22023'; end if;
  select * into binding from rm_private.sso_identity_bindings where id=p_binding_id for share;
  if not found or not binding.enabled or not exists(select 1 from public.rm_users where id=binding.rm_user_id
    and auth_user_id=binding.auth_user_id and status='ativo' and perfil in ('administrador','padr_o','auditor')) then
    raise exception 'Vínculo SSO indisponível.' using errcode='42501'; end if;
  if not exists(select 1 from auth.sessions where id=p_local_session_id and user_id=binding.auth_user_id) then
    raise exception 'Sessão Auth divergente.' using errcode='42501'; end if;
  insert into rm_private.sso_sessions(hash,binding_id,local_session_id,ciphertext,expires_at)
    values(p_hash,p_binding_id,p_local_session_id,p_ciphertext,p_expires_at)
    on conflict(hash) do update set ciphertext=excluded.ciphertext,expires_at=excluded.expires_at,updated_at=clock_timestamp()
    where rm_private.sso_sessions.binding_id=excluded.binding_id and rm_private.sso_sessions.local_session_id=excluded.local_session_id;
  if not found then raise exception 'Identificador de sessão já utilizado.' using errcode='23505'; end if;
end $$;

create function public.rm_sso_session_get_v1(p_hash text) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('ciphertext',s.ciphertext,'binding_id',b.id,'rm_user_id',u.id,'auth_user_id',b.auth_user_id,
    'local_session_id',s.local_session_id,'expires_at',s.expires_at,'issuer',b.issuer,'subject',b.subject,
    'profile',jsonb_build_object('id',u.id,'nome',u.nome,'perfil',u.perfil,'cargo',u.cargo,'matricula',u.matricula))
  from rm_private.sso_sessions s join rm_private.sso_identity_bindings b on b.id=s.binding_id
    join public.rm_users u on u.id=b.rm_user_id and u.auth_user_id=b.auth_user_id
    join auth.sessions a on a.id=s.local_session_id and a.user_id=b.auth_user_id
  where s.hash=p_hash and s.expires_at>statement_timestamp() and b.enabled and u.status='ativo'
    and u.perfil in ('administrador','padr_o','auditor');
$$;

create function public.rm_sso_session_delete_v1(p_hash text) returns void
language sql security definer set search_path='' as $$
  delete from rm_private.sso_sessions where hash=p_hash;
$$;

create function public.rm_sso_action_permit_v1(p_session_hash text,p_submission_id uuid,p_operation text,
  p_payload jsonb,p_capability text) returns void
language plpgsql security definer set search_path='' as $$
declare binding rm_private.sso_identity_bindings%rowtype; sess rm_private.sso_sessions%rowtype; required_capability text;
begin
  required_capability:=case p_operation when 'save_project' then 'em.projects.manage'
    when 'plan_cell' then 'em.planning.manage' when 'review_form' then 'em.forms.review' end;
  if p_submission_id is null or required_capability is null or p_capability is distinct from required_capability
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Permissão de ação inválida.' using errcode='22023'; end if;
  select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
    where s.hash=p_session_hash for share of b;
  if not found or not binding.enabled or not exists(select 1 from public.rm_users where id=binding.rm_user_id
    and auth_user_id=binding.auth_user_id and status='ativo' and perfil in ('administrador','padr_o','auditor')) then
    raise exception 'Vínculo SSO indisponível.' using errcode='42501'; end if;
  select * into sess from rm_private.sso_sessions where hash=p_session_hash for share;
  if not found or sess.binding_id<>binding.id or sess.expires_at<=clock_timestamp()
    or not exists(select 1 from auth.sessions where id=sess.local_session_id and user_id=binding.auth_user_id) then
    raise exception 'Sessão SSO indisponível.' using errcode='42501'; end if;
  insert into rm_private.sso_action_permits(submission_id,session_hash,operation,payload_hash,capability,expires_at)
    values(p_submission_id,p_session_hash,p_operation,extensions.digest(p_payload::text,'sha256'),p_capability,
      least(sess.expires_at,clock_timestamp()+interval '15 seconds'))
    on conflict(submission_id) do update set expires_at=excluded.expires_at,created_at=clock_timestamp()
    where rm_private.sso_action_permits.session_hash=excluded.session_hash
      and rm_private.sso_action_permits.operation=excluded.operation
      and rm_private.sso_action_permits.payload_hash=excluded.payload_hash
      and rm_private.sso_action_permits.capability=excluded.capability;
  if not found then raise exception 'Permissão já vinculada a outra ação.' using errcode='23505'; end if;
end $$;

-- The existing core retains all role, MFA, validation, HTTP409 and receipt rules.
alter function public.rm_web_mutate_v1(uuid,text,jsonb) set schema rm_private;
alter function rm_private.rm_web_mutate_v1(uuid,text,jsonb) rename to web_mutate_core_v1;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

create function public.rm_web_mutate_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare binding rm_private.sso_identity_bindings%rowtype; sess rm_private.sso_sessions%rowtype;
  permit rm_private.sso_action_permits%rowtype; permit_session text; strict_mode boolean;
begin
  if auth.uid() is null then raise exception 'Sessão Auth necessária.' using errcode='42501'; end if;
  select require_sso into strict_mode from rm_private.sso_settings where singleton for share;
  -- A disabled existing binding never falls through to legacy access.
  select * into binding from rm_private.sso_identity_bindings
    where auth_user_id=auth.uid() or rm_user_id=rm_private.current_rm_user_id() for share;
  if coalesce(strict_mode,true) or binding.id is not null then
    if binding.id is null or binding.auth_user_id is distinct from auth.uid() or not binding.enabled or not exists(select 1 from public.rm_users
      where id=binding.rm_user_id and auth_user_id=binding.auth_user_id and status='ativo'
        and perfil in ('administrador','padr_o','auditor')) then
      raise exception 'Vínculo SSO obrigatório.' using errcode='42501'; end if;
    if p_client_submission_id is null then raise exception 'Informe o envio.' using errcode='22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
    select session_hash into permit_session from rm_private.sso_action_permits where submission_id=p_client_submission_id;
    -- Lock session before permit, matching deletion/cascade and issuance order.
    select * into sess from rm_private.sso_sessions where hash=permit_session for share;
    if not found or sess.binding_id<>binding.id or sess.expires_at<=clock_timestamp()
      or (auth.jwt()->>'session_id') is distinct from sess.local_session_id::text
      or not exists(select 1 from auth.sessions where id=sess.local_session_id and user_id=binding.auth_user_id) then
      raise exception 'Sessão SSO ou permissão indisponível.' using errcode='42501'; end if;
    select * into permit from rm_private.sso_action_permits where submission_id=p_client_submission_id for update;
    if not found or permit.session_hash<>sess.hash or permit.expires_at<=clock_timestamp()
      or permit.operation is distinct from p_operation
      or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256') then
      raise exception 'Permissão de ação ausente, expirada ou divergente.' using errcode='42501'; end if;
    delete from rm_private.sso_action_permits where submission_id=p_client_submission_id;
  end if;
  -- Consumption and mutation commit together; replays need a freshly authorized permit.
  return rm_private.web_mutate_core_v1(p_client_submission_id,p_operation,p_payload);
end $$;
revoke all on function public.rm_web_mutate_v1(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.rm_web_mutate_v1(uuid,text,jsonb) to authenticated;

do $$ declare signature text;
begin
  foreach signature in array array[
    'public.rm_sso_binding_v1(text,uuid)','public.rm_sso_flow_put_v1(text,text,timestamptz)',
    'public.rm_sso_flow_take_v1(text)','public.rm_sso_flow_get_v1(text)','public.rm_sso_session_put_v1(text,uuid,uuid,text,timestamptz)',
    'public.rm_sso_session_get_v1(text)','public.rm_sso_session_delete_v1(text)',
    'public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'] loop
    execute 'revoke all on function '||signature||' from public,anon,authenticated,service_role';
    execute 'grant execute on function '||signature||' to service_role';
  end loop;
end $$;
notify pgrst,'reload schema';
commit;
