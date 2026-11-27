begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.execution_workshop_enforcement(
 channel text primary key check(channel in('web','mobile')),
 activated_at timestamptz not null
);
alter table rm_private.execution_workshop_enforcement enable row level security;
revoke all on rm_private.execution_workshop_enforcement from public,anon,authenticated,service_role;

create function rm_private.activate_execution_workshops_v1(p_channel text) returns void
language plpgsql set search_path='' as $$
begin
 if p_channel is null or p_channel not in('web','mobile') then raise exception 'Canal inválido.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('execution-workshop-cutover:'||p_channel,51));
 if exists(select 1 from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id
  left join rm_private.workshop_project_ownership p on p.id=a.projeto_id
  left join rm_private.workshop_cell_ownership c on c.cell_id=a.celula_id
  where p.workshop_id is null or p.workshop_id is distinct from c.workshop_id) then
  raise exception 'Há apontamentos com oficina de origem pendente ou divergente.' using errcode='PT409';
 end if;
 insert into rm_private.execution_workshop_enforcement values(p_channel,clock_timestamp()) on conflict(channel) do nothing;
 if p_channel='web' then
  revoke execute on function public.rm_web_execution_snapshot_v1(jsonb),rm_private.execution_session_version_v1(uuid),
   rm_private.execution_session_summary_v1(uuid),rm_private.execution_session_detail_v1(uuid) from authenticated;
  revoke select on rm_private.execution_sessions,rm_private.execution_events,rm_private.execution_reviews from authenticated;
 else
  revoke execute on function public.rm_mobile_execution_snapshot_v1(text,uuid) from authenticated;
 end if;
 perform pg_notify('pgrst','reload schema');
end
$$;
revoke all on function rm_private.activate_execution_workshops_v1(text) from public,anon,authenticated,service_role;

create function rm_private.workshop_execution_session_owned_v1(p_session uuid,p_office uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id
  where s.id=p_session and rm_private.workshop_project_owned_v1(a.projeto_id,p_office)
   and rm_private.workshop_cell_owned_v1(a.celula_id,p_office));
$$;
revoke all on function rm_private.workshop_execution_session_owned_v1(uuid,uuid) from public,anon,authenticated,service_role;

do $readers$
declare
 web text:=pg_get_functiondef('public.rm_web_execution_snapshot_v1(jsonb)'::regprocedure);
 mobile text:=pg_get_functiondef('public.rm_mobile_execution_snapshot_v1(text,uuid)'::regprocedure);
 web_filter constant text:=' where(pid is null or a.projeto_id=pid) and(cid is null or a.celula_id=cid)';
 web_select constant text:=' select coalesce(array_agg(a.id order by a.id),';
 mobile_auth_start constant text:=' select * into d from rm_private.operator_delegations';
 mobile_entry constant text:=' select * into a from public.rm_celulas_projeto where id=p_allocation_id;';
 access constant text:='rm_private.operator_can_access_cell(d.operator_id,other.celula_id);';
 first_auth integer;
 after_auth integer;
