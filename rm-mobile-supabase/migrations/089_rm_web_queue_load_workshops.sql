begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

create table rm_private.queue_workshop_enforcement(
 singleton boolean primary key check(singleton),
 activated_at timestamptz not null
);
alter table rm_private.queue_workshop_enforcement enable row level security;
revoke all on rm_private.queue_workshop_enforcement from public,anon,authenticated,service_role;

create function rm_private.activate_queue_workshops_v1() returns void
language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('cell-queue-workshop-cutover',21));
 if exists(select 1 from rm_private.web_open_cell_allocations_v1 a
  left join rm_private.workshop_project_ownership p on p.id=a.projeto_id
  left join rm_private.workshop_cell_ownership c on c.cell_id=a.celula_id
  where p.workshop_id is null or p.workshop_id is distinct from c.workshop_id) then
  raise exception 'Há trabalhos abertos com origem pendente ou divergente.' using errcode='PT409';
 end if;
 insert into rm_private.queue_workshop_enforcement values(true,clock_timestamp()) on conflict(singleton) do nothing;
 revoke execute on function public.rm_web_cell_queue_snapshot_v1(uuid),public.rm_web_planning_load_v1() from authenticated;
 revoke select on rm_private.web_open_cell_allocations_v1 from authenticated;
 perform pg_notify('pgrst','reload schema');
end
$$;
revoke all on function rm_private.activate_queue_workshops_v1() from public,anon,authenticated,service_role;

-- Reuse the queue's ordering and version contract and the load aggregation.
-- Both filter projects and cells before producing rows, versions or totals.
do $projection$
declare
 queue text:=pg_get_functiondef('public.rm_web_cell_queue_snapshot_v1(uuid)'::regprocedure);
 load text:=pg_get_functiondef('public.rm_web_planning_load_v1()'::regprocedure);
