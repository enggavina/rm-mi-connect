begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.root_creation_settings (
 singleton boolean primary key default true check(singleton),
 deployment_id uuid, runtime_sha text, activated_at timestamptz,
 check((deployment_id is null and runtime_sha is null and activated_at is null)
    or (deployment_id is not null and runtime_sha is not null and runtime_sha ~ '^[0-9a-f]{40}$' and activated_at is not null))
);
insert into rm_private.root_creation_settings(singleton) values(true);

create table rm_private.root_creation_permits (
 submission_id uuid primary key,
 session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 operation text not null check(operation in('save_project_with_equipment','save_catalog','delete_catalog')),
 payload_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 subject uuid not null,
 context jsonb not null,
 expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp()
);
create index root_creation_permits_session on rm_private.root_creation_permits(session_hash);
alter table rm_private.root_creation_settings enable row level security;
alter table rm_private.root_creation_permits enable row level security;
revoke all on rm_private.root_creation_settings,rm_private.root_creation_permits from public,anon,authenticated,service_role;

create function rm_private.web_root_write_kind_v1(p_operation text,p_payload jsonb)
returns text language sql immutable set search_path='' as $$
 select case when p_operation='delete_catalog' and p_payload->>'kind'='cells' then 'cell'
 when p_payload->'expected_updated_at' = 'null'::jsonb then
   case
    when p_operation='save_project_with_equipment' then 'project'
    when p_operation='save_catalog' and p_payload->>'kind'='cells' then 'cell'
   end
 end;
$$;

