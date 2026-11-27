begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.form_review_workshop_settings (
 singleton boolean primary key default true check(singleton),
 enforced boolean not null default false
);
insert into rm_private.form_review_workshop_settings(singleton) values(true);
create table rm_private.form_review_workshop_permits (
 submission_id uuid primary key,
 session_hash text not null references rm_private.sso_sessions(hash) on delete cascade,
 operation text not null check(operation='review_form'),
 payload_hash bytea not null,
 workshop_id uuid not null references rm_private.workshop_references(id),
 subject uuid not null,
 context jsonb not null,
 expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp()
);
create index form_review_workshop_permits_session on rm_private.form_review_workshop_permits(session_hash);
alter table rm_private.form_review_workshop_settings enable row level security;
alter table rm_private.form_review_workshop_permits enable row level security;
revoke all on rm_private.form_review_workshop_settings,rm_private.form_review_workshop_permits from public,anon,authenticated,service_role;

do $issuer$
declare
 definition text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 operations text:='p_operation not in(''save_gantt_plan'',''save_gantt_settings'')';
 capability text:='''em.planning.manage''';
begin
 if array_length(string_to_array(definition,operations),1) is distinct from 2
  or array_length(string_to_array(definition,capability),1) is distinct from 2 then
  raise exception 'Unexpected workshop authority validator';
 end if;
 definition:=replace(definition,'public.rm_sso_gantt_workshop_permit_v1(','public.rm_sso_form_review_workshop_permit_v1(');
 definition:=replace(definition,operations,'p_operation <> ''review_form''');
 definition:=replace(definition,capability,'''em.forms.review''');
 execute replace(definition,'gantt_workshop_write_permits','form_review_workshop_permits');
end
$issuer$;
revoke all on function public.rm_sso_form_review_workshop_permit_v1(text,uuid,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_sso_form_review_workshop_permit_v1(text,uuid,text,jsonb,jsonb) to service_role;

create function rm_private.web_mutate_form_review_workshop_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path='' as $$
declare
 permit rm_private.form_review_workshop_permits;
 binding rm_private.sso_identity_bindings;
 sess rm_private.sso_sessions;
 target_id uuid;
 project_id uuid;
 registration public.rm_registros_formulario;
 result jsonb;
begin
 if p_operation is distinct from 'review_form' then
  return rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into permit from rm_private.form_review_workshop_permits where submission_id=p_client_submission_id;
 if not found then
  if exists(select 1 from rm_private.form_review_workshop_settings where singleton and not enforced for share) then
   return rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id,p_operation,p_payload);
  end if;
  raise exception 'Confirme a oficina antes de revisar o formulário.' using errcode='42501';
 end if;

 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=permit.session_hash for share of b;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into permit from rm_private.form_review_workshop_permits where submission_id=p_client_submission_id for update;
 if not found or not coalesce(binding.enabled,false) or sess.binding_id is distinct from binding.id
  or permit.session_hash is distinct from sess.hash or permit.subject is distinct from binding.subject
  or binding.auth_user_id is distinct from auth.uid() or sess.local_session_id::text is distinct from auth.jwt()->>'session_id'
  or sess.expires_at<=clock_timestamp() or permit.expires_at<=clock_timestamp()
  or permit.operation is distinct from p_operation or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256') then
  raise exception 'Confirmação de oficina ausente, expirada ou divergente.' using errcode='42501';
 end if;

 target_id:=(p_payload->>'registro_formulario_id')::uuid;
 select projeto_id into project_id from public.rm_registros_formulario where id=target_id;
 if not found or not rm_private.workshop_project_owned_v1(project_id,permit.workshop_id) then
  raise exception 'Formulário indisponível nesta oficina.' using errcode='42501';
 end if;
 -- The existing writer locks protocol, project and registration in this order.
 perform pg_advisory_xact_lock(hashtextextended(project_id::text,11));
 perform 1 from public.rm_projetos where id=project_id for update;
 select * into registration from public.rm_registros_formulario where id=target_id for update;
 if not found or registration.projeto_id is distinct from project_id
  or not rm_private.workshop_form_record_owned_v1(registration.projeto_id,registration.celula_id,registration.form_id,permit.workshop_id) then
  raise exception 'Formulário indisponível nesta oficina.' using errcode='42501';
 end if;
 result:=rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id,p_operation,p_payload);
 if permit.expires_at<=clock_timestamp() or sess.expires_at<=clock_timestamp() then
  raise exception 'A confirmação de oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';
 end if;
 delete from rm_private.form_review_workshop_permits where submission_id=p_client_submission_id;
 return result;
exception when invalid_text_representation then
 raise exception 'Formulário inválido.' using errcode='22023';
end
$$;
revoke all on function rm_private.web_mutate_form_review_workshop_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

do $dispatch$
declare
 definition text:=pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
 target text:='return rm_private.web_mutate_gantt_workshop_v1(p_client_submission_id,p_operation,p_payload);';
begin
 if array_length(string_to_array(definition,target),1) is distinct from 2 then raise exception 'Unexpected web mutation dispatch';end if;
 execute replace(definition,target,'return rm_private.web_mutate_form_review_workshop_v1(p_client_submission_id,p_operation,p_payload);');
end
$dispatch$;

create function rm_private.activate_form_review_workshop_writes_v1()
returns void language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from rm_private.workshop_root_enforcement where singleton and activated_at is not null) then
  raise exception 'Conclua a ativação da origem antes de habilitar a revisão por oficina.' using errcode='PT409';
 end if;
 update rm_private.form_review_workshop_settings set enforced=true where singleton and not enforced;
end
$$;
revoke all on function rm_private.activate_form_review_workshop_writes_v1() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
