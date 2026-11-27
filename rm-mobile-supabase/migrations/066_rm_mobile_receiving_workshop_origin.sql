begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.mobile_receiving_workshop_permits (
 submission_id uuid not null,
 phase text not null check(phase in('open','complete')),
 auth_user_id uuid not null,
 auth_session_id uuid not null,
 operator_id uuid not null,
 operator_hash bytea not null,
 payload_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 expires_at timestamptz not null,
 primary key(submission_id,phase)
);
alter table rm_private.mobile_receiving_workshop_permits enable row level security;
revoke all on rm_private.mobile_receiving_workshop_permits from public,anon,authenticated,service_role;

-- Only the portal server can obtain the current device/operator context from
-- Acessos and attach it to this particular native JWT, delegation and payload.
create function public.rm_authorize_mobile_receiving_workshop_v1(
 p_auth_user_id uuid,p_session_id uuid,p_operator_token text,p_workshop_context jsonb,
 p_client_submission_id uuid,p_phase text,p_params jsonb
) returns void language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
 identity record;
 office uuid;
 deadline timestamptz;
begin
 if p_client_submission_id is null or p_phase is null or p_phase not in('open','complete')
  or jsonb_typeof(p_params) is distinct from 'object' or octet_length(p_params::text)>2097152 then
  raise exception 'Dados de recebimento inválidos.' using errcode='22023';
 end if;
 select * into identity from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token);
 if not found then raise exception 'Identifique novamente o operador.' using errcode='28000'; end if;
 office:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,identity.operator_subject);
 if office is null then raise exception 'Confirme novamente a oficina.' using errcode='42501'; end if;
 deadline:=least(identity.expires_at,(p_workshop_context->>'expires_at')::timestamptz,
  (p_workshop_context->>'issued_at')::timestamptz+interval '15 seconds');
 if deadline<=clock_timestamp() then raise exception 'Confirme novamente a oficina.' using errcode='PT503'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
 insert into rm_private.mobile_receiving_workshop_permits as a(submission_id,phase,auth_user_id,
  auth_session_id,operator_id,operator_hash,payload_hash,workshop_id,expires_at)
 values(p_client_submission_id,p_phase,p_auth_user_id,p_session_id,identity.operator_subject,
  extensions.digest(p_operator_token,'sha256'),extensions.digest(p_params::text,'sha256'),office,deadline)
 on conflict(submission_id,phase) do update set auth_session_id=excluded.auth_session_id,
  operator_hash=excluded.operator_hash,expires_at=excluded.expires_at
 where a.auth_user_id=excluded.auth_user_id and a.operator_id=excluded.operator_id
  and a.payload_hash=excluded.payload_hash and a.workshop_id=excluded.workshop_id;
 if not found then raise exception 'O protocolo pertence a outro recebimento.' using errcode='PT409'; end if;
end
$$;
revoke all on function public.rm_authorize_mobile_receiving_workshop_v1(uuid,uuid,text,jsonb,uuid,text,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function public.rm_authorize_mobile_receiving_workshop_v1(uuid,uuid,text,jsonb,uuid,text,jsonb) to service_role;

-- The native client still sends its real Supabase JWT. Reuse the original
-- early opening, QR, draft, media and final receipt paths in one transaction.
create function public.rm_mobile_receiving_workshop_v1(
 p_client_submission_id uuid,p_phase text,p_params jsonb,p_operator_token text
) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
 actor rm_private.operator_delegations;
 permit rm_private.mobile_receiving_workshop_permits;
 linked_project uuid;
 project_id uuid;
 client_id uuid;
 result jsonb;
begin
 if auth.uid() is null or p_client_submission_id is null then
  raise exception 'Sessão do dispositivo ou protocolo indisponível.' using errcode='42501';
 end if;
 actor:=rm_private.receiving_actor_v1(p_operator_token,p_params);
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
 select * into permit from rm_private.mobile_receiving_workshop_permits
  where submission_id=p_client_submission_id and phase=p_phase for update;
 if not found or permit.expires_at<=clock_timestamp() or permit.auth_user_id is distinct from auth.uid()
  or permit.auth_session_id::text is distinct from auth.jwt()->>'session_id'
  or permit.operator_id is distinct from actor.operator_id
  or permit.operator_hash is distinct from extensions.digest(p_operator_token,'sha256')
  or permit.payload_hash is distinct from extensions.digest(p_params::text,'sha256')
  or not exists(select 1 from rm_private.online_operator_identity_v1(auth.uid(),permit.auth_session_id,p_operator_token)) then
  raise exception 'Confirmação da oficina indisponível. O protocolo foi preservado.' using errcode='42501';
 end if;

 -- A QR, an opening or a completed receipt already has its own origin. A new
 -- offline receipt can prove origin from the immutable client selected in the
 -- original payload. Both must agree with the pair's current workshop.
 select o.project_id into linked_project from rm_private.receiving_openings o where o.client_submission_id=p_client_submission_id;
 if not found then
  select nullif(r.result->>'projeto_id','')::uuid into linked_project from rm_private.mobile_mutation_receipts r
    where r.client_submission_id=p_client_submission_id and r.rpc_name='rm_submit_recebimento_v1';
 end if;
 project_id:=coalesce(linked_project,nullif(p_params->>'p_projeto_id','')::uuid);
 client_id:=nullif(p_params->>'p_cliente_id','')::uuid;
 if client_id is not null then
  if not pg_try_advisory_xact_lock_shared(hashtextextended('em:workshop-catalog:v1:client:'||client_id,0)) then
   raise exception 'Cliente em atualização. Reenvie o mesmo protocolo.' using errcode='PT409';
  end if;
  if rm_private.workshop_catalog_scope_v1('client',client_id) is distinct from permit.workshop_id then
   raise exception 'Cliente fora da oficina confirmada ou com origem pendente.' using errcode='42501';
  end if;
 end if;
 if project_id is not null then
  perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
  perform rm_private.workshop_assert_origin_v1('project',project_id,permit.workshop_id);
 elsif client_id is null then
  raise exception 'Informe um cliente da oficina deste recebimento.' using errcode='22023';
 end if;

 if p_phase='open' then
  result:=public.rm_mobile_open_receiving_v1(p_client_submission_id,p_params,p_operator_token);
 else
  result:=public.rm_mobile_mutate_v1(p_client_submission_id,'rm_submit_recebimento_v1',p_params,p_operator_token);
 end if;
 if project_id is null then
  insert into rm_private.workshop_project_ownership(id,workshop_id)
   values((result->>'projeto_id')::uuid,permit.workshop_id);
 elsif result->>'projeto_id' is distinct from project_id::text then
  raise exception 'O protocolo não corresponde ao projeto de origem.' using errcode='PT409';
 end if;
 if permit.expires_at<=clock_timestamp() or not exists(
  select 1 from rm_private.online_operator_identity_v1(auth.uid(),permit.auth_session_id,p_operator_token)
   where expires_at>clock_timestamp()) then
  raise exception 'Confirme novamente a oficina e reenvie o mesmo protocolo.' using errcode='PT503';
 end if;
 delete from rm_private.mobile_receiving_workshop_permits where submission_id=p_client_submission_id and phase=p_phase;
 return result;
exception when invalid_text_representation then
 raise exception 'Identificador de recebimento inválido.' using errcode='22023';
end
$$;
revoke all on function public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
