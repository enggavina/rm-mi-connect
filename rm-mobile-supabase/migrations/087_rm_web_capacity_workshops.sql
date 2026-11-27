begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

alter table rm_private.capacity_resources add column workshop_id uuid references rm_private.workshop_references(id);
drop index rm_private.rm_capacity_resource_name;
create unique index rm_capacity_resource_legacy_name on rm_private.capacity_resources(lower(btrim(name))) where workshop_id is null;
create unique index rm_capacity_resource_workshop_name on rm_private.capacity_resources(workshop_id,lower(btrim(name))) where workshop_id is not null;

create table rm_private.capacity_workshop_enforcement (
 singleton boolean primary key check(singleton),
 activated_at timestamptz not null
);
alter table rm_private.capacity_workshop_enforcement enable row level security;
revoke all on rm_private.capacity_workshop_enforcement from public,anon,authenticated,service_role;

create function rm_private.activate_capacity_workshop_writes_v1() returns void
language plpgsql set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('capacity-workshop-cutover',50));
 if exists(select 1 from rm_private.capacity_resources where workshop_id is null) then
  raise exception 'Há recursos com origem pendente de conferência.' using errcode='PT409';
 end if;
 insert into rm_private.capacity_workshop_enforcement values(true,clock_timestamp()) on conflict(singleton) do nothing;
end
$$;
revoke all on function rm_private.activate_capacity_workshop_writes_v1() from public,anon,authenticated,service_role;

-- The old reader can serve pre-existing unclassified data for reconciliation.
-- It can never read a scoped resource or its bookings, even via a direct RPC.
alter policy rm_capacity_resources_read on rm_private.capacity_resources using (
 workshop_id is null and rm_private.web_gantt_read_allowed_v1());
alter policy rm_capacity_bookings_read on rm_private.capacity_bookings using (
 rm_private.web_gantt_read_allowed_v1() and exists(select 1 from public.rm_celulas_projeto a where a.id=allocation_id)
 and exists(select 1 from rm_private.capacity_resources r where r.id=resource_id and r.workshop_id is null));

create function rm_private.capacity_allocation_owned_v1(p_allocation uuid,p_office uuid) returns boolean
language sql stable set search_path='' as $$
 select exists(select 1 from public.rm_celulas_projeto a where a.id=p_allocation
  and rm_private.workshop_project_owned_v1(a.projeto_id,p_office) and rm_private.workshop_cell_owned_v1(a.celula_id,p_office));
$$;
revoke all on function rm_private.capacity_allocation_owned_v1(uuid,uuid) from public,anon,authenticated,service_role;

create function rm_private.capacity_booking_workshop_guard_v1() returns trigger
language plpgsql set search_path='' as $$
declare office uuid;
begin
 select r.workshop_id into office from rm_private.capacity_resources r where r.id=new.resource_id;
 if office is not null and not rm_private.capacity_allocation_owned_v1(new.allocation_id,office) then
  raise exception 'A etapa e o recurso devem pertencer à mesma oficina.' using errcode='42501';
 end if;
 return new;
end
$$;
revoke all on function rm_private.capacity_booking_workshop_guard_v1() from public,anon,authenticated,service_role;
create trigger rm_capacity_booking_workshop_guard before insert or update of resource_id,allocation_id on rm_private.capacity_bookings
 for each row execute function rm_private.capacity_booking_workshop_guard_v1();

