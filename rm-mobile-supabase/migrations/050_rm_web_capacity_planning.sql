-- Individually declared workshop resources and explicit daily reservations.
-- Installation creates no resources or reservations.
begin;

create table rm_private.capacity_resources (
 id uuid primary key default gen_random_uuid(),
 name text not null check (length(btrim(name)) between 1 and 120),
 kind text not null check (kind in ('pessoa','maquina')),
 active boolean not null,
 weekly_minutes jsonb not null check (jsonb_typeof(weekly_minutes)='array' and jsonb_array_length(weekly_minutes)=7),
 exceptions jsonb not null check (jsonb_typeof(exceptions)='array' and jsonb_array_length(exceptions)<=366),
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid not null references public.rm_users(id) on delete restrict
);
create unique index rm_capacity_resource_name on rm_private.capacity_resources(lower(btrim(name)));
create table rm_private.capacity_bookings (
 id uuid primary key default gen_random_uuid(),
 resource_id uuid not null references rm_private.capacity_resources(id) on delete restrict,
 allocation_id uuid not null references public.rm_celulas_projeto(id) on delete restrict,
 day date not null check (day between '1900-01-01'::date and '2200-12-31'::date),
 minutes integer not null check (minutes between 1 and 1440),
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid not null references public.rm_users(id) on delete restrict,
 unique (resource_id,allocation_id,day)
);
create index rm_capacity_booking_allocation on rm_private.capacity_bookings(allocation_id,day);
create index rm_capacity_booking_window on rm_private.capacity_bookings(day,resource_id);
revoke all on rm_private.capacity_resources,rm_private.capacity_bookings from public,anon,authenticated,service_role;
alter table rm_private.capacity_resources enable row level security;
alter table rm_private.capacity_bookings enable row level security;
grant select on rm_private.capacity_resources,rm_private.capacity_bookings to authenticated;
create policy rm_capacity_resources_read on rm_private.capacity_resources for select to authenticated
 using (rm_private.web_gantt_read_allowed_v1());
create policy rm_capacity_bookings_read on rm_private.capacity_bookings for select to authenticated
 using (rm_private.web_gantt_read_allowed_v1() and exists (select 1 from public.rm_celulas_projeto a where a.id=allocation_id));

create function rm_private.capacity_available_minutes_v1(p_week jsonb,p_exceptions jsonb,p_day date) returns integer
language sql immutable security invoker set search_path='' as $$
 select coalesce((select (e->>'minutes')::int from jsonb_array_elements(p_exceptions) e where e->>'date'=to_char(p_day,'YYYY-MM-DD')),
  (p_week->>(extract(isodow from p_day)::int-1))::int);
$$;
revoke all on function rm_private.capacity_available_minutes_v1(jsonb,jsonb,date) from public,anon,authenticated,service_role;
grant execute on function rm_private.capacity_available_minutes_v1(jsonb,jsonb,date) to authenticated;

-- Include reservations outside the selected window/project in every version.
create function rm_private.capacity_resource_version_v1(p_resource uuid) returns text
language sql stable security invoker set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_object('resource',to_jsonb(r),
  'bookings',coalesce((select jsonb_agg(to_jsonb(b) order by b.id) from rm_private.capacity_bookings b where b.resource_id=r.id),'[]'))::text,'UTF8')),'hex')
 from rm_private.capacity_resources r where r.id=p_resource;
$$;
revoke all on function rm_private.capacity_resource_version_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function rm_private.capacity_resource_version_v1(uuid) to authenticated;

