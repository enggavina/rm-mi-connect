begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.receiving_draft_workshops (
 draft_id uuid primary key references rm_private.receiving_drafts(id) on delete cascade,
 workshop_id uuid not null references rm_private.workshop_references(id),
 assigned_at timestamptz not null default clock_timestamp()
);
create table rm_private.receiving_draft_workshop_permits (
 request_id uuid primary key,
 auth_user_id uuid not null,
 auth_session_id uuid not null,
 operator_id uuid not null,
 operator_hash bytea not null,
 arguments_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 expires_at timestamptz not null
);
create index receiving_draft_workshop_permits_expiry on rm_private.receiving_draft_workshop_permits(expires_at);
alter table rm_private.receiving_draft_workshops enable row level security;
alter table rm_private.receiving_draft_workshop_permits enable row level security;
revoke all on rm_private.receiving_draft_workshops,rm_private.receiving_draft_workshop_permits from public,anon,authenticated,service_role;

create function rm_private.receiving_draft_evidence_workshop_v1(p_draft uuid,p_payload jsonb) returns uuid
language plpgsql stable set search_path='' as $$
declare anchored uuid; project uuid; client_id uuid; project_office uuid; client_office uuid;
begin
 select w.workshop_id into anchored from rm_private.receiving_draft_workshops w where w.draft_id=p_draft;
 if anchored is not null then return anchored;end if;
 select a.workshop_id into project_office from rm_private.receiving_openings o
  join rm_private.workshop_project_ownership a on a.id=o.project_id where o.client_submission_id=p_draft;
 if project_office is not null then return project_office;end if;
 project:=nullif(p_payload->>'projeto_id','')::uuid;
 client_id:=nullif(p_payload->>'cliente','')::uuid;
 if project is not null then
  select w.workshop_id into project_office from rm_private.workshop_project_ownership w where w.id=project;
  if project_office is null then return null;end if;
 end if;
 if client_id is not null then
  client_office:=rm_private.workshop_catalog_scope_v1('client',client_id);
  if client_office is null or (project_office is not null and project_office<>client_office) then return null;end if;
 end if;
 return coalesce(project_office,client_office);
exception when invalid_text_representation then return null;
end
$$;
revoke all on function rm_private.receiving_draft_evidence_workshop_v1(uuid,jsonb) from public,anon,authenticated,service_role;

create function public.rm_authorize_receiving_draft_workshop_v1(p_auth_user_id uuid,p_session_id uuid,p_operator_token text,
 p_workshop_context jsonb,p_request_id uuid,p_args jsonb) returns void
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare identity record; office uuid; deadline timestamptz;
begin
 if p_request_id is null or jsonb_typeof(p_args) is distinct from 'object' or octet_length(p_args::text)>1065000
  or coalesce(p_args->>'action','') not in('read','save') then raise exception 'Consulta de rascunho inválida.' using errcode='22023';end if;
 select * into identity from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token);
 if not found then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 office:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,identity.operator_subject);
 if office is null then raise exception 'Oficina indisponível.' using errcode='42501';end if;
 deadline:=least(identity.expires_at,(p_workshop_context->>'expires_at')::timestamptz,
  (p_workshop_context->>'issued_at')::timestamptz+interval '15 seconds');
 if deadline<=clock_timestamp() then raise exception 'Confirme novamente a oficina.' using errcode='PT503';end if;
 delete from rm_private.receiving_draft_workshop_permits where expires_at<clock_timestamp()-interval '5 minutes';
 insert into rm_private.receiving_draft_workshop_permits values(p_request_id,p_auth_user_id,p_session_id,identity.operator_subject,
  extensions.digest(p_operator_token,'sha256'),extensions.digest(p_args::text,'sha256'),office,deadline);