create function rm_private.workshop_capacity_snapshot_v1(p_args jsonb,p_office uuid) returns jsonb
language plpgsql stable set search_path='' as $$
declare start_day date; days int; project uuid; snapshot jsonb; project_plan jsonb; empty_snapshot jsonb; managed boolean;
begin
 if p_office is null or jsonb_typeof(p_args) is distinct from 'object' or not p_args?&array['start','days','project_id','can_manage']
  or exists(select 1 from jsonb_object_keys(p_args) k where k not in('start','days','project_id','can_manage'))
  or jsonb_typeof(p_args->'start') is distinct from 'string' or (p_args->>'start')!~'^\d{4}-\d{2}-\d{2}$'
  or jsonb_typeof(p_args->'days') is distinct from 'number' or (p_args->>'days') not in('7','14','28')
  or jsonb_typeof(p_args->'project_id') not in('null','string') or jsonb_typeof(p_args->'can_manage') is distinct from 'boolean' then
  raise exception 'Datas ou filtros de capacidade inválidos.' using errcode='22023';
 end if;
 start_day:=(p_args->>'start')::date; days:=(p_args->>'days')::int; project:=(p_args->>'project_id')::uuid;
 managed:=(p_args->>'can_manage')::boolean;
 if start_day<'1900-01-01'::date or start_day+days-1>'2200-12-31'::date then
  raise exception 'Janela fora do intervalo permitido.' using errcode='22023';
 end if;
 if project is not null and not rm_private.workshop_project_owned_v1(project,p_office) then return null;end if;

 with resources as materialized (select * from rm_private.capacity_resources r where r.workshop_id=p_office),
 bookings as materialized (
  select b.* from rm_private.capacity_bookings b join resources r on r.id=b.resource_id
   where rm_private.capacity_allocation_owned_v1(b.allocation_id,p_office)
 ), demand as materialized (select resource_id,day,sum(minutes) minutes from bookings group by resource_id,day),
 window_bookings as materialized (select * from bookings where day>=start_day and day<start_day+days),
 counts as (select (select count(*) from resources) resources,(select count(*) from window_bookings) bookings,
  (select count(*) from demand) booked_days,(select coalesce(max(minutes),0) from demand) largest_day)
 select jsonb_build_object('as_of',statement_timestamp(),'start',to_char(start_day,'YYYY-MM-DD'),'days',days,
  'complete',false,'totals',jsonb_build_object('resources',stat.resources,'bookings',stat.bookings),
  'resources','[]'::jsonb,'bookings','[]'::jsonb,'project_plan',null),
  case when resources<=200 and bookings<=10000 and booked_days<=20000 and largest_day<=2147483647 then
   jsonb_build_object('resources',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'kind',r.kind,'active',r.active,
    'weekly_minutes',r.weekly_minutes,'exceptions',r.exceptions,'updated_at',r.updated_at,'version',rm_private.capacity_resource_version_v1(r.id),
    'booked_days',coalesce((select jsonb_agg(jsonb_build_object('date',to_char(d.day,'YYYY-MM-DD'),'minutes',d.minutes) order by d.day)
     from demand d where d.resource_id=r.id),'[]')) order by lower(r.name),r.id) from resources r),'[]'),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'resource_id',b.resource_id,'allocation_id',b.allocation_id,
     'day',to_char(b.day,'YYYY-MM-DD'),'minutes',b.minutes,'updated_at',b.updated_at,'allocation_updated_at',a.updated_at,
     'project_id',p.id,'numero_projeto',coalesce(a.numero_projeto,p.numero),'cell_name',c.nome,'status',a.status,'retired',a.retirada,
     'project_closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false),
     'planned_start',a.data_inicio,'planned_end',a.data_limite,'project_working',s.id is null or rm_private.gantt_working_day_v1(b.day,s.calendar))
     order by b.day,b.resource_id,p.id,b.allocation_id,b.id) from window_bookings b join public.rm_celulas_projeto a on a.id=b.allocation_id
      join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id
      left join rm_private.gantt_project_settings s on s.projeto_id=p.id),'[]')) end
 into empty_snapshot,snapshot from counts stat;
 if snapshot is null then return empty_snapshot;end if;
 if project is not null then
  begin
   project_plan:=rm_private.workshop_gantt_snapshot_v1(jsonb_build_object('project_id',project,'cell_id',null,
    'include_closed',true,'project_details',true,'can_manage',false),p_office);
  exception when sqlstate 'PT413' then return empty_snapshot;
  end;
  if project_plan->>'complete' is distinct from 'true' then return empty_snapshot;end if;
  if managed and project_plan->'projects'->0->>'closed'='false' then
   project_plan:=jsonb_set(project_plan,'{items}',(select coalesce(jsonb_agg(a.value||jsonb_build_object('can_edit',
    (a.value->>'status') is distinct from 'finalizado' and (a.value->>'status') is distinct from 'n_a') order by a.ordinality),'[]')
    from jsonb_array_elements(project_plan->'items') with ordinality a));
  end if;
 end if;
 snapshot:=empty_snapshot||snapshot||jsonb_build_object('complete',true,'project_plan',project_plan);
 if octet_length(snapshot::text)>10485760 then return empty_snapshot;end if;
 return snapshot;
