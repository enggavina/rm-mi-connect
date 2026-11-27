begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

-- Only a completed scoped catalog read can submit an observation. Build details
-- are reported by the client and are never an authorization or cutover switch.
create table rm_private.workshop_android_observations (
 session_id uuid not null references auth.sessions(id) on delete cascade,
 operator_id uuid not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 app_version text not null check(app_version ~ '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'),
 build_code integer not null check(build_code between 1 and 2100000000),
 observed_at timestamptz not null,
 primary key(session_id,operator_id)
);
alter table rm_private.workshop_android_observations enable row level security;
revoke all on rm_private.workshop_android_observations from public,anon,authenticated,service_role;

create function public.rm_observe_mobile_workshop_android_v1(p_auth_user_id uuid,p_session_id uuid,p_operator_token text,
 p_workshop_context jsonb,p_app_version text,p_build_code integer) returns void
language plpgsql security definer set search_path='' as $$
declare
 actor uuid;
 office uuid;
 seen_at timestamptz:=clock_timestamp();
begin
 if p_app_version is null or p_app_version !~ '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
  or p_build_code is null or p_build_code not between 1 and 2100000000 then
  raise exception 'Versão Android inválida.' using errcode='22023';
 end if;
 select i.operator_subject into actor from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token) i;
 if actor is null then raise exception 'Identificação inválida.' using errcode='28000'; end if;
 office:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,actor);
 if office is null then raise exception 'Oficina indisponível.' using errcode='42501'; end if;

 insert into rm_private.workshop_android_observations as current(session_id,operator_id,workshop_id,app_version,build_code,observed_at)
 values(p_session_id,actor,office,p_app_version,p_build_code,seen_at)
 on conflict(session_id,operator_id) do update set workshop_id=excluded.workshop_id,app_version=excluded.app_version,
  build_code=excluded.build_code,observed_at=excluded.observed_at
 where current.observed_at<=excluded.observed_at and (current.observed_at<=excluded.observed_at-interval '15 minutes'
  or (current.workshop_id,current.app_version,current.build_code) is distinct from (excluded.workshop_id,excluded.app_version,excluded.build_code));
end
$$;
revoke all on function public.rm_observe_mobile_workshop_android_v1(uuid,uuid,text,jsonb,text,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.rm_observe_mobile_workshop_android_v1(uuid,uuid,text,jsonb,text,integer) to service_role;
notify pgrst,'reload schema';
commit;
