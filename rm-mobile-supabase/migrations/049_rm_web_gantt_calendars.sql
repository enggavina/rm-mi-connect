-- Optional project calendars and milestones; existing plans keep elapsed days.
-- Installation creates no settings, dates, baseline, receipt or operational data.
begin;

create table rm_private.gantt_project_settings(
 id uuid primary key default gen_random_uuid(),
 projeto_id uuid not null unique references public.rm_projetos(id) on delete restrict,
 calendar jsonb not null check(jsonb_typeof(calendar)='object'),
 milestones jsonb not null default '[]' check(jsonb_typeof(milestones)='array' and jsonb_array_length(milestones)<=100),
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid not null references public.rm_users(id) on delete restrict
);
revoke all on rm_private.gantt_project_settings from public,anon,authenticated,service_role;
alter table rm_private.gantt_project_settings enable row level security;
grant select on rm_private.gantt_project_settings to authenticated;
create policy rm_gantt_settings_read on rm_private.gantt_project_settings for select to authenticated
 using(rm_private.web_gantt_read_allowed_v1() and exists(select 1 from public.rm_projetos p where p.id=projeto_id));

create function rm_private.gantt_working_day_v1(p_day date,p_calendar jsonb) returns boolean
language sql immutable security invoker set search_path='' as $$
 select coalesce((select (e->>'working')::boolean from jsonb_array_elements(p_calendar->'exceptions') e where e->>'date'=to_char(p_day,'YYYY-MM-DD')),
  exists(select 1 from jsonb_array_elements_text(p_calendar->'weekdays') d where d::int=extract(isodow from p_day)::int));
$$;
create function rm_private.gantt_successor_day_v1(p_end date,p_lag int,p_calendar jsonb) returns date
language plpgsql immutable security invoker set search_path='' as $$
declare d date:=p_end+1;working int:=0;iterations int:=0;
begin
 if p_end is null or p_lag is null or p_lag not between 0 and 3650 then raise exception 'Dependencia de calendario invalida.' using errcode='22023';end if;
 loop
  if rm_private.gantt_working_day_v1(d,p_calendar) then
   if working=p_lag then return d;end if;
   working:=working+1;
  end if;
  d:=d+1;iterations:=iterations+1;
  if iterations>30000 then raise exception 'Calendario sem dias suficientes para a dependencia.' using errcode='22023';end if;
 end loop;
end $$;
revoke all on function rm_private.gantt_working_day_v1(date,jsonb),rm_private.gantt_successor_day_v1(date,int,jsonb) from public,anon,authenticated,service_role;

-- Absence of settings preserves the exact 047 version, including old drafts.
alter function rm_private.web_gantt_project_version_v1(uuid) rename to web_gantt_project_version_before_calendar_v1;
create function rm_private.web_gantt_project_version_v1(p_project_id uuid) returns text
language sql stable security invoker set search_path='' as $$
 select case when s.id is null then rm_private.web_gantt_project_version_before_calendar_v1(p_project_id)
  else encode(sha256(convert_to(jsonb_build_object('previous',rm_private.web_gantt_project_version_before_calendar_v1(p_project_id),
   'settings',jsonb_build_object('id',s.id,'updated_at',s.updated_at,'calendar',s.calendar,'milestones',s.milestones))::text,'UTF8')),'hex') end
 from public.rm_projetos p left join rm_private.gantt_project_settings s on s.projeto_id=p.id where p.id=p_project_id;
$$;
revoke all on function rm_private.web_gantt_project_version_v1(uuid),rm_private.web_gantt_project_version_before_calendar_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function rm_private.web_gantt_project_version_v1(uuid),rm_private.web_gantt_project_version_before_calendar_v1(uuid) to authenticated;