end
$$;
revoke all on function rm_private.workshop_capacity_snapshot_v1(jsonb,uuid) from public,anon,authenticated,service_role;

create function rm_private.capacity_write_workshop_v1(p_submission uuid,p_operation text,p_payload jsonb) returns uuid
language plpgsql set search_path='' as $$
declare permit rm_private.gantt_workshop_write_permits; binding rm_private.sso_identity_bindings; sess rm_private.sso_sessions;
begin
 perform pg_advisory_xact_lock_shared(hashtextextended('capacity-workshop-cutover',50));
 select * into permit from rm_private.gantt_workshop_write_permits where submission_id=p_submission;
 if not found then
  if exists(select 1 from rm_private.capacity_workshop_enforcement where singleton) then
   raise exception 'Confirme a oficina antes de salvar a capacidade.' using errcode='42501';
  end if;
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
revoke all on function rm_private.capacity_write_workshop_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

alter table rm_private.gantt_workshop_write_permits drop constraint gantt_workshop_write_permits_operation_check;
alter table rm_private.gantt_workshop_write_permits add constraint gantt_workshop_write_permits_operation_check
 check(operation in('save_gantt_plan','save_gantt_settings','plan_cell','save_project_route','manage_project_route_cell','assign_form_reviewer',
  'save_capacity_resource','save_capacity_bookings'));
alter table rm_private.workshop_read_permits drop constraint workshop_read_permits_resource_check;
alter table rm_private.workshop_read_permits add constraint workshop_read_permits_resource_check check (
 resource in('catalog_list','catalog_entry','template_list','template_draft','template_form','template_choices',
  'project_list','project_entry','planning_list','gantt_snapshot','gantt_projects','gantt_cells','operation_validation','receiving_list',
  'project_qr','document_link','form_record_project','form_record_list','workshop_twin','planning_export','media_reference','overview',
  'approval_list','approval_entry','approval_choices','approval_allocation','capacity_snapshot'));

-- Keep the installed capacity writer's lock order, versioning, stock limits,
-- history and idempotency. The office comes exclusively from its SSO permit.
do $capacity$
declare
 issuer text:=pg_get_functiondef('public.rm_sso_gantt_workshop_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 writer text:=pg_get_functiondef('rm_private.web_mutate_before_execution_v1(uuid,text,jsonb)'::regprocedure);
 read_issuer text:=pg_get_functiondef('public.rm_sso_workshop_read_permit_v1(text,uuid,text,jsonb,jsonb)'::regprocedure);
 reader text:=pg_get_functiondef('public.rm_web_workshop_read_v1(uuid,text,jsonb)'::regprocedure);
 last_operation constant text:='''assign_form_reviewer'')';
 last_resource constant text:='''approval_allocation'')';
 read_dispatch constant text:='  else rm_private.workshop_read_data_v1(p_resource,p_args,permit.workshop_id)';
 marker text;
