begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.receiving_draft_recoveries (
 draft_id uuid primary key references rm_private.receiving_draft_workshops(draft_id) on delete cascade,
 auth_user_id uuid not null,
 operator_id uuid not null,
 original_revision bigint not null check(original_revision=1),
 original_payload_sha256 text not null check(original_payload_sha256 ~ '^[a-f0-9]{64}$'),
 recovered_at timestamptz not null default clock_timestamp()
);
alter table rm_private.receiving_draft_recoveries enable row level security;
revoke all on rm_private.receiving_draft_recoveries from public,anon,authenticated,service_role;

-- Only the original automatic placeholder can be recovered with the current
-- binding. Unknown fields, attachments, another revision or a real arrival
-- time require historical evidence. The caller holds the device/operator lock.
create function rm_private.recover_pristine_receiving_draft_v1(p_draft rm_private.receiving_drafts,p_office uuid)
returns boolean language plpgsql set search_path='' as $$
declare arrival timestamptz;
begin
 if p_draft.state is distinct from 'draft' or p_draft.revision is distinct from 1
  or p_draft.created_at is distinct from p_draft.updated_at
  or p_draft.payload->'submitted' is not null and p_draft.payload->'submitted'<>'false'::jsonb
  or p_draft.payload-array['chegada','submitted'] is distinct from jsonb_build_object(
   'version',2,'id',p_draft.id,'step',0,'cliente','','notaFiscal','','arquivoNotaFiscal','',
   'descricaoEquipamento','','placaMotor','','eventualidades','','equipamento','{}'::jsonb,'fotos','[]'::jsonb)
  or jsonb_typeof(p_draft.payload->'chegada') is distinct from 'string'
  or not coalesce(p_draft.payload->>'chegada' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',false)
  or rm_private.receiving_draft_evidence_workshop_v1(p_draft.id,p_draft.payload) is not null
  or exists(select 1 from rm_private.receiving_openings where client_submission_id=p_draft.id)
  or exists(select 1 from rm_private.mobile_mutation_receipts where client_submission_id=p_draft.id)
  or exists(select 1 from rm_private.mobile_workshop_uploads where submission_id=p_draft.id) then
  return false;
 end if;
 begin
  arrival:=(p_draft.payload->>'chegada')::timestamptz;
 exception when invalid_datetime_format or datetime_field_overflow then
  return false;
 end;
 if abs(extract(epoch from p_draft.created_at-arrival))>30 then return false;end if;

 insert into rm_private.receiving_draft_workshops(draft_id,workshop_id) values(p_draft.id,p_office)
 on conflict(draft_id) do nothing;
 if not found then return false;end if;
 insert into rm_private.receiving_draft_recoveries(draft_id,auth_user_id,operator_id,original_revision,original_payload_sha256)
 values(p_draft.id,p_draft.auth_user_id,p_draft.operator_id,p_draft.revision,encode(sha256(convert_to(p_draft.payload::text,'UTF8')),'hex'));
 return true;
end
$$;
revoke all on function rm_private.recover_pristine_receiving_draft_v1(rm_private.receiving_drafts,uuid) from public,anon,authenticated,service_role;

-- An existing workshop permit is bound to the exact session, operator, phase
-- and body. Unclassified legacy protocols and their replays keep their path.
create function rm_private.require_scoped_receiving_draft_submission_v1(
 p_submission uuid,p_phase text,p_params jsonb,p_operator uuid,p_token text
) returns void language plpgsql set search_path='' as $$
begin
 if exists(select 1 from rm_private.receiving_draft_workshops where draft_id=p_submission)
  and not exists(select 1 from rm_private.mobile_receiving_workshop_permits a
   join rm_private.receiving_draft_workshops w on w.draft_id=a.submission_id and w.workshop_id=a.workshop_id
   where a.submission_id=p_submission and a.phase=p_phase and a.auth_user_id=auth.uid()
    and a.auth_session_id::text=auth.jwt()->>'session_id' and a.operator_id=p_operator
    and a.operator_hash=extensions.digest(p_token,'sha256') and a.payload_hash=extensions.digest(p_params::text,'sha256')
    and a.expires_at>clock_timestamp()) then
  raise exception 'Confirme a oficina do rascunho antes de enviar. O protocolo continua preservado.' using errcode='42501';
 end if;
end
$$;
revoke all on function rm_private.require_scoped_receiving_draft_submission_v1(uuid,text,jsonb,uuid,text) from public,anon,authenticated,service_role;

do $storage$
declare
 definition text:=pg_get_functiondef('public.rm_receiving_draft_v1(text,text,uuid,jsonb,bigint,uuid)'::regprocedure);
 signature constant text:='FUNCTION public.rm_receiving_draft_v1(';
 last_parameter constant text:='p_save_id uuid DEFAULT NULL::uuid)';
 actor_lock constant text:=' perform pg_advisory_xact_lock(hashtextextended(''receiving-draft:''||auth.uid()::text||'':''||d.operator_id::text,45));';
 read_start constant text:=' if p_action=''read'' then';
 read_found constant text:='  if not found then return null;end if;';
 save_found constant text:='  if item.state<>''draft'' then';
 guard constant text:=$guard$  if not p_scoped and exists(select 1 from rm_private.receiving_draft_workshops where draft_id=item.id) then
   raise exception 'Confirme a oficina para acessar o rascunho original.' using errcode='42501';end if;$guard$;
begin
 if exists(select 1 from unnest(array[signature,last_parameter,actor_lock,read_start,read_found,save_found]) needle
  where array_length(string_to_array(definition,needle),1) is distinct from 2) then
  raise exception 'Unexpected legacy receiving draft store';
 end if;
 definition:=replace(definition,signature,'FUNCTION rm_private.receiving_draft_store_v1(');
 definition:=replace(definition,last_parameter,'p_save_id uuid DEFAULT NULL::uuid, p_scoped boolean DEFAULT false)');
 definition:=replace(definition,actor_lock,'');
 definition:=replace(definition,read_start,actor_lock||chr(10)||read_start);
 definition:=replace(definition,read_found,read_found||chr(10)||guard);
 execute replace(definition,save_found,guard||chr(10)||save_found);
end
$storage$;
revoke all on function rm_private.receiving_draft_store_v1(text,text,uuid,jsonb,bigint,uuid,boolean) from public,anon,authenticated,service_role;

create or replace function public.rm_receiving_draft_v1(
 p_operator_token text,p_action text,p_draft_id uuid default null,p_payload jsonb default null,
 p_expected_revision bigint default null,p_save_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return rm_private.receiving_draft_store_v1(p_operator_token,p_action,p_draft_id,p_payload,p_expected_revision,p_save_id,false);
end
$$;

do $gateways$
declare
 definition text;
 previous_rule constant text:=$old$  raise exception 'A oficina original do rascunho precisa ser conferida.' using errcode='42501';$old$;
 store_call constant text:=$old$  value:=public.rm_receiving_draft_v1(p_operator_token,'save',draft,snapshot,(p_args->>'expectedRevision')::bigint,(p_args->>'saveId')::uuid);$old$;
 open_lock constant text:=' perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));';
 actor_lock constant text:=' perform pg_advisory_xact_lock(hashtextextended(''receiving-draft:''||auth.uid()::text||'':''||d.operator_id::text,45));';
begin
 definition:=pg_get_functiondef('public.rm_mobile_receiving_draft_workshop_v1(uuid,jsonb,text)'::regprocedure);
 if array_length(string_to_array(definition,previous_rule),1) is distinct from 2
  or array_length(string_to_array(definition,store_call),1) is distinct from 2 then
  raise exception 'Unexpected scoped receiving draft gateway';
 end if;
 definition:=replace(definition,previous_rule,$patch$  if action is distinct from 'read' or not rm_private.recover_pristine_receiving_draft_v1(previous,scope.workshop_id) then
   raise exception 'A oficina original do rascunho precisa ser conferida.' using errcode='42501';
  end if;$patch$);
 execute replace(definition,store_call,$patch$  value:=rm_private.receiving_draft_store_v1(p_operator_token,'save',draft,snapshot,(p_args->>'expectedRevision')::bigint,(p_args->>'saveId')::uuid,true);$patch$);

 -- Keep the submission, actor, project lock order across both entry paths.
 definition:=pg_get_functiondef('public.rm_mobile_receiving_workshop_v1(uuid,text,jsonb,text)'::regprocedure);
 if array_length(string_to_array(definition,open_lock),1) is distinct from 2 then
  raise exception 'Unexpected scoped receiving submission lock';
 end if;
 execute replace(definition,open_lock,open_lock||$patch$
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||auth.uid()::text||':'||actor.operator_id::text,45));$patch$);

 definition:=pg_get_functiondef('public.rm_mobile_open_receiving_v1(uuid,jsonb,text)'::regprocedure);
 if array_length(string_to_array(definition,open_lock),1) is distinct from 2
  or array_length(string_to_array(definition,actor_lock),1) is distinct from 2 then
  raise exception 'Unexpected receiving opening locks';
 end if;
 definition:=replace(definition,actor_lock,'');
 execute replace(definition,open_lock,open_lock||chr(10)||actor_lock||$patch$
 perform rm_private.require_scoped_receiving_draft_submission_v1(p_client_submission_id,'open',p_params,d.operator_id,p_operator_token);$patch$);

 definition:=pg_get_functiondef('rm_private.mobile_mutate_before_execution_v1(uuid,text,jsonb,text)'::regprocedure);
 if array_length(string_to_array(definition,open_lock),1) is distinct from 2 then
  raise exception 'Unexpected receiving completion lock';
 end if;
 execute replace(definition,open_lock,open_lock||$patch$
  if p_rpc_name='rm_submit_recebimento_v1' then
   perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||auth.uid()::text||':'||d.operator_id::text,45));
   perform rm_private.require_scoped_receiving_draft_submission_v1(p_client_submission_id,'complete',p_params,d.operator_id,p_operator_token);
  end if;$patch$);
end
$gateways$;

notify pgrst,'reload schema';
commit;