end
$$;
revoke all on function public.rm_authorize_receiving_draft_workshop_v1(uuid,uuid,text,jsonb,uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_authorize_receiving_draft_workshop_v1(uuid,uuid,text,jsonb,uuid,jsonb) to service_role;

create function public.rm_mobile_receiving_draft_workshop_v1(p_request_id uuid,p_args jsonb,p_operator_token text) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare scope rm_private.receiving_draft_workshop_permits; identity record; previous rm_private.receiving_drafts;
 draft uuid; action text; snapshot jsonb; related_project uuid; customer uuid; value jsonb;
begin
 if auth.uid() is null or auth.jwt()->>'session_id' is null then raise exception 'Sessão indisponível.' using errcode='28000';end if;
 select * into identity from rm_private.online_operator_identity_v1(auth.uid(),(auth.jwt()->>'session_id')::uuid,p_operator_token);
 if not found then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 select * into scope from rm_private.receiving_draft_workshop_permits where request_id=p_request_id for update;
 if not found or scope.auth_user_id is distinct from auth.uid() or scope.auth_session_id::text is distinct from auth.jwt()->>'session_id'
  or scope.operator_id is distinct from identity.operator_subject or scope.operator_hash is distinct from extensions.digest(p_operator_token,'sha256')
  or scope.arguments_hash is distinct from extensions.digest(p_args::text,'sha256') or scope.expires_at<=clock_timestamp() then
  raise exception 'Confirmação da oficina indisponível.' using errcode='42501';
 end if;
 draft:=nullif(p_args->>'draftId','')::uuid;
 action:=p_args->>'action';
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||scope.auth_user_id||':'||scope.operator_id,45));
 if action='read' and draft is null then
  select * into previous from rm_private.receiving_drafts d where d.auth_user_id=scope.auth_user_id and d.operator_id=scope.operator_id and d.state='draft';
 elsif draft is not null then
  select * into previous from rm_private.receiving_drafts d where d.id=draft and d.auth_user_id=scope.auth_user_id and d.operator_id=scope.operator_id;
 end if;
 if previous.id is not null and rm_private.receiving_draft_evidence_workshop_v1(previous.id,previous.payload) is distinct from scope.workshop_id then
  raise exception 'A oficina original do rascunho precisa ser conferida.' using errcode='42501';
 end if;
 if action='read' then
  if previous.id is not null then value:=rm_private.receiving_draft_dto_v1(previous);end if;
 elsif action='save' and draft is not null then
  snapshot:=p_args->'payload';
  related_project:=nullif(snapshot->>'projeto_id','')::uuid;
  customer:=nullif(snapshot->>'cliente','')::uuid;
  if related_project is not null and not rm_private.workshop_project_owned_v1(related_project,scope.workshop_id)
   or customer is not null and rm_private.workshop_catalog_scope_v1('client',customer) is distinct from scope.workshop_id then
   raise exception 'O cliente ou projeto pertence a outra oficina.' using errcode='42501';
  end if;
  value:=public.rm_receiving_draft_v1(p_operator_token,'save',draft,snapshot,(p_args->>'expectedRevision')::bigint,(p_args->>'saveId')::uuid);
  insert into rm_private.receiving_draft_workshops(draft_id,workshop_id) values(draft,scope.workshop_id) on conflict(draft_id) do nothing;
 else
  raise exception 'Operação de rascunho inválida.' using errcode='22023';
 end if;
 if scope.expires_at<=clock_timestamp() then raise exception 'Autorize novamente a operação.' using errcode='PT503';end if;
 delete from rm_private.receiving_draft_workshop_permits where request_id=p_request_id;
 return value;
exception when invalid_text_representation then raise exception 'Identificadores do rascunho inválidos.' using errcode='22023';
end
$$;
revoke all on function public.rm_mobile_receiving_draft_workshop_v1(uuid,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_receiving_draft_workshop_v1(uuid,jsonb,text) to authenticated;

do $opening$
declare definition text:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 marker constant text:=' select o.project_id into linked_project';
begin
 if array_length(string_to_array(definition,marker),1) is distinct from 2 then raise exception 'Unexpected opening workshop validation';end if;
 execute replace(definition,marker,$extra$ if exists(select 1 from rm_private.receiving_draft_workshops w
  where w.draft_id=p_client_submission_id and w.workshop_id is distinct from permit.workshop_id) then
  raise exception 'O rascunho pertence a outra oficina.' using errcode='42501';
 end if;
$extra$||marker);
end
$opening$;
notify pgrst,'reload schema';
commit;