begin
 if array_length(string_to_array(queue,'where celula_id=p_cell_id'),1) is distinct from 2
  or array_length(string_to_array(queue,'where c.id=p_cell_id'),1) is distinct from 2
  or array_length(string_to_array(load,'from rm_private.web_open_cell_allocations_v1 group by celula_id'),1) is distinct from 2
  or array_length(string_to_array(load,'from public.rm_celulas c left join counts a on a.celula_id=c.id;'),1) is distinct from 2 then
  raise exception 'Unexpected PCP projection definition';
 end if;
 queue:=replace(queue,'public.rm_web_cell_queue_snapshot_v1(p_cell_id uuid)',
  'rm_private.workshop_queue_projection_v1(p_cell_id uuid,p_office uuid)');
 queue:=replace(queue,'where celula_id=p_cell_id',
  'where celula_id=p_cell_id and rm_private.workshop_project_owned_v1(projeto_id,p_office)');
 execute replace(queue,'where c.id=p_cell_id','where c.id=p_cell_id and rm_private.workshop_cell_owned_v1(c.id,p_office)');
 load:=replace(load,'public.rm_web_planning_load_v1()','rm_private.workshop_load_projection_v1(p_office uuid)');
 load:=replace(load,'from rm_private.web_open_cell_allocations_v1 group by celula_id',
  'from rm_private.web_open_cell_allocations_v1 where rm_private.workshop_project_owned_v1(projeto_id,p_office)
    and rm_private.workshop_cell_owned_v1(celula_id,p_office) group by celula_id');
 execute replace(load,'from public.rm_celulas c left join counts a on a.celula_id=c.id;',
  'from public.rm_celulas c left join counts a on a.celula_id=c.id where rm_private.workshop_cell_owned_v1(c.id,p_office);');
end
$projection$;
revoke all on function rm_private.workshop_queue_projection_v1(uuid,uuid),rm_private.workshop_load_projection_v1(uuid)
 from public,anon,authenticated,service_role;

create function rm_private.workshop_pcp_read_v1(p_resource text,p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
begin
 if p_office is not null and p_resource='cell_queue' and jsonb_typeof(p_args)='object'
  and jsonb_typeof(p_args->'cell_id')='string' and p_args-'cell_id'='{}'::jsonb then
  return rm_private.workshop_queue_projection_v1((p_args->>'cell_id')::uuid,p_office);
 end if;
 if p_office is not null and p_resource='planning_load' and p_args='{}'::jsonb then
  return rm_private.workshop_load_projection_v1(p_office);
 end if;
 raise exception 'Consulta de fila ou carga inválida.' using errcode='22023';
exception when invalid_text_representation then
 raise exception 'Célula inválida.' using errcode='22023';
end
$$;
revoke all on function rm_private.workshop_pcp_read_v1(text,jsonb,uuid) from public,anon,authenticated,service_role;

create function rm_private.planning_workshop_permit_v1(p_submission uuid,p_operation text,p_payload jsonb,p_required boolean)
returns uuid language plpgsql set search_path='' as $$
declare permit rm_private.gantt_workshop_write_permits; binding rm_private.sso_identity_bindings; sess rm_private.sso_sessions;
begin
 select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_submission;
 if not found then
  if p_required then raise exception 'Confirme a oficina antes de salvar o planejamento.' using errcode='42501';end if;
  return null;
 end if;
 select b.* into binding from rm_private.sso_identity_bindings b join rm_private.sso_sessions s on s.binding_id=b.id
  where s.hash=permit.session_hash for share of b;
 select * into sess from rm_private.sso_sessions where hash=permit.session_hash for share;
 select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_submission for update;
 if not found or not coalesce(binding.enabled,false) or sess.binding_id is distinct from binding.id
  or permit.session_hash is distinct from sess.hash or permit.subject is distinct from binding.subject
  or binding.auth_user_id is distinct from auth.uid() or sess.local_session_id::text is distinct from auth.jwt()->>'session_id'
  or sess.expires_at<=clock_timestamp() or permit.expires_at<=clock_timestamp() or permit.operation is distinct from p_operation
  or permit.payload_hash is distinct from extensions.digest(p_payload::text,'sha256')
  or not exists(select 1 from auth.sessions s where s.id=sess.local_session_id and s.user_id=binding.auth_user_id) then
  raise exception 'Confirmação da oficina ausente, expirada ou divergente.' using errcode='42501';
 end if;
 return permit.workshop_id;
end
$$;
revoke all on function rm_private.planning_workshop_permit_v1(uuid,text,jsonb,boolean) from public,anon,authenticated,service_role;

create or replace function rm_private.capacity_write_workshop_v1(p_submission uuid,p_operation text,p_payload jsonb) returns uuid
language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock_shared(hashtextextended('capacity-workshop-cutover',50));
 return rm_private.planning_workshop_permit_v1(p_submission,p_operation,p_payload,
  exists(select 1 from rm_private.capacity_workshop_enforcement where singleton));
end
$$;

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell','save_project_route','manage_project_route_cell','assign_form_reviewer',
  'save_capacity_resource','save_capacity_bookings','manage_cell_availability','save_cell_queue'));
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot','cell_availability','cell_queue','planning_load'));

-- Keep the exact existing writer. Scope the initial receipt lookup and recheck
-- the cell, all submitted rows and open work once the queue's parent is locked.
do $queue$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_pcp_core_v1(uuid,text,jsonb)'::regprocedure);
 read_issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 last_operation constant text:='''manage_cell_availability'')';
 last_resource constant text:='''cell_availability'')';
 read_dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 declaration constant text:='  cell_id uuid; project_id uuid;';
 receipt_select constant text:='  select * into receipt from rm_private.web_mutation_receipts';
 replay constant text:='    return receipt.result||jsonb_build_object';
 project_list constant text:='from public.rm_celulas_projeto where celula_id=cell_id;';
 lock_allocations constant text:='  perform 1 from public.rm_celulas_projeto where celula_id=cell_id order by id for update;';
 load_before constant text:='  before_record:=public.rm_web_cell_queue_snapshot_v1(cell_id);';
 load_after constant text:='  snapshot:=public.rm_web_cell_queue_snapshot_v1(cell_id);';
 save_receipt constant text:='  insert into rm_private.web_mutation_receipts(';
 anchor text;
