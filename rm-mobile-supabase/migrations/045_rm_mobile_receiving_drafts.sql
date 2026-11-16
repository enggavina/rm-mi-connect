-- Receiving autosave is private, separate from effective projects and the mobile
-- mutation FIFO. Existing receiving envelopes/receipts remain byte-for-byte valid.
begin;

create table rm_private.receiving_drafts (
 id uuid primary key,
 auth_user_id uuid not null references auth.users(id) on delete restrict,
 operator_id uuid not null references public.rm_users(id) on delete restrict,
 payload jsonb not null check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=1048576),
 revision bigint not null default 1 check(revision>0),
 last_save_id uuid not null,
 state text not null default 'draft' check(state in('draft','finalized')),
 result jsonb,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 finalized_at timestamptz,
 check(coalesce(payload->>'id'=id::text,false)),
 check((state='draft' and result is null and finalized_at is null) or
       (state='finalized' and result is not null and finalized_at is not null))
);
-- One active cloud draft per device account/operator mirrors the existing local
-- receiving slot. Queued older drafts finalize before a new slot can be saved.
create unique index receiving_drafts_active_actor on rm_private.receiving_drafts(auth_user_id,operator_id) where state='draft';
create index receiving_drafts_actor_updated on rm_private.receiving_drafts(auth_user_id,operator_id,updated_at desc,id);
revoke all on rm_private.receiving_drafts from public,anon,authenticated,service_role;

create function rm_private.receiving_draft_dto_v1(p_draft rm_private.receiving_drafts) returns jsonb
language sql immutable security definer set search_path='' as $$
 select jsonb_build_object('id',p_draft.id,'revision',p_draft.revision,'state',p_draft.state,
  'payload',p_draft.payload,'result',p_draft.result);
$$;

create function public.rm_receiving_draft_v1(
 p_operator_token text,p_action text,p_draft_id uuid default null,p_payload jsonb default null,
 p_expected_revision bigint default null,p_save_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare d rm_private.operator_delegations%rowtype; item rm_private.receiving_drafts%rowtype;
begin
 select * into d from rm_private.operator_delegations where token_hash=extensions.digest(p_operator_token,'sha256')
  and auth_user_id=auth.uid() and not revoked and expires_at>clock_timestamp();
 if not found or rm_private.current_rm_user_id() is distinct from d.tablet_user_id or not exists(
  select 1 from public.rm_users where id=d.operator_id and status='ativo') then
  raise exception 'Identifique novamente o operador neste dispositivo.' using errcode='28000';
 end if;
 if p_action='read' then
  if p_draft_id is null then
   select * into item from rm_private.receiving_drafts where auth_user_id=auth.uid() and operator_id=d.operator_id and state='draft';
  else
   select * into item from rm_private.receiving_drafts where id=p_draft_id and auth_user_id=auth.uid() and operator_id=d.operator_id;
  end if;
  if not found then return null;end if;
  return rm_private.receiving_draft_dto_v1(item);
 end if;
 if p_action is distinct from 'save' or p_draft_id is null or p_save_id is null or p_expected_revision is null or p_expected_revision<0
  or p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>1048576
  or (p_payload->>'id') is distinct from p_draft_id::text or (p_payload->>'version') is distinct from '2'
  or coalesce(p_payload->>'submitted','false')<>'false' then
  raise exception 'Rascunho ou versão inválida.' using errcode='22023';
 end if;
 -- Actor lock also serializes two devices creating different protocols in the
 -- same active slot. It is never acquired by unrelated project operations.
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||auth.uid()::text||':'||d.operator_id::text,45));
 select * into item from rm_private.receiving_drafts where id=p_draft_id for update;
 if found then
  if item.auth_user_id<>auth.uid() or item.operator_id<>d.operator_id then
   raise exception 'Rascunho não disponível para este operador.' using errcode='42501';end if;
  if item.state<>'draft' then raise exception 'Este recebimento já foi concluído.' using errcode='PT409';end if;
  if item.last_save_id=p_save_id then
   if item.payload<>p_payload then raise exception 'Protocolo de salvamento já usado com outros dados.' using errcode='22023';end if;
   return rm_private.receiving_draft_dto_v1(item);
  end if;
  if item.revision<>p_expected_revision then
   raise exception 'O rascunho foi alterado em outro dispositivo. Os dados locais foram preservados.' using errcode='PT409';end if;
  update rm_private.receiving_drafts set payload=p_payload,revision=revision+1,last_save_id=p_save_id,updated_at=clock_timestamp()
   where id=p_draft_id returning * into item;
 else
  if p_expected_revision<>0 or exists(select 1 from rm_private.receiving_drafts where auth_user_id=auth.uid() and operator_id=d.operator_id and state='draft') then
   raise exception 'Já existe outro rascunho no banco. Os dados locais foram preservados.' using errcode='PT409';end if;
  insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,payload,last_save_id)
   values(p_draft_id,auth.uid(),d.operator_id,p_payload,p_save_id) returning * into item;
 end if;
 return rm_private.receiving_draft_dto_v1(item);