alter function public.rm_web_gantt_snapshot_v1(jsonb) set schema rm_private;
alter function rm_private.rm_web_gantt_snapshot_v1(jsonb) rename to web_gantt_snapshot_before_calendar_v1;
create function public.rm_web_gantt_snapshot_v1(p_filters jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;settings jsonb;project_ids uuid[];settings_size bigint;
begin
 result:=rm_private.web_gantt_snapshot_before_calendar_v1(p_filters);
 select coalesce(array_agg((p->>'id')::uuid),'{}') into project_ids from jsonb_array_elements(result->'projects') p;
 select coalesce(sum(octet_length(s.calendar::text)+octet_length(s.milestones::text)+250),0) into settings_size
  from rm_private.gantt_project_settings s where s.projeto_id=any(project_ids);
 if octet_length(result::text)+settings_size>10485760 then raise exception 'O cronograma excede o limite de leitura completa.' using errcode='PT413';end if;
 select coalesce(jsonb_agg(jsonb_build_object('projeto_id',s.projeto_id,'calendar',s.calendar,'milestones',s.milestones,'updated_at',s.updated_at) order by s.projeto_id),'[]') into settings
  from rm_private.gantt_project_settings s where s.projeto_id=any(project_ids);
 result:=result||jsonb_build_object('settings',settings);
 if octet_length(result::text)>10485760 then raise exception 'O cronograma excede o limite de leitura completa.' using errcode='PT413';end if;
 return result;
end $$;
revoke all on function public.rm_web_gantt_snapshot_v1(jsonb),rm_private.web_gantt_snapshot_before_calendar_v1(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_gantt_snapshot_v1(jsonb),rm_private.web_gantt_snapshot_before_calendar_v1(jsonb) to authenticated;

-- The confirmed deletion closure and its version include the new private row.
alter function rm_private.project_delete_scope_v1(uuid) rename to project_delete_scope_before_gantt_settings_v1;
create function rm_private.project_delete_scope_v1(p_project uuid)
returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 select * from rm_private.project_delete_scope_before_gantt_settings_v1(p_project)
 union all select 'rm_private','gantt_project_settings',array(select id from rm_private.gantt_project_settings where projeto_id=p_project);
$$;
revoke all on function rm_private.project_delete_scope_v1(uuid),rm_private.project_delete_scope_before_gantt_settings_v1(uuid) from public,anon,authenticated,service_role;
do $$declare d text;needle text:='foreach label in array array[''rm_private.gantt_baselines''';begin
 d:=pg_get_functiondef('rm_private.web_mutate_before_route_config_v1(uuid,text,jsonb)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected project deletion leaf order';end if;
 execute replace(d,needle,'foreach label in array array[''rm_private.gantt_project_settings'',''rm_private.gantt_baselines''');
 execute pg_get_functiondef('rm_private.project_delete_context_v1(uuid)'::regprocedure);
end $$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_gantt_settings_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype;receipt rm_private.web_mutation_receipts%rowtype;p public.rm_projetos%rowtype;stored rm_private.gantt_project_settings%rowtype;
 result jsonb;prior_dates jsonb;item jsonb;entry jsonb;cal jsonb;milestones jsonb;weekdays jsonb;exceptions jsonb;before_record jsonb;field_name text;field_value jsonb;
 pid uuid;changed boolean:=false;expected timestamptz;d date;label text;n int;row_after public.rm_celulas_projeto%rowtype;old_dates jsonb;
begin
 if p_operation is distinct from 'save_gantt_settings' and p_operation is distinct from 'save_gantt_plan' then
  return rm_private.web_mutate_before_gantt_settings_v1(p_client_submission_id,p_operation,p_payload);
 end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'Operacao restrita a administracao/PCP.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticacao de dois fatores.' using errcode='42501';end if;
 if p_operation='save_gantt_plan' then
  if jsonb_typeof(p_payload->'items')='array' then
   select coalesce(jsonb_object_agg(a.id::text,jsonb_build_object('data_inicio',a.data_inicio,'data_limite',a.data_limite)),'{}') into prior_dates
    from public.rm_celulas_projeto a where a.id in(select(x->>'id')::uuid from jsonb_array_elements(p_payload->'items') x);
  end if;
  result:=rm_private.web_mutate_before_gantt_settings_v1(p_client_submission_id,p_operation,p_payload);
  if(result->>'idempotent_replay')::boolean or p_payload?'baseline' then return result;end if;
  for item in select value from jsonb_array_elements(p_payload->'items') loop
   select * into row_after from public.rm_celulas_projeto where id=(item->>'id')::uuid;
   select calendar into cal from rm_private.gantt_project_settings where projeto_id=row_after.projeto_id;
   if cal is null then continue;end if;
   old_dates:=prior_dates->(item->>'id');
   for field_name,field_value in select * from jsonb_each(item->'changes') loop
    if field_name='data_inicio' and row_after.data_inicio is not null and row_after.data_inicio is distinct from (old_dates->>'data_inicio')::timestamptz then
     d:=(row_after.data_inicio at time zone 'America/Sao_Paulo')::date;
    elsif field_name='data_limite' and row_after.data_limite is not null and row_after.data_limite is distinct from (old_dates->>'data_limite')::timestamptz then
     d:=(row_after.data_limite at time zone 'America/Sao_Paulo')::date;
    else continue;end if;
    if not rm_private.gantt_working_day_v1(d,cal) then raise exception 'A data alterada deve ser um dia de trabalho no calendario do projeto.' using errcode='PT409';end if;
   end loop;
  end loop;
  if exists(select 1 from rm_private.gantt_project_settings s join rm_private.gantt_project_plans g on g.projeto_id=s.projeto_id
   cross join lateral jsonb_array_elements(g.links) l
   join public.rm_celulas_projeto a on a.id=(l->>'predecessor_id')::uuid and a.projeto_id=g.projeto_id
   join public.rm_celulas_projeto b on b.id=(l->>'successor_id')::uuid and b.projeto_id=g.projeto_id
   where s.projeto_id in(select(x->>'id')::uuid from jsonb_array_elements(p_payload->'projects') x)
    and not a.retirada and not b.retirada and a.data_limite is not null and b.data_inicio is not null
    and (b.data_inicio at time zone 'America/Sao_Paulo')::date < rm_private.gantt_successor_day_v1((a.data_limite at time zone 'America/Sao_Paulo')::date,(l->>'lag_days')::int,s.calendar)) then
   raise exception 'O plano viola uma dependencia no calendario do projeto. Revise os dias uteis e a espera.' using errcode='PT409';
  end if;
  return result;
 end if;

 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Envio invalido.' using errcode='22023';end if;
 if octet_length(p_payload::text)>2097152 then raise exception 'A configuracao excede o limite de envio.' using errcode='PT413';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation or receipt.payload<>p_payload then raise exception 'Identificador de envio ja utilizado com outro conteudo.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload?&array['projeto_id','expected_updated_at','expected_plan_version','calendar','milestones','reason']
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('projeto_id','expected_updated_at','expected_plan_version','calendar','milestones','reason'))
  or jsonb_typeof(p_payload->'projeto_id') is distinct from 'string'
  or jsonb_typeof(p_payload->'expected_updated_at') is distinct from 'string'
  or(p_payload->>'expected_updated_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or jsonb_typeof(p_payload->'expected_plan_version') is distinct from 'string' or(p_payload->>'expected_plan_version') !~ '^[0-9a-f]{64}$'
  or jsonb_typeof(p_payload->'reason') is distinct from 'string' or length(btrim(p_payload->>'reason')) not between 3 and 2000 then
  raise exception 'Configuracao ou justificativa invalida.' using errcode='22023';end if;
 pid:=(p_payload->>'projeto_id')::uuid;expected:=(p_payload->>'expected_updated_at')::timestamptz;
 if not isfinite(expected) then raise exception 'Versao de projeto invalida.' using errcode='22023';end if;
 cal:=p_payload->'calendar';milestones:=p_payload->'milestones';
 if cal is null or jsonb_typeof(cal)<>'object' or not cal?&array['weekdays','exceptions']
  or exists(select 1 from jsonb_object_keys(cal) k where k not in('weekdays','exceptions'))
  or jsonb_typeof(cal->'weekdays') is distinct from 'array' or jsonb_array_length(cal->'weekdays') not between 1 and 7
  or jsonb_typeof(cal->'exceptions') is distinct from 'array' or jsonb_array_length(cal->'exceptions')>366
  or jsonb_typeof(milestones) is distinct from 'array' or jsonb_array_length(milestones)>100 then raise exception 'Calendario ou marcos invalidos.' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(cal->'weekdays') day_value where jsonb_typeof(day_value)<>'number' or day_value::text !~ '^[1-7]$')
  or (select count(distinct value) from jsonb_array_elements(cal->'weekdays'))<>jsonb_array_length(cal->'weekdays') then raise exception 'Escolha dias da semana distintos entre 1 e 7.' using errcode='22023';end if;
 select jsonb_agg(day_value::int order by day_value::int) into weekdays from jsonb_array_elements_text(cal->'weekdays') day_value;
 for entry in select value from jsonb_array_elements(cal->'exceptions') loop
  if jsonb_typeof(entry)<>'object' or not entry?&array['date','working','label'] or exists(select 1 from jsonb_object_keys(entry) k where k not in('date','working','label'))
   or jsonb_typeof(entry->'date') is distinct from 'string' or(entry->>'date') !~ '^\d{4}-\d{2}-\d{2}$'
   or jsonb_typeof(entry->'working') is distinct from 'boolean' or jsonb_typeof(entry->'label') is distinct from 'string' or length(btrim(entry->>'label')) not between 1 and 120 then raise exception 'Excecao do calendario invalida.' using errcode='22023';end if;
  d:=(entry->>'date')::date;
  if d not between '1900-01-01'::date and '2200-12-31'::date then raise exception 'Data fora do intervalo permitido.' using errcode='22023';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(cal->'exceptions') e group by e->>'date' having count(*)>1) then raise exception 'Data de excecao repetida.' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('date',e->>'date','working',(e->>'working')::boolean,'label',btrim(e->>'label')) order by e->>'date'),'[]') into exceptions from jsonb_array_elements(cal->'exceptions') e;
 cal:=jsonb_build_object('weekdays',weekdays,'exceptions',exceptions);
 for entry in select value from jsonb_array_elements(milestones) loop
  if jsonb_typeof(entry)<>'object' or not entry?&array['id','label','date'] or exists(select 1 from jsonb_object_keys(entry) k where k not in('id','label','date'))
   or jsonb_typeof(entry->'id') is distinct from 'string' or jsonb_typeof(entry->'label') is distinct from 'string' or length(btrim(entry->>'label')) not between 1 and 120
   or jsonb_typeof(entry->'date') is distinct from 'string' or(entry->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Marco do projeto invalido.' using errcode='22023';end if;
  perform(entry->>'id')::uuid;d:=(entry->>'date')::date;
  if d not between '1900-01-01'::date and '2200-12-31'::date then raise exception 'Data fora do intervalo permitido.' using errcode='22023';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(milestones) e group by(e->>'id')::uuid having count(*)>1) then raise exception 'Identificador de marco repetido.' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',(e->>'id')::uuid,'label',btrim(e->>'label'),'date',e->>'date') order by e->>'date',(e->>'id')::uuid),'[]') into milestones from jsonb_array_elements(milestones) e;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,11));
 select * into p from public.rm_projetos where id=pid for update;
 if not found then raise exception 'Projeto inexistente.' using errcode='P0002';end if;
 if p.updated_at is distinct from expected then raise exception 'O projeto mudou. Recarregue o cronograma.' using errcode='PT409';end if;
 if p.data_real_de_entrega is not null or p.status_pcp in('cancelado','finalizando_para_faturar') then raise exception 'Projeto encerrado: somente consulta.' using errcode='22023';end if;
 perform 1 from public.rm_celulas_projeto where projeto_id=pid order by id for update;
 perform 1 from rm_private.gantt_project_plans where projeto_id=pid for update;
 select * into stored from rm_private.gantt_project_settings where projeto_id=pid for update;
 if rm_private.web_gantt_project_version_v1(pid) is distinct from p_payload->>'expected_plan_version' then raise exception 'O planejamento mudou. Recarregue antes de salvar.' using errcode='PT409';end if;
 if(select count(*) from public.rm_celulas_projeto where projeto_id=pid and not retirada)>2000 then raise exception 'O roteiro excede o limite de planejamento.' using errcode='PT413';end if;
 before_record:=jsonb_build_object('projeto_id',pid,'settings',case when stored.id is null then null else to_jsonb(stored) end);
 changed:=case when stored.id is null then cal<>'{"weekdays":[1,2,3,4,5,6,7],"exceptions":[]}'::jsonb or milestones<>'[]'::jsonb else stored.calendar is distinct from cal or stored.milestones is distinct from milestones end;
 if changed then
  insert into rm_private.gantt_project_settings(projeto_id,calendar,milestones,updated_by) values(pid,cal,milestones,actor.id)
   on conflict(projeto_id) do update set calendar=excluded.calendar,milestones=excluded.milestones,updated_at=clock_timestamp(),updated_by=excluded.updated_by;
 end if;
 result:=jsonb_build_object('operation',p_operation,'id',pid,'projeto_id',pid,'updated_at',clock_timestamp(),'record',jsonb_build_object('settings_changed',changed),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,before_record);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation is distinct from 'save_gantt_settings' and p_operation is distinct from 'save_gantt_plan' then raise;end if;
 raise exception 'Identificador, versao ou data invalidos.' using errcode='22023';
end $$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_gantt_settings_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

do $$declare d text;constraint_definition text;needle text:='when ''save_gantt_plan'' then ''em.planning.manage''';begin
 select pg_get_constraintdef(oid) into constraint_definition from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check';
 if strpos(constraint_definition,'''save_gantt_plan''::text')=0 then raise exception 'Migration047 required';end if;
 constraint_definition:=replace(constraint_definition,'''save_gantt_plan''::text','''save_gantt_plan''::text, ''save_gantt_settings''::text');
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check '||constraint_definition;
 d:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected SSO capability map';end if;
 execute replace(d,needle,needle||' when ''save_gantt_settings'' then ''em.planning.manage''');
 -- Rebind warmed statements to the new names while preserving old function OIDs.
 execute pg_get_functiondef('rm_private.web_mutate_before_gantt_settings_v1(uuid,text,jsonb)'::regprocedure);
 execute pg_get_functiondef('rm_private.web_gantt_snapshot_before_calendar_v1(jsonb)'::regprocedure);
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end $$;
notify pgrst,'reload schema';
commit;
