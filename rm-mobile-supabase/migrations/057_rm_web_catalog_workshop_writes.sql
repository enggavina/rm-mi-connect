-- Targeted web catalog writes only. No read isolation, mobile SSO or office default.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.catalog_workshop_write_settings (
 singleton boolean primary key default true check(singleton),
 enforced boolean not null default false,
 runtime_sha text,deployment_id uuid,activated_at timestamptz,database_actor text,
 check(not enforced or(runtime_sha is not null and runtime_sha ~ '^[0-9a-f]{40}$' and deployment_id is not null and activated_at is not null and database_actor is not null))
);
insert into rm_private.catalog_workshop_write_settings(singleton) values(true);
create table rm_private.catalog_workshop_write_permits (
 submission_id uuid primary key,
 session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 operation text not null check(operation in('save_catalog','delete_catalog')),
 payload_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 subject uuid not null,
 context jsonb not null,
 expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp()
);
create index catalog_workshop_permits_session on rm_private.catalog_workshop_write_permits(session_hash);
alter table rm_private.catalog_workshop_write_settings enable row level security;
alter table rm_private.catalog_workshop_write_permits enable row level security;
revoke all on rm_private.catalog_workshop_write_settings,rm_private.catalog_workshop_write_permits from public,anon,authenticated,service_role;