create function public.rm_web_capacity_snapshot_v1(p_filters jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare
 start_day date; window_days int; selected_project uuid; resource_count bigint; booking_count bigint; booked_day_count bigint; largest_day bigint;
 result jsonb; project_plan jsonb;
begin
 if not coalesce(rm_private.web_gantt_read_allowed_v1(),false) then raise exception 'Acesso ao planejamento nao autorizado.' using errcode='42501';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or not p_filters?&array['start','days','project_id']
  or exists(select 1 from jsonb_object_keys(p_filters) k where k not in('start','days','project_id'))
  or jsonb_typeof(p_filters->'start') is distinct from 'string' or (p_filters->>'start') !~ '^\d{4}-\d{2}-\d{2}$'
  or jsonb_typeof(p_filters->'days') is distinct from 'number' or (p_filters->>'days') not in('7','14','28')
  or jsonb_typeof(p_filters->'project_id') not in('null','string') then raise exception 'Janela de capacidade invalida.' using errcode='22023';end if;
 start_day:=(p_filters->>'start')::date;window_days:=(p_filters->>'days')::int;selected_project:=(p_filters->>'project_id')::uuid;
 if start_day<'1900-01-01'::date or start_day+window_days-1>'2200-12-31'::date then raise exception 'Janela fora do intervalo permitido.' using errcode='22023';end if;
 if selected_project is not null and not exists(select 1 from public.rm_projetos where id=selected_project) then raise exception 'Projeto nao disponivel.' using errcode='P0002';end if;
 select count(*) into resource_count from rm_private.capacity_resources;
 select count(*) into booking_count from rm_private.capacity_bookings where day>=start_day and day<start_day+window_days;
 result:=jsonb_build_object('as_of',statement_timestamp(),'start',to_char(start_day,'YYYY-MM-DD'),'days',window_days,
  'complete',false,'totals',jsonb_build_object('resources',resource_count,'bookings',booking_count),'resources','[]'::jsonb,'bookings','[]'::jsonb,'project_plan',null);
 if resource_count>200 or booking_count>10000 then return result;end if;
 select count(*),coalesce(max(minutes),0) into booked_day_count,largest_day
  from(select resource_id,day,sum(minutes) minutes from rm_private.capacity_bookings group by resource_id,day) demand;
 if booked_day_count>20000 or largest_day>2147483647 then return result;end if;
 if selected_project is not null then
  begin
   project_plan:=public.rm_web_gantt_snapshot_v1(jsonb_build_object('project_id',selected_project,'cell_id',null,'include_closed',true));
  exception when sqlstate 'PT413' then return result;
  end;
  if project_plan->>'complete' is distinct from 'true' then return result;end if;
 end if;
 result:=result||jsonb_build_object('complete',true,'project_plan',project_plan,
  'resources',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'kind',r.kind,'active',r.active,
   'weekly_minutes',r.weekly_minutes,'exceptions',r.exceptions,'updated_at',r.updated_at,'version',rm_private.capacity_resource_version_v1(r.id),
   'booked_days',coalesce((select jsonb_agg(jsonb_build_object('date',to_char(d.day,'YYYY-MM-DD'),'minutes',d.minutes) order by d.day)
    from(select b.day,sum(b.minutes) minutes from rm_private.capacity_bookings b where b.resource_id=r.id group by b.day)d),'[]')) order by lower(r.name),r.id)
   from rm_private.capacity_resources r),'[]'),
  'bookings',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'resource_id',b.resource_id,'allocation_id',b.allocation_id,
   'day',to_char(b.day,'YYYY-MM-DD'),'minutes',b.minutes,'updated_at',b.updated_at,'allocation_updated_at',a.updated_at,
   'project_id',a.projeto_id,'numero_projeto',coalesce(a.numero_projeto,p.numero),'cell_name',c.nome,'status',a.status,'retired',a.retirada,
   'project_closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false),
   'planned_start',a.data_inicio,'planned_end',a.data_limite,'project_working',case when s.id is null then true else
    coalesce((select (e->>'working')::boolean from jsonb_array_elements(s.calendar->'exceptions') e where e->>'date'=to_char(b.day,'YYYY-MM-DD')),
     exists(select 1 from jsonb_array_elements_text(s.calendar->'weekdays') w where w::int=extract(isodow from b.day)::int)) end)
   order by b.day,b.resource_id,a.projeto_id,b.allocation_id,b.id)
   from rm_private.capacity_bookings b join public.rm_celulas_projeto a on a.id=b.allocation_id
   join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id
   left join rm_private.gantt_project_settings s on s.projeto_id=p.id where b.day>=start_day and b.day<start_day+window_days),'[]'));
 if octet_length(result::text)>10485760 then
  return jsonb_build_object('as_of',statement_timestamp(),'start',to_char(start_day,'YYYY-MM-DD'),'days',window_days,'complete',false,
   'totals',jsonb_build_object('resources',resource_count,'bookings',booking_count),'resources','[]'::jsonb,'bookings','[]'::jsonb,'project_plan',null);
 end if;
 return result;
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
 raise exception 'Projeto ou data invalidos.' using errcode='22023';
