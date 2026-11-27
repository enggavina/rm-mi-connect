begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.mobile_workshop_mutation_permits (
 submission_id uuid not null,
 rpc_name text not null check(rpc_name in('rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_record_cell_photo_v1',
  'rm_transition_stage_approval_v1','rm_update_cell_status_v1','rm_add_cell_comment_v1','rm_record_execution_event_v1')),
 auth_user_id uuid not null,
 auth_session_id uuid not null,
 operator_id uuid not null,
 operator_hash bytea not null,
 payload_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 expires_at timestamptz not null,
 primary key(submission_id,rpc_name)
);
alter table rm_private.mobile_workshop_mutation_permits enable row level security;
revoke all on rm_private.mobile_workshop_mutation_permits from public,anon,authenticated,service_role;

create function rm_private.mobile_mutation_workshop_project_v1(p_rpc text,p_params jsonb,p_office uuid) returns uuid
language plpgsql stable set search_path='' as $$
declare project uuid; cell uuid; form_model uuid; target uuid;
begin
 case p_rpc
 when 'rm_submit_form_inspection_v1' then
  project:=(p_params->>'p_projeto_id')::uuid; cell:=(p_params->>'p_celula_id')::uuid; form_model:=(p_params->>'p_form_id')::uuid;
 when 'rm_submit_form_revision_v1' then
  select r.projeto_id,r.celula_id,r.form_id into project,cell,form_model from public.rm_registros_formulario r
   where r.id=(p_params->>'p_registro_formulario_id')::uuid;
 when 'rm_transition_stage_approval_v1' then
  target:=(p_params->>'p_aprovacao_etapa_id')::uuid;
  if not rm_private.workshop_stage_owned_v1(target,p_office) then return null;end if;
  select s.projeto_id,s.celula_origem_id into project,cell from public.rm_aprovacoes_etapas s where s.id=target;
 when 'rm_record_cell_photo_v1' then
  if nullif(p_params->>'p_cadastro_foto_id','') is not null then return null;end if;
  target:=nullif(p_params->>'p_foto_id','')::uuid;
  if target is not null then
   select f.projeto_id,f.celula_id into project,cell from public.rm_fotos f where f.id=target and not f.lixeira
    and (f.celula_projeto_id is null or exists(select 1 from public.rm_celulas_projeto a
     where a.id=f.celula_projeto_id and a.projeto_id=f.projeto_id and a.celula_id=f.celula_id));
  else
   project:=(p_params->>'p_projeto_id')::uuid; cell:=(p_params->>'p_celula_id')::uuid;
  end if;
  if (nullif(p_params->>'p_projeto_id','') is not null and (p_params->>'p_projeto_id')::uuid is distinct from project)
   or (nullif(p_params->>'p_celula_id','') is not null and (p_params->>'p_celula_id')::uuid is distinct from cell)
   or (nullif(p_params->>'p_celula_projeto_id','') is not null and not exists(select 1 from public.rm_celulas_projeto a
    where a.id=(p_params->>'p_celula_projeto_id')::uuid and a.projeto_id=project and a.celula_id=cell)) then return null;end if;
 when 'rm_record_execution_event_v1','rm_update_cell_status_v1','rm_add_cell_comment_v1' then
  target:=(p_params->>case when p_rpc='rm_record_execution_event_v1' then 'p_allocation_id' else 'p_celula_projeto_id' end)::uuid;
  select a.projeto_id,a.celula_id into project,cell from public.rm_celulas_projeto a where a.id=target;
 else return null;
 end case;
 if not rm_private.workshop_project_owned_v1(project,p_office) or not rm_private.workshop_cell_owned_v1(cell,p_office)
  or (p_rpc in('rm_submit_form_inspection_v1','rm_submit_form_revision_v1')
    and not rm_private.workshop_read_owned_v1('form_model',form_model,p_office)) then return null;end if;
 return project;
exception when invalid_text_representation then
 raise exception 'Projeto, célula ou registro inválido.' using errcode='22023';
end
$$;
revoke all on function rm_private.mobile_mutation_workshop_project_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