begin
 if array_length(string_to_array(web,web_filter),1) is distinct from 2
  or array_length(string_to_array(web,web_select),1) is distinct from 2
  or array_length(string_to_array(mobile,access),1) is distinct from 2
  or array_length(string_to_array(mobile,mobile_entry),1) is distinct from 2 then
  raise exception 'Unexpected execution snapshot contract';
 end if;
 web:=replace(web,'public.rm_web_execution_snapshot_v1(p_filters jsonb)',
  'rm_private.workshop_execution_snapshot_v1(p_filters jsonb,p_office uuid)');
 web:=replace(web,web_select,$guard$
 if p_office is null or (pid is not null and not rm_private.workshop_project_owned_v1(pid,p_office))
  or (cid is not null and not rm_private.workshop_cell_owned_v1(cid,p_office))
  or (sid is not null and not exists(select 1 from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id
   where s.id=sid and (pid is null or a.projeto_id=pid) and (cid is null or a.celula_id=cid)
    and rm_private.workshop_project_owned_v1(a.projeto_id,p_office) and rm_private.workshop_cell_owned_v1(a.celula_id,p_office))) then
  return null;
 end if;$guard$||chr(10)||web_select);
 execute replace(web,web_filter,web_filter||' and rm_private.workshop_project_owned_v1(a.projeto_id,p_office)
   and rm_private.workshop_cell_owned_v1(a.celula_id,p_office)');

 mobile:=replace(mobile,'public.rm_mobile_execution_snapshot_v1(p_operator_token text, p_allocation_id uuid)',
  'rm_private.workshop_mobile_execution_projection_v1(p_operator_id uuid,p_allocation_id uuid,p_office uuid)');
 if strpos(mobile,'rm_private.workshop_mobile_execution_projection_v1(')=0 then raise exception 'Unexpected native execution signature';end if;
 first_auth:=strpos(mobile,mobile_auth_start);
 after_auth:=strpos(mobile,mobile_entry);
 if first_auth=0 or after_auth<=first_auth then raise exception 'Unexpected native execution authentication block';end if;
 mobile:=replace(substr(mobile,1,first_auth-1)||substr(mobile,after_auth),'d rm_private.operator_delegations%rowtype;','');
 mobile:=replace(mobile,access,'rm_private.operator_can_access_cell(p_operator_id,other.celula_id)
   and rm_private.workshop_project_owned_v1(other.projeto_id,p_office) and rm_private.workshop_cell_owned_v1(other.celula_id,p_office);');
 mobile:=replace(mobile,'d.operator_id','p_operator_id');
 execute replace(mobile,' if a.id is null then',$guard$
 if a.id is null or not rm_private.workshop_project_owned_v1(a.projeto_id,p_office)
  or not rm_private.workshop_cell_owned_v1(a.celula_id,p_office) then$guard$);
end
$readers$;
revoke all on function rm_private.workshop_execution_snapshot_v1(jsonb,uuid),
 rm_private.workshop_mobile_execution_projection_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

create function public.rm_mobile_workshop_execution_v1(p_auth_user_id uuid,p_session_id uuid,p_operator_token text,
 p_workshop_context jsonb,p_allocation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare identity record; office uuid;
begin
 select * into identity from rm_private.online_operator_identity_v1(p_auth_user_id,p_session_id,p_operator_token);
 if not found then raise exception 'Identifique novamente o operador.' using errcode='28000';end if;
 office:=rm_private.online_workshop_context_v1(p_workshop_context,p_auth_user_id,identity.operator_subject);
 if office is null then raise exception 'O apontamento está indisponível nesta oficina.' using errcode='42501';end if;
 return jsonb_build_object('workshop_id',office,
  'snapshot',rm_private.workshop_mobile_execution_projection_v1(identity.operator_subject,p_allocation_id,office));
end
$$;
revoke all on function public.rm_mobile_workshop_execution_v1(uuid,uuid,text,jsonb,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_workshop_execution_v1(uuid,uuid,text,jsonb,uuid) to service_role;

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell','save_project_route','manage_project_route_cell','assign_form_reviewer',
  'save_capacity_resource','save_capacity_bookings','manage_cell_availability','save_cell_queue','review_execution_session'));
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot','cell_availability','cell_queue','planning_load','execution_snapshot'));

do $review$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 read_issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_core_v1(uuid,text,jsonb)'::regprocedure);
 mobile text:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 op_tail constant text:='''save_cell_queue'')';
 read_tail constant text:='''planning_load'')';
 dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 declarations constant text:=' a public.rm_celulas_projeto%rowtype;review_id';
 receipt_select constant text:=' select * into receipt from rm_private.web_mutation_receipts';
 replay constant text:='  return receipt.result||jsonb_build_object';
 save_receipt constant text:=' insert into rm_private.web_mutation_receipts(';
 locked_session constant text:=' select * into s from rm_private.execution_sessions where id=(p_payload->>''session_id'')::uuid for update;';
 mobile_receipt constant text:=' select * into receipt from rm_private.mobile_mutation_receipts';
 consume constant text:=$sql$
 if owner_office is not null then
  if not rm_private.workshop_execution_session_owned_v1((p_payload->>'session_id')::uuid,owner_office) then
   raise exception 'O apontamento está indisponível nesta oficina.' using errcode='42501';
  end if;
  delete from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id and expires_at>clock_timestamp();
  if not found then raise exception 'A confirmação da oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
 end if;
$sql$;
 anchor text;
begin
 if array_length(string_to_array(issuer,op_tail),1) is distinct from 2
  or array_length(string_to_array(read_issuer,read_tail),1) is distinct from 2
  or array_length(string_to_array(reader,dispatch),1) is distinct from 2
  or array_length(string_to_array(mobile,mobile_receipt),1) is distinct from 2 then raise exception 'Unexpected execution workshop contract';end if;
 foreach anchor in array array[declarations,receipt_select,replay,save_receipt,locked_session] loop
  if array_length(string_to_array(writer,anchor),1) is distinct from 2 then raise exception 'Unexpected execution review anchor: %',anchor;end if;
 end loop;
 execute replace(issuer,op_tail,'''save_cell_queue'',''review_execution_session'')');
 execute replace(read_issuer,read_tail,'''planning_load'',''execution_snapshot'')');
 execute replace(reader,dispatch,'  when ''execution_snapshot'' then rm_private.workshop_execution_snapshot_v1(p_args,permit.workshop_id)'||chr(10)||dispatch);
 writer:=replace(writer,declarations,' owner_office uuid; a public.rm_celulas_projeto%rowtype;review_id');
 writer:=replace(writer,receipt_select,$sql$
 perform pg_advisory_xact_lock_shared(hashtextextended('execution-workshop-cutover:web',51));
 owner_office:=rm_private.planning_workshop_permit_v1(p_client_submission_id,p_operation,p_payload,
  exists(select 1 from rm_private.execution_workshop_enforcement where channel='web'));
 if owner_office is not null and not rm_private.workshop_execution_session_owned_v1((p_payload->>'session_id')::uuid,owner_office) then
  raise exception 'O apontamento está indisponível nesta oficina.' using errcode='42501';end if;
$sql$||receipt_select);
 writer:=replace(writer,replay,consume||replay);
 writer:=replace(writer,locked_session,locked_session||$sql$
 if owner_office is not null and not rm_private.workshop_execution_session_owned_v1(s.id,owner_office) then
  raise exception 'O apontamento está indisponível nesta oficina.' using errcode='42501';end if;
$sql$);
 execute replace(writer,save_receipt,consume||save_receipt);

 -- The old mobile gateway remains compatible during rollout. After its own
 -- cutover, only a current signed 083 permit can reach the execution writer.
 execute replace(mobile,mobile_receipt,$sql$
 perform pg_advisory_xact_lock_shared(hashtextextended('execution-workshop-cutover:mobile',51));
 if exists(select 1 from rm_private.execution_workshop_enforcement where channel='mobile') and not exists(
  select 1 from rm_private.mobile_workshop_mutation_permits permit
  where permit.submission_id=p_client_submission_id and permit.rpc_name=p_rpc_name and permit.auth_user_id=auth.uid()
   and permit.auth_session_id::text=auth.jwt()->>'session_id' and permit.operator_id=d.operator_id
   and permit.operator_hash=extensions.digest(p_operator_token,'sha256') and permit.payload_hash=extensions.digest(p_params::text,'sha256')
   and permit.expires_at>clock_timestamp()
   and rm_private.mobile_mutation_workshop_project_v1(p_rpc_name,p_params,permit.workshop_id) is not null
 ) then raise exception 'Confirme a oficina antes de registrar o apontamento.' using errcode='42501';end if;
$sql$||mobile_receipt);
end
$review$;
notify pgrst,'reload schema';
commit;