create function public.rm_sso_catalog_workshop_permit_v1(p_session_hash text,p_submission_id uuid,p_operation text,p_payload jsonb,p_context jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare binding rm_private.sso_identity_bindings;sess rm_private.sso_sessions;workshop jsonb;principal jsonb;
 issued timestamptz;expires timestamptz;office uuid;stamp timestamptz;
begin
 if p_submission_id is null or p_operation is null or p_operation not in('save_catalog','delete_catalog')
  or p_payload is null or jsonb_typeof(p_payload)<>'object' or p_payload->>'kind' is null or p_payload->>'kind' not in('clients','types')
  or p_context is null or jsonb_typeof(p_context)<>'object' or octet_length(p_context::text)>65536 then
  raise exception using errcode='22023',message='Contexto de cadastro inválido.';end if;
 if(select array_agg(k order by k) from jsonb_object_keys(p_context)k) is distinct from
  array['application','authority','channel','expires_at','issued_at','principals','version','workshop']
  or p_context->'version' is distinct from '2'::jsonb or p_context->>'application' is distinct from 'em'
  or p_context->>'channel' is distinct from 'web' or p_context->>'authority' is distinct from 'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
  or jsonb_typeof(p_context->'workshop') is distinct from 'object' or jsonb_typeof(p_context->'principals') is distinct from 'array' then
  raise exception using errcode='22023',message='Autoridade de oficina inválida.';end if;
 if jsonb_array_length(p_context->'principals')<>1 then raise exception using errcode='22023',message='Identidade de oficina inválida.';end if;
 workshop:=p_context->'workshop';principal:=p_context->'principals'->0;
 if jsonb_typeof(principal) is distinct from 'object' then raise exception using errcode='22023',message='Identidade de oficina inválida.';end if;
 if(select array_agg(k order by k) from jsonb_object_keys(workshop)k) is distinct from array['active','code','id','name','revision','updated_at']
  or(select array_agg(k order by k) from jsonb_object_keys(principal)k) is distinct from array['issuer','kind','revision','subject']
  or workshop->'active' is distinct from 'true'::jsonb or principal->>'kind' is distinct from 'corporate'
  or principal->>'issuer' is distinct from 'https://kxoriwvzmxhatzqcgnht.supabase.co/auth/v1'
  or jsonb_typeof(workshop->'id') is distinct from 'string' or jsonb_typeof(workshop->'code') is distinct from 'string'
  or jsonb_typeof(workshop->'name') is distinct from 'string' or length(workshop->>'name') not between 1 and 200
  or workshop->>'name'<>btrim(workshop->>'name') or workshop->>'name' ~ '[[:cntrl:]]'
  or jsonb_typeof(workshop->'revision') is distinct from 'number' or jsonb_typeof(principal->'revision') is distinct from 'number'
  or workshop->>'revision' !~ '^[1-9][0-9]{0,15}$' or principal->>'revision' !~ '^[1-9][0-9]{0,15}$'
  or(workshop->>'revision')::numeric>9007199254740991 or(principal->>'revision')::numeric>9007199254740991
  or jsonb_typeof(p_context->'issued_at') is distinct from 'string' or jsonb_typeof(p_context->'expires_at') is distinct from 'string'
  or jsonb_typeof(workshop->'updated_at') is distinct from 'string' then
  raise exception using errcode='22023',message='Oficina ou revisão inválida.';end if;
 issued:=(p_context->>'issued_at')::timestamptz;expires:=(p_context->>'expires_at')::timestamptz;
 perform(workshop->>'updated_at')::timestamptz;
 select id into office from rm_private.workshop_references where id=(workshop->>'id')::uuid and code=workshop->>'code'
  and authority=p_context->>'authority';
 if office is null then raise exception using errcode='42501',message='Oficina autoritativa não reconhecida.';end if;
 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=p_session_hash for share of b;
 if not found or not binding.enabled or principal->>'subject' is distinct from binding.subject::text
  or binding.issuer is distinct from p_context->>'authority' then
  raise exception using errcode='42501',message='Oficina não corresponde à identidade autenticada.';end if;
 select * into sess from rm_private.sso_sessions where hash=p_session_hash for share;
 stamp:=clock_timestamp();
 if not found or sess.binding_id<>binding.id or sess.expires_at<=stamp or not isfinite(issued) or not isfinite(expires)
  or abs(extract(epoch from stamp-issued))>15 or expires<=stamp or expires<=issued or expires>issued+interval '5 minutes' then
  raise exception using errcode='42501',message='Contexto de oficina expirado ou indisponível.';end if;
 -- The existing action permit still validates the real local SSO binding,
 -- session and operation capability. No new capability is granted here.
 perform public.rm_sso_action_permit_v1(p_session_hash,p_submission_id,p_operation,p_payload,'em.catalogs.manage');
 insert into rm_private.catalog_workshop_write_permits(submission_id,session_hash,operation,payload_hash,workshop_id,subject,context,expires_at)
  select p_submission_id,p_session_hash,p_operation,extensions.digest(p_payload::text,'sha256'),office,binding.subject,p_context,
   least(expires,sess.expires_at,a.expires_at,clock_timestamp()+interval '15 seconds')
  from rm_private.sso_action_permits a where a.submission_id=p_submission_id
 on conflict(submission_id) do update set context=excluded.context,expires_at=excluded.expires_at,created_at=clock_timestamp()
 where rm_private.catalog_workshop_write_permits.session_hash=excluded.session_hash
  and rm_private.catalog_workshop_write_permits.operation=excluded.operation
  and rm_private.catalog_workshop_write_permits.payload_hash=excluded.payload_hash
  and rm_private.catalog_workshop_write_permits.workshop_id=excluded.workshop_id
  and rm_private.catalog_workshop_write_permits.subject=excluded.subject;
 if not found then raise exception using errcode='23505',message='Protocolo já vinculado a outra oficina ou operação.';end if;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
 raise exception using errcode='22023',message='Contexto de cadastro inválido.';
end;
$$;
revoke all on function public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

create function rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare permit rm_private.catalog_workshop_write_permits;sess rm_private.sso_sessions;binding rm_private.sso_identity_bindings;
 scope_enforced boolean;kind text;object_key uuid;business_table text;existing boolean;owner_office uuid;retired boolean;result jsonb;
begin
 if p_operation is null or p_operation not in('save_catalog','delete_catalog') or p_payload->>'kind' is null or p_payload->>'kind' not in('clients','types') then
  return rm_private.web_mutate_core_v1(p_client_submission_id,p_operation,p_payload);end if;
 select enforced into scope_enforced from rm_private.catalog_workshop_write_settings where singleton for share;
 select * into permit from rm_private.catalog_workshop_write_permits where submission_id=p_client_submission_id;
 if not found then
  if coalesce(scope_enforced,true) then raise exception using errcode='42501',message='Confirme a oficina em uma sessão web atual antes de salvar.';end if;
  return rm_private.web_mutate_core_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 -- The public 016 wrapper already holds session/identity locks and has consumed
 -- its normal action permit. This independent permit survives that consumption.
 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=permit.session_hash for share of b;
 if not found then raise exception using errcode='42501',message='Sessão de oficina indisponível.';end if;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 if not found then raise exception using errcode='42501',message='Sessão de oficina indisponível.';end if;
 select * into permit from rm_private.catalog_workshop_write_permits where submission_id=p_client_submission_id for update;
 if not found or not binding.enabled or sess.binding_id<>binding.id or permit.session_hash<>sess.hash
  or binding.auth_user_id is distinct from auth.uid() or binding.subject<>permit.subject
  or sess.local_session_id::text is distinct from auth.jwt()->>'session_id' or sess.expires_at<=clock_timestamp()
  or permit.expires_at<=clock_timestamp() or permit.operation<>p_operation
  or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256') then
  raise exception using errcode='42501',message='Confirmação de oficina ausente, expirada ou divergente.';end if;
 kind:=case p_payload->>'kind' when 'clients' then 'client' else 'equipment_type' end;
 business_table:=case kind when 'client' then 'rm_clientes' else 'rm_tipos_equipamento' end;
 object_key:=(p_payload->>'id')::uuid;
 if object_key is null then raise exception using errcode='22023',message='Cadastro inválido.';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-catalog:v1:'||kind||':'||object_key,0)) then
  raise exception using errcode='PT409',message='O cadastro está sendo conferido. Reenvie o mesmo protocolo.';end if;
 select workshop_id into owner_office from rm_private.workshop_catalog_ownership where object_kind=kind and object_id=object_key;
 select exists(select 1 from rm_private.workshop_catalog_retirements where object_kind=kind and object_id=object_key) into retired;
 execute format('select exists(select 1 from public.%I where id=$1)',business_table) into existing using object_key;
 if owner_office is not null and owner_office<>permit.workshop_id or existing and owner_office is null then
  raise exception using errcode='42501',message='Cadastro fora da oficina confirmada ou com origem pendente de revisão.';end if;
 if retired and(p_operation<>'delete_catalog' or not exists(select 1 from rm_private.web_mutation_receipts r
  where r.client_submission_id=p_client_submission_id and r.auth_user_id=auth.uid() and r.operation=p_operation and r.payload=p_payload)) then
  raise exception using errcode='PT410',message='A origem do cadastro foi encerrada. Preserve o protocolo para conferência.';end if;
 result:=rm_private.web_mutate_core_v1(p_client_submission_id,p_operation,p_payload);
 if permit.expires_at<=clock_timestamp() then raise exception using errcode='42501',message='A confirmação de oficina expirou. Reenvie o mesmo protocolo.';end if;
 if p_operation='save_catalog' and owner_office is null then
  insert into rm_private.workshop_catalog_ownership(object_kind,object_id,workshop_id) values(kind,object_key,permit.workshop_id);
 end if;
 return result;
end;
$$;
revoke all on function rm_private.web_mutate_scoped_catalog_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Preserve the public function OID/owner/grants and all 016 authentication,
-- MFA/session/permit rules. Change only its final dispatch target.
do $$declare definition text;needle text:='return rm_private.web_mutate_core_v1(p_client_submission_id,p_operation,p_payload);';begin
 definition:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 if(length(definition)-length(replace(definition,needle,'')))<>length(needle) then raise exception 'Unexpected public mutation dispatch';end if;
 execute replace(definition,needle,'return rm_private.web_mutate_scoped_catalog_v1(p_client_submission_id,p_operation,p_payload);');
end$$;

create function rm_private.activate_catalog_workshop_writes_v1(p_runtime_sha text,p_deployment_id uuid)
returns jsonb language plpgsql set search_path='' as $$
declare settings rm_private.catalog_workshop_write_settings;
begin
 if current_user::regrole<>(select relowner from pg_class where oid='rm_private.catalog_workshop_write_settings'::regclass) then
  raise exception using errcode='42501',message='Technical publication owner required.';end if;
 if p_runtime_sha is null or p_runtime_sha !~ '^[0-9a-f]{40}$' or p_deployment_id is null then raise exception using errcode='22023',message='Verified deployment required.';end if;
 select * into settings from rm_private.catalog_workshop_write_settings where singleton for update;
 if settings.enforced then
  if settings.runtime_sha<>p_runtime_sha or settings.deployment_id<>p_deployment_id then raise exception using errcode='PT409',message='Activation already bound to another deployment.';end if;
  return jsonb_build_object('enforced',true,'replayed',true,'full_isolation_active',false);
 end if;
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso) or not exists(select 1 from rm_private.workshop_catalog_adoption)
  or exists(select 1 from public.rm_clientes x where not exists(select 1 from rm_private.workshop_catalog_ownership o where o.object_kind='client' and o.object_id=x.id))
  or exists(select 1 from public.rm_tipos_equipamento x where not exists(select 1 from rm_private.workshop_catalog_ownership o where o.object_kind='equipment_type' and o.object_id=x.id)) then
  raise exception using errcode='PT409',message='Catalog ownership or SSO prerequisites incomplete; preserve current records.';end if;
 update rm_private.catalog_workshop_write_settings set enforced=true,runtime_sha=p_runtime_sha,deployment_id=p_deployment_id,
  activated_at=clock_timestamp(),database_actor=session_user where singleton;
 return jsonb_build_object('enforced',true,'replayed',false,'full_isolation_active',false);
end;
$$;
revoke all on function rm_private.activate_catalog_workshop_writes_v1(text,uuid) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