-- Reuse the established Acessos context, session and expiry validator.
do $build$
declare
 definition text:=pg_get_functiondef('public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 operation_check text:='p_operation not in(''save_catalog'',''delete_catalog'')';
 payload_check text:=' or p_payload->>''kind'' is null or p_payload->>''kind'' not in(''clients'',''types'')';
 action_capability text:='p_payload,''em.catalogs.manage'')';
begin
 if strpos(definition,operation_check)=0 or strpos(definition,payload_check)=0 or strpos(definition,action_capability)=0 then
   raise exception 'Unexpected workshop authority validator';
 end if;
 definition:=replace(definition,'public.rm_sso_catalog_workshop_permit_v1(','public.rm_sso_root_creation_permit_v1(');
 definition:=replace(definition,operation_check,'rm_private.web_root_write_kind_v1(p_operation,p_payload) is null');
 definition:=replace(definition,payload_check,'');
 definition:=replace(definition,action_capability,
   'p_payload,case when p_operation in(''save_catalog'',''delete_catalog'') then ''em.catalogs.manage'' else ''em.projects.manage'' end)');
 definition:=replace(definition,'catalog_workshop_write_permits','root_creation_permits');
 execute definition;
end
$build$;
revoke all on function public.rm_sso_root_creation_permit_v1(text,uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_root_creation_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

create function rm_private.web_mutate_root_creation_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare
 kind text:=rm_private.web_root_write_kind_v1(p_operation,p_payload);
 retiring boolean:=p_operation='delete_catalog';
 permit rm_private.root_creation_permits;
 binding rm_private.sso_identity_bindings;
 sess rm_private.sso_sessions;
 root_id uuid;
 office uuid;
 root_exists boolean;
 result jsonb;
begin
 if kind is null then
  return rm_private.web_mutate_scoped_templates_v1(p_client_submission_id,p_operation,p_payload);
 end if;

 select * into permit from rm_private.root_creation_permits where submission_id=p_client_submission_id;
 if not found then
  -- The migration precedes the Railway deployment. Once activated, an ordinary
  -- SSO action permit alone can no longer create an unclassified web root.
  if exists(select 1 from rm_private.root_creation_settings where singleton and deployment_id is null for share) then
   return rm_private.web_mutate_scoped_templates_v1(p_client_submission_id,p_operation,p_payload);
  end if;
  raise exception 'Confirme a oficina antes de gravar o registro.' using errcode='42501';
 end if;

 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=permit.session_hash for share of b;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 select * into permit from rm_private.root_creation_permits where submission_id=p_client_submission_id for update;
 if not found or not coalesce(binding.enabled,false) or sess.binding_id is distinct from binding.id
  or permit.session_hash is distinct from sess.hash or permit.subject is distinct from binding.subject
  or binding.auth_user_id is distinct from auth.uid()
  or sess.local_session_id::text is distinct from auth.jwt()->>'session_id'
  or sess.expires_at<=clock_timestamp() or permit.expires_at<=clock_timestamp()
  or permit.operation is distinct from p_operation or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256') then
  raise exception 'Confirmação de oficina ausente, expirada ou divergente.' using errcode='42501';
 end if;

 begin
  root_id:=(p_payload->>'id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Identificador de origem inválido.' using errcode='22023';
 end;
 if root_id is null then raise exception 'Identificador inválido.' using errcode='22023'; end if;
 if not pg_try_advisory_xact_lock(hashtextextended('em:workshop-origin:v1:'||kind||':'||root_id,0)) then
  raise exception 'Origem em conferência. Reenvie o mesmo protocolo.' using errcode='PT409';
 end if;
 if retiring then
  select workshop_id into office from rm_private.workshop_object_origins where object_kind='cell' and object_id=root_id;
  if office is distinct from permit.workshop_id then
   raise exception 'Célula fora da oficina confirmada ou com origem pendente.' using errcode='42501';
  end if;
 else
  office:=rm_private.workshop_catalog_scope_v1(kind,root_id);
  if kind='project' then
   select exists(select 1 from public.rm_projetos where id=root_id) into root_exists;
  else
   select exists(select 1 from public.rm_celulas where id=root_id) into root_exists;
  end if;
  if (office is not null or root_exists) and office is distinct from permit.workshop_id then
   raise exception 'Registro fora da oficina confirmada ou com origem pendente.' using errcode='42501';
  end if;
 end if;

 result:=rm_private.web_mutate_scoped_templates_v1(p_client_submission_id,p_operation,p_payload);
 if office is null then
  if kind='project' then
   insert into rm_private.workshop_project_ownership(id,workshop_id) values(root_id,permit.workshop_id);
  else
   insert into rm_private.workshop_cell_ownership(cell_id,workshop_id) values(root_id,permit.workshop_id);
  end if;
 end if;
 if permit.expires_at<=clock_timestamp() or sess.expires_at<=clock_timestamp() then
  raise exception 'A confirmação de oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';
 end if;
 delete from rm_private.root_creation_permits where submission_id=p_client_submission_id;
 return result;
end
$$;

do $dispatch$
declare
 definition text:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 target text:='return rm_private.web_mutate_scoped_templates_v1(p_client_submission_id,p_operation,p_payload);';
begin
 if length(definition)-length(replace(definition,target,''))<>length(target) then
  raise exception 'Unexpected web mutation dispatch';
 end if;
 execute replace(definition,target,'return rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);');
end
$dispatch$;

-- Cell ownership is lifecycle metadata. Its FK cascades and the existing
-- ownership trigger retains the durable origin. Real dependencies still block deletion.
do $catalog$
declare
 definition text:=pg_get_functiondef('rm_private.web_mutate_catalog_core_v1(uuid,text,jsonb)'::regprocedure);
 target text:='where f.contype=''f'' and f.confrelid=target_oid and cardinality(f.conkey)=1';
begin
 if length(definition)-length(replace(definition,target,''))<>length(target) then
  raise exception 'Unexpected catalog reference guard';
 end if;
 execute replace(definition,target,target||$guard$ and f.conrelid<>'rm_private.workshop_cell_ownership'::regclass$guard$);
end
$catalog$;

create function rm_private.activate_root_creation_v1(p_runtime_sha text,p_deployment_id uuid)
returns void language plpgsql set search_path='' as $$
declare active rm_private.root_creation_settings;
begin
 if p_runtime_sha is null or p_runtime_sha !~ '^[0-9a-f]{40}$' or p_deployment_id is null then
  raise exception 'Informe a versão publicada do portal.' using errcode='22023';
 end if;
 if not exists(select 1 from rm_private.sso_settings where singleton and require_sso) then
  raise exception 'O portal deve exigir SSO antes de ativar a origem.' using errcode='PT409';
 end if;
 select * into strict active from rm_private.root_creation_settings where singleton for update;
 if active.deployment_id is not null and (active.deployment_id<>p_deployment_id or active.runtime_sha<>p_runtime_sha) then
  raise exception 'A criação por oficina já foi ativada.' using errcode='PT409';
 end if;
 update rm_private.root_creation_settings
 set deployment_id=p_deployment_id,runtime_sha=p_runtime_sha,activated_at=clock_timestamp()
 where singleton and deployment_id is null;
end
$$;

revoke all on function rm_private.web_root_write_kind_v1(text,jsonb),
 rm_private.web_mutate_root_creation_v1(uuid,text,jsonb),rm_private.activate_root_creation_v1(text,uuid)
 from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