begin
 if array_length(string_to_array(issuer,last_operation),1) is distinct from 2
  or array_length(string_to_array(read_issuer,last_resource),1) is distinct from 2
  or array_length(string_to_array(reader,read_dispatch),1) is distinct from 2 then raise exception 'Unexpected scoped capacity contract';end if;
 execute replace(issuer,last_operation,'''assign_form_reviewer'',''save_capacity_resource'',''save_capacity_bookings'')');
 execute replace(read_issuer,last_resource,'''approval_allocation'',''capacity_snapshot'')');
 execute replace(reader,read_dispatch,'  when ''capacity_snapshot'' then rm_private.workshop_capacity_snapshot_v1(p_args,permit.workshop_id)'||chr(10)||read_dispatch);
 foreach marker in array array[' selected_resource_id uuid;', ' select * into receipt from rm_private.web_mutation_receipts',
  '  return receipt.result||jsonb_build_object', '  insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by)',
  'values(selected_resource_id,btrim(p_payload->>''name''),p_payload->>''kind'',(p_payload->>''active'')::boolean,week,exceptions,actor.id)',
  'if(select count(*) from rm_private.capacity_resources)>=200', '''capacity-resources-registry'',50',
  '  if allocation.updated_at is distinct from expected_time', ' insert into rm_private.web_mutation_receipts('] loop
  if array_length(string_to_array(writer,marker),1) is distinct from 2 then raise exception 'Unexpected capacity writer anchor: %',marker;end if;
 end loop;
 marker:='select * into resource from rm_private.capacity_resources where id=selected_resource_id for update;';
 if array_length(string_to_array(writer,marker),1) is distinct from 3 then raise exception 'Unexpected capacity resource locking';end if;
 writer:=replace(writer,marker,marker||$guard$
  if resource.id is not null and resource.workshop_id is distinct from owner_office then
   raise exception 'Recurso indisponível nesta oficina.' using errcode='42501';end if;$guard$);
 writer:=replace(writer,' selected_resource_id uuid;',' owner_office uuid; selected_resource_id uuid;');
 writer:=replace(writer,' select * into receipt from rm_private.web_mutation_receipts',
  ' owner_office:=rm_private.capacity_write_workshop_v1(p_client_submission_id,p_operation,p_payload);'||chr(10)||
  ' select * into receipt from rm_private.web_mutation_receipts');
 writer:=replace(writer,'  return receipt.result||jsonb_build_object',$guard$
  if not exists(select 1 from rm_private.capacity_resources r where r.id=(receipt.result->>'id')::uuid and r.workshop_id is not distinct from owner_office)
   or (owner_office is not null and p_operation='save_capacity_bookings' and not rm_private.capacity_allocation_owned_v1((p_payload->>'allocation_id')::uuid,owner_office)) then
   raise exception 'Protocolo indisponível nesta oficina.' using errcode='42501';end if;
  delete from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id and owner_office is not null;
  return receipt.result||jsonb_build_object$guard$);
 writer:=replace(writer,'if(select count(*) from rm_private.capacity_resources)>=200',
  'if(select count(*) from rm_private.capacity_resources r where r.workshop_id is not distinct from owner_office)>=200');
 writer:=replace(writer,'''capacity-resources-registry'',50','''capacity-resources-registry''||coalesce('':''||owner_office::text,''''),50');
 writer:=replace(writer,'  insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by)',
  '  insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by,workshop_id)');
 writer:=replace(writer,'values(selected_resource_id,btrim(p_payload->>''name''),p_payload->>''kind'',(p_payload->>''active'')::boolean,week,exceptions,actor.id)',
  'values(selected_resource_id,btrim(p_payload->>''name''),p_payload->>''kind'',(p_payload->>''active'')::boolean,week,exceptions,actor.id,owner_office)');
 writer:=replace(writer,'  if allocation.updated_at is distinct from expected_time',$guard$
  if owner_office is not null and not rm_private.capacity_allocation_owned_v1(allocation.id,owner_office) then
   raise exception 'Etapa indisponível nesta oficina.' using errcode='42501';end if;
  if allocation.updated_at is distinct from expected_time$guard$);
 execute replace(writer,' insert into rm_private.web_mutation_receipts(',$guard$
 if owner_office is not null then
  delete from rm_private.gantt_workshop_write_permits where submission_id=p_client_submission_id and expires_at>clock_timestamp();
  if not found then raise exception 'A confirmação da oficina expirou. Reenvie o mesmo protocolo.' using errcode='42501';end if;
 end if;
 insert into rm_private.web_mutation_receipts($guard$);
end
$capacity$;
notify pgrst,'reload schema';
commit;
