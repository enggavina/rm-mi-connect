begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.gantt_workshop_write_settings (
 singleton boolean primary key default true check(singleton),
 enforced boolean not null default false
);
insert into rm_private.gantt_workshop_write_settings(singleton) values(true);
create table rm_private.gantt_workshop_write_permits (
 submission_id uuid primary key,
 session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 operation text not null check(operation in('save_gantt_plan','save_gantt_settings')),
 payload_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 subject uuid not null,
 context jsonb not null,
 expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp()
);
create index gantt_workshop_permits_session on rm_private.gantt_workshop_write_permits(session_hash);
alter table rm_private.gantt_workshop_write_settings enable row level security;
alter table rm_private.gantt_workshop_write_permits enable row level security;
revoke all on rm_private.gantt_workshop_write_settings,rm_private.gantt_workshop_write_permits from public,anon,authenticated,service_role;

do $issuer$
declare
 definition text:=pg_get_functiondef('public.rm_sso_catalog_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 operations text:='p_operation not in(''save_catalog'',''delete_catalog'')';
 catalog_kinds text:=' or p_payload->>''kind'' is null or p_payload->>''kind'' not in(''clients'',''types'')';
begin
 if strpos(definition,operations)=0 or strpos(definition,catalog_kinds)=0 then
  raise exception 'Unexpected workshop authority validator';
 end if;
 definition:=replace(definition,'public.rm_sso_catalog_workshop_permit_v1(','public.rm_sso_gantt_workshop_permit_v1(');
 definition:=replace(definition,operations,'p_operation not in(''save_gantt_plan'',''save_gantt_settings'')');
 definition:=replace(definition,catalog_kinds,' or octet_length(p_payload::text)>2097152');
 definition:=replace(definition,'''em.catalogs.manage''','''em.planning.manage''');
 execute replace(definition,'catalog_workshop_write_permits','gantt_workshop_write_permits');
end
$issuer$;
revoke all on function public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

create function rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare
 permit rm_private.gantt_workshop_write_permits;
 binding rm_private.sso_identity_bindings;
 sess rm_private.sso_sessions;
 project_ids uuid[];
 project_id uuid;
 result jsonb;
begin
 if p_operation is null or p_operation not in('save_gantt_plan','save_gantt_settings') then
  return rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id;
 if not found then
  if exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and not enforced for share) then
   return rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);
  end if;
  raise exception 'Confirme a oficina antes de salvar o cronograma.' using errcode='42501';
 end if;

 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=permit.session_hash for share of b;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id for update;
 if not found or not coalesce(binding.enabled,false) or sess.binding_id is distinct from binding.id
  or permit.session_hash is distinct from sess.hash or permit.subject is distinct from binding.subject
  or binding.auth_user_id is distinct from auth.uid() or sess.local_session_id::text is distinct from auth.jwt()->>'session_id'
  or sess.expires_at<=clock_timestamp() or permit.expires_at<=clock_timestamp()
  or permit.operation is distinct from p_operation or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256') then
  raise exception 'Confirmação de oficina ausente, expirada ou divergente.' using errcode='42501';
 end if;

 begin
  if p_operation='save_gantt_settings' then
   project_ids:=array[(p_payload->>'projeto_id')::uuid];
  else
   if jsonb_typeof(p_payload->'projects') is distinct from 'array' or jsonb_array_length(p_payload->'projects') not between 1 and 2000 then
    raise exception 'Informe os projetos do cronograma.' using errcode='22023';
   end if;
   select array_agg(distinct (p->>'id')::uuid order by (p->>'id')::uuid) into project_ids
   from jsonb_array_elements(p_payload->'projects') p;
  end if;
 exception when invalid_text_representation then
  raise exception 'Projeto do cronograma inválido.' using errcode='22023';
 end;
 if array_position(project_ids,null) is not null then
  raise exception 'Informe os projetos do cronograma.' using errcode='22023';
 end if;

 -- Reuse the original writer's lock order and the other operational writers'
 -- project lock. A baseline or calendar can affect more than the visible rows.
 foreach project_id in array project_ids loop
  perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
  perform rm_private.workshop_assert_origin_v1('project',project_id,permit.workshop_id);
  if exists(select 1 from public.rm_celulas_projeto a where a.projeto_id=project_id and not a.retirada
    and not rm_private.workshop_cell_owned_v1(a.celula_id,permit.workshop_id)) then
   raise exception 'Há uma etapa com origem pendente ou de outra oficina.' using errcode='42501';
  end if;
 end loop;
 result:=rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);
 if permit.expires_at<=clock_timestamp() or sess.expires_at<=clock_timestamp() then
  raise exception 'A confirmação de oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';
 end if;
 delete from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id;
 return result;
end
$$;
revoke all on function rm_private.web_mutate_gantt_workshop_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

do $dispatch$
declare
 definition text:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 target text:='return rm_private.web_mutate_root_creation_v1(p_client_submission_id,p_operation,p_payload);';
begin
 if array_length(string_to_array(definition,target),1) is distinct from 2 then raise exception 'Unexpected web mutation dispatch'; end if;
 execute replace(definition,target,'return rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id,p_operation,p_payload);');
end
$dispatch$;

do $read$
declare
 definition text:=pg_get_functiondef('rm_private.workshop_gantt_snapshot_v1(jsonb,uuid)'::regprocedure);
 guard text:='or p_args->''can_manage'' is distinct from ''false''::jsonb';
 editable text:='''can_edit'',false';
begin
 if array_length(string_to_array(definition,guard),1) is distinct from 2
  or array_length(string_to_array(definition,editable),1) is distinct from 2 then
  raise exception 'Unexpected scoped Gantt reader';
 end if;
 definition:=replace(definition,guard,$guard$or jsonb_typeof(p_args->'can_manage') is distinct from 'boolean'
  or (p_args->'can_manage'='true'::jsonb and (p_args->'project_details' is distinct from 'true'::jsonb
    or not exists(select 1 from rm_private.gantt_workshop_write_settings where singleton and enforced)))$guard$);
 execute replace(definition,editable,$edit$'can_edit',p_args->'can_manage'='true'::jsonb
   and p.data_real_de_entrega is null and p.status_pcp is distinct from 'cancelado'::public.rm_status_pcp_enum
   and p.status_pcp is distinct from 'finalizando_para_faturar'::public.rm_status_pcp_enum
   and a.status is distinct from 'finalizado'::public.rm_status_cel_proj_enum
   and a.status is distinct from 'n_a'::public.rm_status_cel_proj_enum
   and not exists(select 1 from public.rm_celulas_projeto current_route
    where current_route.projeto_id=p.id and not current_route.retirada
     and not rm_private.workshop_cell_owned_v1(current_route.celula_id,p_office))$edit$);
end
$read$;

create function rm_private.activate_gantt_workshop_writes_v1()
returns void language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from rm_private.workshop_root_enforcement where singleton and activated_at is not null) then
  raise exception 'Conclua a ativação da origem antes de habilitar as gravações do Gantt.' using errcode='PT409';
 end if;
 update rm_private.gantt_workshop_write_settings set enforced=true where singleton and not enforced;
end
$$;
revoke all on function rm_private.activate_gantt_workshop_writes_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