begin
 if array_length(string_to_array(issuer,last_operation),1) is distinct from 2
  or array_length(string_to_array(read_issuer,last_resource),1) is distinct from 2
  or array_length(string_to_array(reader,read_dispatch),1) is distinct from 2 then
  raise exception 'Unexpected scoped PCP contract';
 end if;
 foreach anchor in array array[declaration,receipt_select,replay,project_list,lock_allocations,load_before,load_after,save_receipt] loop
  if array_length(string_to_array(writer,anchor),1) is distinct from 2 then
   raise exception 'Unexpected scoped PCP writer anchor: %',anchor;
  end if;
 end loop;
 execute replace(issuer,last_operation,'''manage_cell_availability'',''save_cell_queue'')');
 execute replace(read_issuer,last_resource,'''cell_availability'',''cell_queue'',''planning_load'')');
 execute replace(reader,read_dispatch,'  when ''cell_queue'' then rm_private.workshop_pcp_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||
  '  when ''planning_load'' then rm_private.workshop_pcp_read_v1(p_resource,p_args,permit.workshop_id)'||chr(10)||read_dispatch);
 writer:=replace(writer,declaration,'  owner_office uuid; cell_id uuid; project_id uuid;');
 writer:=replace(writer,receipt_select,$guard$
  perform pg_advisory_xact_lock_shared(hashtextextended('cell-queue-workshop-cutover',21));
  owner_office:=rm_private.planning_workshop_permit_v1(p_client_submission_id,p_operation,p_payload,
   exists(select 1 from rm_private.queue_workshop_enforcement where singleton));
  if owner_office is not null and not rm_private.workshop_cell_owned_v1((p_payload->>'celula_id')::uuid,owner_office) then
   raise exception 'Fila indisponível nesta oficina.' using errcode='42501';
  end if;$guard$||chr(10)||receipt_select);
 writer:=replace(writer,replay,$guard$
    if owner_office is not null then
     if exists(select 1 from jsonb_array_elements(p_payload->'items') queued where not exists(
      select 1 from public.rm_celulas_projeto a where a.id=(queued->>'id')::uuid and a.celula_id=(p_payload->>'celula_id')::uuid
       and rm_private.workshop_project_owned_v1(a.projeto_id,owner_office))) then
      raise exception 'Protocolo indisponível nesta oficina.' using errcode='42501';
     end if;
     delete from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id and expires_at>clock_timestamp();
     if not found then raise exception 'A confirmação da oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
    end if;$guard$||chr(10)||replay);
 writer:=replace(writer,project_list,'from public.rm_celulas_projeto a where a.celula_id=cell_id
     and (owner_office is null or rm_private.workshop_project_owned_v1(a.projeto_id,owner_office));');
 writer:=replace(writer,lock_allocations,'  perform 1 from public.rm_celulas_projeto a where a.celula_id=cell_id
    and (owner_office is null or rm_private.workshop_project_owned_v1(a.projeto_id,owner_office)) order by a.id for update;');
 writer:=replace(writer,load_before,$guard$
  if owner_office is not null then
   if exists(select 1 from rm_private.web_open_cell_allocations_v1 a where a.celula_id=cell_id
    and not rm_private.workshop_project_owned_v1(a.projeto_id,owner_office)) then
    raise exception 'Há trabalhos com origem pendente. Atualize a fila após a conferência.' using errcode='PT409';
   end if;
   if exists(select 1 from unnest(submitted_ids) submitted(id) where not exists(select 1 from public.rm_celulas_projeto a
    where a.id=submitted.id and a.celula_id=cell_id and rm_private.workshop_project_owned_v1(a.projeto_id,owner_office))) then
    raise exception 'Há alocações indisponíveis nesta oficina ou nesta célula.' using errcode='42501';
   end if;
   before_record:=rm_private.workshop_queue_projection_v1(cell_id,owner_office);
  else
   before_record:=public.rm_web_cell_queue_snapshot_v1(cell_id);
  end if;$guard$);
 writer:=replace(writer,load_after,'  snapshot:=case when owner_office is null then public.rm_web_cell_queue_snapshot_v1(cell_id)
    else rm_private.workshop_queue_projection_v1(cell_id,owner_office) end;');
 execute replace(writer,save_receipt,$guard$
  if owner_office is not null then
   delete from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id and expires_at>clock_timestamp();
   if not found then raise exception 'A confirmação da oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
  end if;$guard$||chr(10)||save_receipt);
end
$queue$;
notify pgrst,'reload schema';
commit;