create function public.rm_authorize_mobile_workshop_mutation_v1(
 p_auth_user_id uuid,p_session_id uuid,p_operator_token text,p_workshop_context jsonb,
 p_client_submission_id uuid,p_rpc_name text,p_params jsonb
) returns void language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare identity record; office uuid; deadline timestamptz;
begin
 if p_client_submission_id is null or p_rpc_name is null or p_rpc_name not in(
  'rm_submit_form_inspection_v1','rm_submit_form_revision_v1','rm_record_cell_photo_v1','rm_transition_stage_approval_v1',
  'rm_update_cell_status_v1','rm_add_cell_comment_v1','rm_record_execution_event_v1')
  or jsonb_typeof(p_params) is distinct from 'object' or octet_length(p_params::text)>2097152 then
  raise exception 'Dados do protocolo inválidos.' using errcode='22023';
 end if;
 select * into identity from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token);
 if not found then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 office:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,identity.operator_subject);
 if office is null or rm_private.mobile_mutation_workshop_project_v1(p_rpc_name,p_params,office) is null then
  raise exception 'Registro indisponível nesta oficina.' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
 deadline:=least(identity.expires_at,(p_workshop_context->>'expires_at')::timestamptz,
  (p_workshop_context->>'issued_at')::timestamptz+interval '15 seconds');
 if deadline<=clock_timestamp() then raise exception 'Confirme novamente a oficina.' using errcode='PT503';end if;
 insert into rm_private.mobile_workshop_mutation_permits as a(submission_id,rpc_name,auth_user_id,
  auth_session_id,operator_id,operator_hash,payload_hash,workshop_id,expires_at)
 values(p_client_submission_id,p_rpc_name,p_auth_user_id,p_session_id,identity.operator_subject,
  extensions.digest(p_operator_token,'sha256'),extensions.digest(p_params::text,'sha256'),office,deadline)
 on conflict(submission_id,rpc_name) do update set auth_session_id=excluded.auth_session_id,
  operator_hash=excluded.operator_hash,expires_at=excluded.expires_at
 where a.auth_user_id=excluded.auth_user_id and a.operator_id=excluded.operator_id
  and a.payload_hash=excluded.payload_hash and a.workshop_id=excluded.workshop_id;
 if not found then raise exception 'O protocolo pertence a outro registro.' using errcode='PT409';end if;
end
$$;
revoke all on function public.rm_authorize_mobile_workshop_mutation_v1(uuid,uuid,text,jsonb,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_authorize_mobile_workshop_mutation_v1(uuid,uuid,text,jsonb,uuid,text,jsonb) to service_role;

create function public.rm_mobile_workshop_mutate_v1(p_client_submission_id uuid,p_rpc_name text,p_params jsonb,p_operator_token text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare permit rm_private.mobile_workshop_mutation_permits; identity record; project uuid; result jsonb;
begin
 if auth.uid() is null or p_client_submission_id is null or auth.jwt()->>'session_id' is null then
  raise exception 'Sessão do dispositivo ou protocolo indisponível.' using errcode='42501';
 end if;
 select * into identity from rm_private.online_operator_identity_v1(auth.uid(),(auth.jwt()->>'session_id')::uuid,p_operator_token);
 if identity.operator_subject is null then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
 select * into permit from rm_private.mobile_workshop_mutation_permits where submission_id=p_client_submission_id and rpc_name=p_rpc_name for update;
 if not found or permit.auth_user_id is distinct from auth.uid() or permit.auth_session_id::text is distinct from auth.jwt()->>'session_id'
  or permit.operator_id is distinct from identity.operator_subject or permit.operator_hash is distinct from extensions.digest(p_operator_token,'sha256')
  or permit.payload_hash is distinct from extensions.digest(p_params::text,'sha256') or permit.expires_at<=clock_timestamp() then
  raise exception 'Confirmação da oficina ausente, expirada ou divergente.' using errcode='42501';
 end if;

 project:=rm_private.mobile_mutation_workshop_project_v1(p_rpc_name,p_params,permit.workshop_id);
 if project is null then raise exception 'Registro indisponível nesta oficina.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(project::text,11));
 if rm_private.mobile_mutation_workshop_project_v1(p_rpc_name,p_params,permit.workshop_id) is distinct from project then
  raise exception 'O contexto da oficina mudou. Preserve o protocolo para conferência.' using errcode='42501';
 end if;
 result:=public.rm_mobile_mutate_v1(p_client_submission_id,p_rpc_name,p_params,p_operator_token);
 if permit.expires_at<=clock_timestamp() then raise exception 'A confirmação expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
 delete from rm_private.mobile_workshop_mutation_permits where submission_id=p_client_submission_id and rpc_name=p_rpc_name;
 return result;
end
$$;
revoke all on function public.rm_mobile_workshop_mutate_v1(uuid,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_workshop_mutate_v1(uuid,text,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