end $$;
revoke all on function public.rm_web_capacity_snapshot_v1(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_capacity_snapshot_v1(jsonb) to authenticated;

-- A booking is exclusively owned by its allocation. Shared resources survive.
alter function rm_private.project_delete_scope_v1(uuid) rename to project_delete_scope_before_capacity_v1;
create function rm_private.project_delete_scope_v1(p_project uuid)
returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 select * from rm_private.project_delete_scope_before_capacity_v1(p_project)
 union all select 'rm_private','capacity_bookings',array(select b.id from rm_private.capacity_bookings b
  join public.rm_celulas_projeto a on a.id=b.allocation_id where a.projeto_id=p_project);
$$;
revoke all on function rm_private.project_delete_scope_v1(uuid),rm_private.project_delete_scope_before_capacity_v1(uuid) from public,anon,authenticated,service_role;
do $$declare definition text;needle text;replacement text;begin
 definition:=pg_get_functiondef('rm_private.web_mutate_before_route_config_v1(uuid,text,jsonb)'::regprocedure);
 needle:='foreach label in array array[''rm_private.gantt_project_settings''';
 if strpos(definition,needle)=0 then raise exception 'Unexpected project deletion leaf order';end if;
 definition:=replace(definition,needle,'foreach label in array array[''rm_private.capacity_bookings'',''rm_private.gantt_project_settings''');
 needle:='for s in select * from rm_private.project_delete_scope_v1(pid) order by schema_name,table_name loop';
 if strpos(definition,needle)=0 then raise exception 'Unexpected project deletion locks';end if;
 replacement:='perform 1 from public.rm_celulas_projeto where projeto_id=pid order by id for update;
 for s in select distinct r.id from rm_private.capacity_resources r join rm_private.capacity_bookings b on b.resource_id=r.id
  join public.rm_celulas_projeto a on a.id=b.allocation_id where a.projeto_id=pid order by r.id loop
  perform pg_advisory_xact_lock(hashtextextended(s.id::text,50));
  perform 1 from rm_private.capacity_resources where id=s.id for update;
 end loop;
 '||needle;
 execute replace(definition,needle,replacement);
 execute pg_get_functiondef('rm_private.project_delete_context_v1(uuid)'::regprocedure);
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_capacity_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare
 actor public.rm_users%rowtype;receipt rm_private.web_mutation_receipts%rowtype;resource rm_private.capacity_resources%rowtype;
 allocation public.rm_celulas_projeto%rowtype;project public.rm_projetos%rowtype;booking rm_private.capacity_bookings%rowtype;
 selected_resource_id uuid;expected_time timestamptz;entry jsonb;week jsonb;exceptions jsonb;calendar jsonb;desired_days jsonb;
 day_value date;minute_value int;changed_days int:=0;positive_changed_days date[]:='{}';resource_changed boolean:=false;before_record jsonb;result jsonb;
begin
 if p_operation is distinct from 'save_capacity_resource' and p_operation is distinct from 'save_capacity_bookings' then
  return rm_private.web_mutate_before_capacity_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operacao restrita a administracao/PCP.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticacao de dois fatores.' using errcode='42501';end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio invalido.' using errcode='22023';end if;
 if octet_length(p_payload::text)>2097152 then raise exception 'A capacidade excede o limite de envio.' using errcode='PT413';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation then raise exception 'Identificador de envio ja utilizado com outro conteudo.' using errcode='23505';end if;
  if receipt.result->'resource_deleted'='true'::jsonb then
   if receipt.payload->>'original_sha256' is distinct from encode(sha256(convert_to(p_payload::text,'UTF8')),'hex') then raise exception 'Identificador de envio ja utilizado com outro conteudo.' using errcode='23505';end if;
   raise exception 'Projeto excluido explicitamente. Este envio permanece disponivel para reconciliacao.' using errcode='PT410';
  elsif receipt.payload<>p_payload then raise exception 'Identificador de envio ja utilizado com outro conteudo.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if jsonb_typeof(p_payload->'reason') is distinct from 'string' or length(btrim(p_payload->>'reason')) not between 3 and 2000
  or jsonb_typeof(p_payload->'acknowledge_overload') is distinct from 'boolean' then raise exception 'Justificativa ou confirmacao de carga invalida.' using errcode='22023';end if;

 if p_operation='save_capacity_resource' then
  if not p_payload?&array['id','expected_version','name','kind','active','weekly_minutes','exceptions','acknowledge_overload','reason']
   or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('id','expected_version','name','kind','active','weekly_minutes','exceptions','acknowledge_overload','reason'))
   or jsonb_typeof(p_payload->'id') not in('null','string') or jsonb_typeof(p_payload->'expected_version') not in('null','string')
   or jsonb_typeof(p_payload->'name') is distinct from 'string' or length(btrim(p_payload->>'name')) not between 1 and 120 or p_payload->>'name' ~ '[[:cntrl:]]'
   or jsonb_typeof(p_payload->'kind') is distinct from 'string' or p_payload->>'kind' not in('pessoa','maquina')
   or jsonb_typeof(p_payload->'active') is distinct from 'boolean' then raise exception 'Recurso invalido.' using errcode='22023';end if;
  if (p_payload->>'id' is null)<>(p_payload->>'expected_version' is null)
   or (p_payload->>'expected_version' is not null and p_payload->>'expected_version' !~ '^[0-9a-f]{64}$') then raise exception 'Versao do recurso invalida.' using errcode='22023';end if;
  week:=p_payload->'weekly_minutes';exceptions:=p_payload->'exceptions';
  if jsonb_typeof(week) is distinct from 'array' or jsonb_array_length(week)<>7
   or jsonb_typeof(exceptions) is distinct from 'array' or jsonb_array_length(exceptions)>366 then raise exception 'Disponibilidade semanal ou excecoes invalidas.' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(week) value where jsonb_typeof(value)<>'number' or value::text !~ '^\d{1,4}$' or(value::text)::int>1440) then raise exception 'Informe minutos inteiros de 0 a 1440.' using errcode='22023';end if;
  for entry in select value from jsonb_array_elements(exceptions) loop
   if jsonb_typeof(entry)<>'object' or not entry?&array['date','minutes','label']
    or exists(select 1 from jsonb_object_keys(entry) k where k not in('date','minutes','label'))
    or jsonb_typeof(entry->'date') is distinct from 'string' or entry->>'date' !~ '^\d{4}-\d{2}-\d{2}$'
    or jsonb_typeof(entry->'minutes') is distinct from 'number' or entry->>'minutes' !~ '^\d{1,4}$' or(entry->>'minutes')::int>1440
    or jsonb_typeof(entry->'label') is distinct from 'string' or length(btrim(entry->>'label')) not between 1 and 120 or entry->>'label' ~ '[[:cntrl:]]' then raise exception 'Excecao de disponibilidade invalida.' using errcode='22023';end if;
   day_value:=(entry->>'date')::date;
   if day_value not between '1900-01-01'::date and '2200-12-31'::date then raise exception 'Data fora do intervalo permitido.' using errcode='22023';end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(exceptions) e group by e->>'date' having count(*)>1) then raise exception 'Data de excecao repetida.' using errcode='22023';end if;
  select coalesce(jsonb_agg(jsonb_build_object('date',e->>'date','minutes',(e->>'minutes')::int,'label',btrim(e->>'label')) order by e->>'date'),'[]') into exceptions from jsonb_array_elements(exceptions) e;
  selected_resource_id:=coalesce((p_payload->>'id')::uuid,gen_random_uuid());
  if p_payload->>'id' is null then
   perform pg_advisory_xact_lock(hashtextextended('capacity-resources-registry',50));
   if(select count(*) from rm_private.capacity_resources)>=200 then raise exception 'Limite de 200 recursos declarados atingido.' using errcode='PT413';end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(selected_resource_id::text,50));
  select * into resource from rm_private.capacity_resources where id=selected_resource_id for update;
  if p_payload->>'id' is not null then
   if resource.id is null then raise exception 'Recurso inexistente.' using errcode='P0002';end if;
   if rm_private.capacity_resource_version_v1(selected_resource_id) is distinct from p_payload->>'expected_version' then raise exception 'O recurso ou suas reservas mudaram. Recarregue antes de salvar.' using errcode='PT409';end if;
   if resource.kind<>p_payload->>'kind' then raise exception 'O tipo do recurso nao pode ser alterado.' using errcode='22023';end if;
  end if;
  resource_changed:=resource.id is null or row(resource.name,resource.kind,resource.active,resource.weekly_minutes,resource.exceptions)
   is distinct from row(btrim(p_payload->>'name'),p_payload->>'kind',(p_payload->>'active')::boolean,week,exceptions);
  if resource_changed and not(p_payload->>'acknowledge_overload')::boolean and exists(
   select 1 from rm_private.capacity_bookings b where b.resource_id=selected_resource_id group by b.day
    having sum(b.minutes)>case when(p_payload->>'active')::boolean then rm_private.capacity_available_minutes_v1(week,exceptions,b.day) else 0 end
  ) then raise exception 'A disponibilidade deixa reservas acima da capacidade. Confirme a sobrecarga para continuar.' using errcode='PT409';end if;
  before_record:=jsonb_build_object('resource',case when resource.id is null then null else to_jsonb(resource) end);
  if resource_changed then
   insert into rm_private.capacity_resources(id,name,kind,active,weekly_minutes,exceptions,updated_by)
    values(selected_resource_id,btrim(p_payload->>'name'),p_payload->>'kind',(p_payload->>'active')::boolean,week,exceptions,actor.id)
    on conflict(id) do update set name=excluded.name,active=excluded.active,weekly_minutes=excluded.weekly_minutes,
     exceptions=excluded.exceptions,updated_at=clock_timestamp(),updated_by=excluded.updated_by;
  end if;
  result:=jsonb_build_object('operation',p_operation,'id',selected_resource_id,'projeto_id',null,'updated_at',clock_timestamp(),
   'record',jsonb_build_object('resource_changed',resource_changed),'idempotent_replay',false);
 else
  if not p_payload?&array['resource_id','expected_resource_version','allocation_id','expected_allocation_updated_at','expected_project_version','days','acknowledge_overload','reason']
   or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('resource_id','expected_resource_version','allocation_id','expected_allocation_updated_at','expected_project_version','days','acknowledge_overload','reason'))
   or jsonb_typeof(p_payload->'resource_id') is distinct from 'string' or jsonb_typeof(p_payload->'allocation_id') is distinct from 'string'
   or jsonb_typeof(p_payload->'expected_resource_version') is distinct from 'string' or p_payload->>'expected_resource_version' !~ '^[0-9a-f]{64}$'
   or jsonb_typeof(p_payload->'expected_project_version') is distinct from 'string' or p_payload->>'expected_project_version' !~ '^[0-9a-f]{64}$'
   or jsonb_typeof(p_payload->'expected_allocation_updated_at') is distinct from 'string'
   or p_payload->>'expected_allocation_updated_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
   or jsonb_typeof(p_payload->'days') is distinct from 'array' or jsonb_array_length(p_payload->'days') not between 1 and 31 then raise exception 'Reserva ou versoes invalidas.' using errcode='22023';end if;
  selected_resource_id:=(p_payload->>'resource_id')::uuid;expected_time:=(p_payload->>'expected_allocation_updated_at')::timestamptz;
  if not isfinite(expected_time) then raise exception 'Versao de etapa invalida.' using errcode='22023';end if;
  desired_days:=p_payload->'days';
  for entry in select value from jsonb_array_elements(desired_days) loop
   if jsonb_typeof(entry)<>'object' or not entry?&array['date','minutes'] or exists(select 1 from jsonb_object_keys(entry) k where k not in('date','minutes'))
    or jsonb_typeof(entry->'date') is distinct from 'string' or entry->>'date' !~ '^\d{4}-\d{2}-\d{2}$'
    or jsonb_typeof(entry->'minutes') is distinct from 'number' or entry->>'minutes' !~ '^\d{1,4}$' or(entry->>'minutes')::int>1440 then raise exception 'Dia ou minutos de reserva invalidos.' using errcode='22023';end if;
   day_value:=(entry->>'date')::date;
   if day_value not between '1900-01-01'::date and '2200-12-31'::date then raise exception 'Data fora do intervalo permitido.' using errcode='22023';end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(desired_days) e group by e->>'date' having count(*)>1) then raise exception 'Dia de reserva repetido.' using errcode='22023';end if;
  select * into allocation from public.rm_celulas_projeto where id=(p_payload->>'allocation_id')::uuid;
  if allocation.id is null then raise exception 'Etapa inexistente.' using errcode='P0002';end if;
  perform pg_advisory_xact_lock(hashtextextended(allocation.projeto_id::text,11));
  select * into project from public.rm_projetos where id=allocation.projeto_id for update;
  if project.id is null then raise exception 'Projeto inexistente.' using errcode='P0002';end if;
  perform 1 from public.rm_celulas_projeto where projeto_id=project.id order by id for update;
  select * into allocation from public.rm_celulas_projeto where id=(p_payload->>'allocation_id')::uuid;
  if allocation.id is null then raise exception 'Etapa inexistente.' using errcode='P0002';end if;
  if allocation.updated_at is distinct from expected_time or rm_private.web_gantt_project_version_v1(project.id) is distinct from p_payload->>'expected_project_version' then raise exception 'O projeto ou a etapa mudou. Recarregue antes de reservar.' using errcode='PT409';end if;
  perform pg_advisory_xact_lock(hashtextextended(selected_resource_id::text,50));
  select * into resource from rm_private.capacity_resources where id=selected_resource_id for update;
  if resource.id is null then raise exception 'Recurso inexistente.' using errcode='P0002';end if;
  if rm_private.capacity_resource_version_v1(selected_resource_id) is distinct from p_payload->>'expected_resource_version' then raise exception 'O recurso ou suas reservas mudaram. Recarregue antes de salvar.' using errcode='PT409';end if;
  select s.calendar into calendar from rm_private.gantt_project_settings s where projeto_id=project.id;
  select jsonb_build_object('resource_id',selected_resource_id,'allocation_id',allocation.id,'bookings',coalesce(jsonb_agg(to_jsonb(b) order by b.day),'[]')) into before_record
   from rm_private.capacity_bookings b where b.resource_id=selected_resource_id and b.allocation_id=allocation.id and b.day in(select(e->>'date')::date from jsonb_array_elements(desired_days)e);
  for entry in select value from jsonb_array_elements(desired_days) order by value->>'date' loop
   day_value:=(entry->>'date')::date;minute_value:=(entry->>'minutes')::int;
   select * into booking from rm_private.capacity_bookings b where b.resource_id=selected_resource_id and b.allocation_id=allocation.id and b.day=day_value for update;
   if minute_value=coalesce(booking.minutes,0) then continue;end if;
   if minute_value>0 then
    if not resource.active or allocation.retirada or allocation.status in('finalizado','n_a') or project.data_real_de_entrega is not null or project.status_pcp in('cancelado','finalizando_para_faturar') then raise exception 'Recurso ou etapa disponivel apenas para liberar reservas.' using errcode='22023';end if;
    if allocation.data_inicio is null or allocation.data_limite is null
     or day_value<(allocation.data_inicio at time zone 'America/Sao_Paulo')::date or day_value>(allocation.data_limite at time zone 'America/Sao_Paulo')::date then raise exception 'A reserva deve estar no intervalo planejado da etapa.' using errcode='22023';end if;
    if calendar is not null and not rm_private.gantt_working_day_v1(day_value,calendar) then raise exception 'A reserva deve estar em um dia de trabalho do projeto.' using errcode='22023';end if;
    insert into rm_private.capacity_bookings(resource_id,allocation_id,day,minutes,updated_by) values(selected_resource_id,allocation.id,day_value,minute_value,actor.id)
     on conflict(resource_id,allocation_id,day) do update set minutes=excluded.minutes,updated_at=clock_timestamp(),updated_by=excluded.updated_by;
    positive_changed_days:=array_append(positive_changed_days,day_value);
   else
    delete from rm_private.capacity_bookings where id=booking.id;
   end if;
   changed_days:=changed_days+1;
  end loop;
  if not(p_payload->>'acknowledge_overload')::boolean and exists(
   select 1 from rm_private.capacity_bookings b where b.resource_id=selected_resource_id and b.day=any(positive_changed_days)
   group by b.day having sum(b.minutes)>case when resource.active then rm_private.capacity_available_minutes_v1(resource.weekly_minutes,resource.exceptions,b.day) else 0 end
  ) then raise exception 'As reservas excedem a disponibilidade diaria. Confirme a sobrecarga para continuar.' using errcode='PT409';end if;
  result:=jsonb_build_object('operation',p_operation,'id',selected_resource_id,'projeto_id',project.id,'updated_at',clock_timestamp(),
   'record',jsonb_build_object('changed_days',changed_days),'idempotent_replay',false);
 end if;
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation is distinct from 'save_capacity_resource' and p_operation is distinct from 'save_capacity_bookings' then raise;end if;
 raise exception 'Identificador, versao, minutos ou data invalidos.' using errcode='22023';
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_capacity_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

do $$declare definition text;constraint_definition text;needle text:='when ''save_gantt_plan'' then ''em.planning.manage''';begin
 select pg_get_constraintdef(oid) into constraint_definition from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check';
 if strpos(constraint_definition,'''save_gantt_settings''::text')=0 then raise exception 'Migration049 required';end if;
 constraint_definition:=replace(constraint_definition,'''save_gantt_settings''::text','''save_gantt_settings''::text, ''save_capacity_resource''::text, ''save_capacity_bookings''::text');
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check '||constraint_definition;
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected SSO capability map';end if;
 execute replace(definition,needle,needle||' when ''save_capacity_resource'' then ''em.planning.manage'' when ''save_capacity_bookings'' then ''em.planning.manage''');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;