end $$;

create function rm_private.lock_receiving_draft_v1(p_operator uuid,p_submission uuid,p_params jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare item rm_private.receiving_drafts%rowtype; ident uuid; expected bigint; snapshot jsonb; pending uuid;
begin
 -- No new keys are required from any already-installed native client.
 if not(p_params?'p_receiving_draft_id') then return;end if;
 ident:=nullif(p_params->>'p_receiving_draft_id','')::uuid;
 expected:=nullif(p_params->>'p_receiving_draft_revision','')::bigint;
 pending:=nullif(p_params->>'p_receiving_draft_save_id','')::uuid;
 snapshot:=p_params->'p_receiving_draft_snapshot';
 if ident is null or ident<>p_submission or expected is null or expected<0 or snapshot is null
  or jsonb_typeof(snapshot)<>'object' or octet_length(snapshot::text)>1048576
  or (snapshot->>'id') is distinct from ident::text or (snapshot->>'version') is distinct from '2'
  or coalesce(snapshot->>'submitted','false')<>'false' then
  raise exception 'Rascunho ou protocolo de recebimento inválido.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('receiving-draft:'||auth.uid()::text||':'||p_operator::text,45));
 select * into item from rm_private.receiving_drafts where id=ident for update;
 if found then
  if item.auth_user_id<>auth.uid() or item.operator_id<>p_operator then
   raise exception 'Rascunho não disponível para este operador.' using errcode='42501';end if;
  if item.state<>'draft' then raise exception 'Este rascunho já foi finalizado.' using errcode='PT409';end if;
  -- A lost autosave response can leave exactly one durable request unacknowledged
  -- locally. Its UUID permits this one revision to be recognized safely.
  if item.revision<>expected and not(item.revision=expected+1 and pending is not null and item.last_save_id=pending) then
   raise exception 'O rascunho foi alterado em outro dispositivo. Confira a versão antes de concluir.' using errcode='PT409';end if;
  update rm_private.receiving_drafts set payload=snapshot,revision=revision+1,updated_at=clock_timestamp() where id=ident;
 else
  if expected<>0 or exists(select 1 from rm_private.receiving_drafts where auth_user_id=auth.uid() and operator_id=p_operator and state='draft') then
   raise exception 'Há outro rascunho aberto no banco. Confira antes de concluir.' using errcode='PT409';end if;
  insert into rm_private.receiving_drafts(id,auth_user_id,operator_id,payload,last_save_id)
   values(ident,auth.uid(),p_operator,snapshot,coalesce(pending,ident));
 end if;
end $$;

-- Patch the current gateway in place, preserving its identity, grants, every
-- legacy validation and receipt replay/redaction boundary. A failed receiving
-- validation rolls back the draft lock/change together with the whole gateway.
do $$ declare definition text; needle text; begin
 definition:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 needle:='  when ''rm_submit_recebimento_v1'' then';
 if strpos(definition,needle)=0 then raise exception 'Unexpected receiving gateway boundary';end if;
 definition:=replace(definition,needle,needle||E'\n    perform rm_private.lock_receiving_draft_v1(d.operator_id,p_client_submission_id,p_params);');
 needle:='  when ''rm_update_cell_status_v1'' then';
 if strpos(definition,needle)=0 then raise exception 'Unexpected receiving finalization boundary';end if;
 definition:=replace(definition,needle,$patch$
    if p_params?'p_receiving_draft_id' then
      update rm_private.receiving_drafts set state='finalized',result=v_result,finalized_at=clock_timestamp(),updated_at=clock_timestamp()
        where id=p_client_submission_id and auth_user_id=auth.uid() and operator_id=d.operator_id and state='draft';
      if not found then raise exception 'Rascunho não disponível para finalizar.' using errcode='PT409';end if;
    end if;
$patch$||needle);
 execute definition;
end $$;
revoke all on function rm_private.receiving_draft_dto_v1(rm_private.receiving_drafts),rm_private.lock_receiving_draft_v1(uuid,uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.rm_receiving_draft_v1(text,text,uuid,jsonb,bigint,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_receiving_draft_v1(text,text,uuid,jsonb,bigint,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
