-- Execution evidence is separate from planning, approvals and legacy actual hours.
-- Installation creates no sessions, events, reviews or inferred effort.
begin;

create table rm_private.execution_sessions(
 id uuid primary key,
 allocation_id uuid not null references public.rm_celulas_projeto(id) on delete restrict,
 operator_id uuid not null references public.rm_users(id) on delete restrict,
 state text not null check(state in('running','paused','finished','review','void')),
 needs_review boolean not null default false,
 clock_warning boolean not null default false,
 last_event_id uuid,
 last_received_event_id uuid,
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp()
);
create unique index rm_execution_operator_running on rm_private.execution_sessions(operator_id) where state='running';
create unique index rm_execution_operator_allocation_open on rm_private.execution_sessions(operator_id,allocation_id) where state in('running','paused');
create index rm_execution_allocation on rm_private.execution_sessions(allocation_id,updated_at,id);
create table rm_private.execution_events(
 id uuid primary key,
 session_id uuid not null references rm_private.execution_sessions(id) on delete restrict,
 previous_event_id uuid,
 sequence bigint generated always as identity unique,
 kind text not null check(kind in('start','pause','resume','finish')),
 occurred_at timestamptz not null,
 received_at timestamptz not null default clock_timestamp(),
 pause_reason text check(pause_reason in('material','cliente','engenharia','ferramenta','maquina','manutencao','transporte','servico_externo','intervalo','outro')),
 note text check(length(note)<=1000),
 effort_minutes integer check(effort_minutes between 0 and 1000000),
 disposition text not null check(disposition in('accepted','review')),
 review_reason text,
 operator_id uuid not null references public.rm_users(id) on delete restrict,
 tablet_user_id uuid not null references public.rm_users(id) on delete restrict,
 auth_user_id uuid not null references auth.users(id) on delete restrict,
 check((kind='pause')=(pause_reason is not null)),
 check(kind='finish' or effort_minutes is null)
);
create index rm_execution_event_session on rm_private.execution_events(session_id,sequence);
create table rm_private.execution_reviews(
 id uuid primary key,
 session_id uuid not null references rm_private.execution_sessions(id) on delete restrict,
 action text not null check(action in('confirm_finished','void')),
 reported_finished_at timestamptz,
 effort_minutes integer check(effort_minutes between 0 and 1000000),
 note text not null check(length(note)<=1000),
 reason text not null check(length(btrim(reason)) between 3 and 2000),
 actor_id uuid not null references public.rm_users(id) on delete restrict,
 through_event_id uuid,
 created_at timestamptz not null default clock_timestamp(),
 check((action='confirm_finished' and reported_finished_at is not null) or(action='void' and reported_finished_at is null and effort_minutes is null))
);
create index rm_execution_review_session on rm_private.execution_reviews(session_id,created_at,id);
revoke all on rm_private.execution_sessions,rm_private.execution_events,rm_private.execution_reviews from public,anon,authenticated,service_role;
revoke all on sequence rm_private.execution_events_sequence_seq from public,anon,authenticated,service_role;
alter table rm_private.execution_sessions enable row level security;
alter table rm_private.execution_events enable row level security;
alter table rm_private.execution_reviews enable row level security;
grant select on rm_private.execution_sessions,rm_private.execution_events,rm_private.execution_reviews to authenticated;
create policy rm_execution_sessions_read on rm_private.execution_sessions for select to authenticated using(rm_private.web_gantt_read_allowed_v1() and exists(select 1 from public.rm_celulas_projeto a where a.id=allocation_id));
create policy rm_execution_events_read on rm_private.execution_events for select to authenticated using(rm_private.web_gantt_read_allowed_v1() and exists(select 1 from rm_private.execution_sessions s where s.id=session_id));
create policy rm_execution_reviews_read on rm_private.execution_reviews for select to authenticated using(rm_private.web_gantt_read_allowed_v1() and exists(select 1 from rm_private.execution_sessions s where s.id=session_id));

create function rm_private.execution_immutable_v1() returns trigger language plpgsql set search_path='' as $$begin
 raise exception 'Execution evidence is immutable; append a management review.' using errcode='42501';
end$$;
revoke all on function rm_private.execution_immutable_v1() from public,anon,authenticated,service_role;
create trigger rm_execution_events_immutable before update on rm_private.execution_events for each row execute function rm_private.execution_immutable_v1();
create trigger rm_execution_reviews_immutable before update on rm_private.execution_reviews for each row execute function rm_private.execution_immutable_v1();

create function rm_private.execution_session_version_v1(p_session uuid) returns text
language sql stable security invoker set search_path='' as $$
 select encode(sha256(convert_to(jsonb_build_object('session',to_jsonb(s),
 'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.sequence) from rm_private.execution_events e where e.session_id=s.id),'[]'),
 'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at,r.id) from rm_private.execution_reviews r where r.session_id=s.id),'[]'))::text,'UTF8')),'hex')
 from rm_private.execution_sessions s where s.id=p_session;
$$;
create function rm_private.execution_session_summary_v1(p_session uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',s.id,'allocation_id',a.id,'project_id',a.projeto_id,'cell_id',a.celula_id,
 'numero_projeto',coalesce(a.numero_projeto,p.numero),'cell_name',c.nome,'operator_id',s.operator_id,'operator_name',u.nome,
 'state',s.state,'needs_review',s.needs_review,'last_event_id',s.last_event_id,
 'can_record',not a.retirada and a.visibilidade and coalesce(a.bloqueada<>'sim',true) and coalesce(a.status not in('finalizado','n_a'),true)
  and p.data_real_de_entrega is null and coalesce(p.status_pcp not in('cancelado','finalizando_para_faturar'),true),
 'last_captured_at',latest.occurred_at,'last_received_at',latest.received_at,'version',rm_private.execution_session_version_v1(s.id),
 'confirmed_minutes',case when review.id is not null then case when review.action='confirm_finished' then review.effort_minutes else null end
  when s.state='finished' then finish.effort_minutes else null end,
 'effort_source',case when review.id is not null and review.action='confirm_finished' and review.effort_minutes is not null then 'manager'
  when review.id is null and s.state='finished' and finish.effort_minutes is not null then 'operator' else null end,
 'clock_warning',s.clock_warning,
 'has_review',review.id is not null)
 from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id
 join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id join public.rm_users u on u.id=s.operator_id
 left join lateral(select e.occurred_at,e.received_at from rm_private.execution_events e where e.session_id=s.id order by e.sequence desc limit 1)latest on true
 left join lateral(select e.effort_minutes from rm_private.execution_events e where e.id=s.last_event_id and e.kind='finish' and e.disposition='accepted')finish on true
 left join lateral(select r.id,r.action,r.effort_minutes from rm_private.execution_reviews r where r.session_id=s.id order by r.created_at desc,r.id desc limit 1)review on true
 where s.id=p_session;
$$;
create function rm_private.execution_session_detail_v1(p_session uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare estimated bigint;result jsonb;
begin
 select coalesce((select sum(octet_length(coalesce(u.nome,''))+octet_length(coalesce(e.note,''))+1600)
  from(select * from rm_private.execution_events where session_id=p_session order by sequence desc limit 200)e join public.rm_users u on u.id=e.operator_id),0)
  +coalesce((select sum(octet_length(coalesce(u.nome,''))+octet_length(r.note)+octet_length(r.reason)+1200)
  from(select * from rm_private.execution_reviews where session_id=p_session order by created_at desc,id desc limit 100)r join public.rm_users u on u.id=r.actor_id),0)
  +coalesce((select octet_length(coalesce(u.nome,''))+octet_length(coalesce(p.numero,''))+octet_length(coalesce(a.numero_projeto,''))+octet_length(coalesce(c.nome,''))+2500
  from rm_private.execution_sessions s join public.rm_users u on u.id=s.operator_id join public.rm_celulas_projeto a on a.id=s.allocation_id
  join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id where s.id=p_session),0) into estimated;
 if estimated>10485760 then raise exception 'O histórico excede o limite de consulta completa.' using errcode='PT413';end if;
 select jsonb_build_object('session',rm_private.execution_session_summary_v1(p_session),
 'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'session_id',e.session_id,'previous_event_id',e.previous_event_id,
  'kind',e.kind,'occurred_at',e.occurred_at,'received_at',e.received_at,'pause_reason',e.pause_reason,'note',e.note,'effort_minutes',e.effort_minutes,
  'disposition',e.disposition,'review_reason',e.review_reason,'operator_id',e.operator_id,'operator_name',u.nome,'source','mobile') order by e.sequence)
  from(select * from rm_private.execution_events where session_id=p_session order by sequence desc limit 200)e join public.rm_users u on u.id=e.operator_id),'[]'),
 'events_total',(select count(*) from rm_private.execution_events where session_id=p_session),
 'events_complete',(select count(*)<=200 from rm_private.execution_events where session_id=p_session),
 'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'session_id',r.session_id,'action',r.action,'reported_finished_at',r.reported_finished_at,
  'effort_minutes',r.effort_minutes,'note',r.note,'reason',r.reason,'actor_name',u.nome,'created_at',r.created_at) order by r.created_at,r.id)
  from(select * from rm_private.execution_reviews where session_id=p_session order by created_at desc,id desc limit 100)r join public.rm_users u on u.id=r.actor_id),'[]'),
 'reviews_total',(select count(*) from rm_private.execution_reviews where session_id=p_session),
 'reviews_complete',(select count(*)<=100 from rm_private.execution_reviews where session_id=p_session)) into result;
 if octet_length(result::text)>10485760 then raise exception 'O histórico excede o limite de consulta completa.' using errcode='PT413';end if;
 return result;
end;
$$;
revoke all on function rm_private.execution_session_version_v1(uuid),rm_private.execution_session_summary_v1(uuid),rm_private.execution_session_detail_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function rm_private.execution_session_version_v1(uuid),rm_private.execution_session_summary_v1(uuid),rm_private.execution_session_detail_v1(uuid) to authenticated;

-- Keep the public OID/ACL/owner, including warmed gateway callers.
do $$declare definition text;needle text:='FUNCTION public.rm_mobile_mutate_v1(';begin
 definition:=pg_get_functiondef('public.rm_mobile_mutate_v1(uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected legacy mobile gateway';end if;
 execute replace(definition,needle,'FUNCTION rm_private.mobile_mutate_before_execution_v1(');
end$$;
revoke all on function rm_private.mobile_mutate_before_execution_v1(uuid,text,jsonb,text) from public,anon,authenticated,service_role;
create or replace function public.rm_mobile_mutate_v1(p_client_submission_id uuid,p_rpc_name text,p_params jsonb,p_operator_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d rm_private.operator_delegations%rowtype;op public.rm_users%rowtype;receipt rm_private.mobile_mutation_receipts%rowtype;
 a public.rm_celulas_projeto%rowtype;p public.rm_projetos%rowtype;s rm_private.execution_sessions%rowtype;
 v_params jsonb;result jsonb;sid uuid;previous uuid;occurred timestamptz;why text;new_state text;kind text;pause text;note text;effort integer;prior_lock_timeout text;
begin
 if p_rpc_name is distinct from 'rm_record_execution_event_v1' then return rm_private.mobile_mutate_before_execution_v1(p_client_submission_id,p_rpc_name,p_params,p_operator_token);end if;
 prior_lock_timeout:=current_setting('lock_timeout');perform set_config('lock_timeout','10s',true);
 if p_client_submission_id is null or p_params is null or jsonb_typeof(p_params)<>'object' or octet_length(p_params::text)>65536 then raise exception 'Apontamento de execução inválido.' using errcode='22023';end if;
 select * into d from rm_private.operator_delegations where token_hash=extensions.digest(p_operator_token,'sha256') and auth_user_id=auth.uid() and not revoked and expires_at>clock_timestamp();
 if d.operator_id is null or rm_private.current_rm_user_id() is distinct from d.tablet_user_id then raise exception 'Identifique novamente o mesmo operador neste dispositivo.' using errcode='28000';end if;
 select * into op from public.rm_users where id=d.operator_id and status='ativo';
 if op.id is null then raise exception 'Operador inativo.' using errcode='28000';end if;
 if not p_params?&array['p_session_id','p_allocation_id','p_previous_event_id','p_kind','p_occurred_at','p_pause_reason','p_note','p_effort_minutes','p_operador_id']
  or exists(select 1 from jsonb_object_keys(p_params) k where k not in('p_session_id','p_allocation_id','p_previous_event_id','p_kind','p_occurred_at','p_pause_reason','p_note','p_effort_minutes','p_operador_id')) then raise exception 'Campos do apontamento de execução inválidos.' using errcode='22023';end if;
 if jsonb_typeof(p_params->'p_operador_id') is distinct from 'string' or(p_params->>'p_operador_id')::uuid<>d.operator_id then raise exception 'A identidade do apontamento diverge do operador identificado.' using errcode='42501';end if;
 v_params:=p_params-'p_operador_id';
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,0));
 select * into receipt from rm_private.mobile_mutation_receipts where client_submission_id=p_client_submission_id;
 if found and receipt.result->'resource_deleted'='true'::jsonb then
  if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>p_rpc_name or receipt.params->>'original_sha256' is distinct from encode(sha256(convert_to(v_params::text,'UTF8')),'hex') then raise exception 'Este protocolo já foi utilizado com outro conteúdo.' using errcode='22023';end if;
  raise exception 'Este projeto foi excluído. Preserve os apontamentos pendentes para reconciliação.' using errcode='PT410';
 end if;
 select * into a from public.rm_celulas_projeto where id=(p_params->>'p_allocation_id')::uuid;
 if a.id is null then raise exception 'A etapa do projeto não está disponível.' using errcode='P0002';end if;
 perform rm_private.assert_cell_access(d.operator_id,a.celula_id);
 if receipt.client_submission_id is not null then
  if receipt.auth_user_id<>auth.uid() or receipt.operator_id<>d.operator_id or receipt.rpc_name<>p_rpc_name or receipt.params<>v_params then raise exception 'Este protocolo já foi utilizado com outro conteúdo.' using errcode='22023';end if;
  perform set_config('lock_timeout',prior_lock_timeout,true);
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if jsonb_typeof(p_params->'p_session_id') is distinct from 'string' or jsonb_typeof(p_params->'p_allocation_id') is distinct from 'string'
  or jsonb_typeof(p_params->'p_previous_event_id') not in('null','string')
  or jsonb_typeof(p_params->'p_kind') is distinct from 'string' or p_params->>'p_kind' not in('start','pause','resume','finish')
  or jsonb_typeof(p_params->'p_occurred_at') is distinct from 'string' or p_params->>'p_occurred_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
  or jsonb_typeof(p_params->'p_pause_reason') not in('null','string') or jsonb_typeof(p_params->'p_note') not in('null','string')
  or length(p_params->>'p_note')>1000 or jsonb_typeof(p_params->'p_effort_minutes') not in('null','number') then raise exception 'Confira os valores do apontamento de execução.' using errcode='22023';end if;
 sid:=(p_params->>'p_session_id')::uuid;previous:=(p_params->>'p_previous_event_id')::uuid;kind:=p_params->>'p_kind';occurred:=(p_params->>'p_occurred_at')::timestamptz;
 pause:=p_params->>'p_pause_reason';note:=p_params->>'p_note';
 if p_params->>'p_effort_minutes' is not null then
  if p_params->>'p_effort_minutes' !~ '^\d{1,7}$' or(p_params->>'p_effort_minutes')::int>1000000 then raise exception 'Informe uma quantidade válida de minutos trabalhados.' using errcode='22023';end if;
  effort:=(p_params->>'p_effort_minutes')::int;
 end if;
 if not isfinite(occurred) or(occurred at time zone 'UTC')::date not between '1900-01-01'::date and '2200-12-31'::date
  or(kind='pause' and(pause is null or pause not in('material','cliente','engenharia','ferramenta','maquina','manutencao','transporte','servico_externo','intervalo','outro') or(pause='outro' and length(btrim(coalesce(note,'')))<3)))
  or(kind<>'pause' and pause is not null) or(kind<>'finish' and effort is not null) then raise exception 'Confira o horário, o motivo da pausa e os minutos informados.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(a.projeto_id::text,11));
 select * into p from public.rm_projetos where id=a.projeto_id for update;
 if p.id is null then raise exception 'O projeto não está disponível.' using errcode='P0002';end if;
 perform 1 from public.rm_celulas_projeto where projeto_id=p.id order by id for update;
 select * into a from public.rm_celulas_projeto where id=(p_params->>'p_allocation_id')::uuid;
 if a.id is null then raise exception 'A etapa do projeto não está disponível.' using errcode='P0002';end if;
 perform rm_private.assert_cell_access(d.operator_id,a.celula_id);
 perform pg_advisory_xact_lock(hashtextextended(d.operator_id::text,51));
 select * into s from rm_private.execution_sessions where id=sid for update;
 if s.id is not null and(s.operator_id<>d.operator_id or s.allocation_id<>a.id) then raise exception 'Este apontamento pertence a outro operador ou a outra etapa.' using errcode='42501';end if;
 if s.id is null then
  insert into rm_private.execution_sessions(id,allocation_id,operator_id,state) values(sid,a.id,d.operator_id,'review') returning * into s;
  if kind<>'start' or previous is not null then why:='missing_start';end if;
 elsif s.needs_review then why:='unresolved_evidence';
 elsif exists(select 1 from rm_private.execution_reviews where session_id=s.id) then why:='after_management_review';
 elsif kind='start' then why:='duplicate_start';
 elsif previous is distinct from s.last_event_id then why:='previous_event_mismatch';
 elsif not((kind='pause' and s.state='running') or(kind='resume' and s.state='paused') or(kind='finish' and s.state in('running','paused'))) then why:='invalid_transition';
 end if;
 if why is null and(a.retirada or not a.visibilidade or a.bloqueada='sim' or a.status in('finalizado','n_a') or p.data_real_de_entrega is not null or p.status_pcp in('cancelado','finalizando_para_faturar')) then why:='allocation_changed';end if;
 if why is null and kind='start' and exists(select 1 from rm_private.execution_sessions other where other.operator_id=d.operator_id and other.allocation_id=a.id and other.id<>sid and other.state in('running','paused')) then why:='another_open_session';end if;
 if why is null and kind in('start','resume') and exists(select 1 from rm_private.execution_sessions other where other.operator_id=d.operator_id and other.id<>sid and other.state='running') then why:='operator_already_running';end if;
 new_state:=case kind when 'start' then 'running' when 'pause' then 'paused' when 'resume' then 'running' when 'finish' then 'finished' end;
 insert into rm_private.execution_events(id,session_id,previous_event_id,kind,occurred_at,pause_reason,note,effort_minutes,disposition,review_reason,operator_id,tablet_user_id,auth_user_id)
 values(p_client_submission_id,sid,previous,kind,occurred,pause,note,effort,case when why is null then 'accepted' else 'review' end,why,d.operator_id,d.tablet_user_id,auth.uid());
 update rm_private.execution_sessions set state=case when why is null then new_state else state end,needs_review=needs_review or why is not null,
  clock_warning=clock_warning or(why is null and(occurred>(select received_at+interval '15 minutes' from rm_private.execution_events where id=p_client_submission_id)
   or coalesce(occurred<(select occurred_at from rm_private.execution_events where id=s.last_event_id),false))),
  last_event_id=case when why is null then p_client_submission_id else last_event_id end,last_received_event_id=p_client_submission_id,updated_at=clock_timestamp() where id=sid;
 result:=jsonb_build_object('event_id',p_client_submission_id,'session_id',sid,'projeto_id',p.id,'disposition',case when why is null then 'accepted' else 'review' end,
  'review_reason',why,'received_at',(select received_at from rm_private.execution_events where id=p_client_submission_id),'idempotent_replay',false);
 insert into rm_private.mobile_mutation_receipts(client_submission_id,auth_user_id,operator_id,rpc_name,params,result) values(p_client_submission_id,auth.uid(),d.operator_id,p_rpc_name,v_params,result);
 perform set_config('lock_timeout',prior_lock_timeout,true);
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_rpc_name is distinct from 'rm_record_execution_event_v1' then raise;end if;
 raise exception 'Confira os identificadores, horários e minutos do apontamento.' using errcode='22023';
end$$;

create function public.rm_mobile_execution_snapshot_v1(p_operator_token text,p_allocation_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d rm_private.operator_delegations%rowtype;a public.rm_celulas_projeto%rowtype;sid uuid;running uuid;detail jsonb;result jsonb;reviews jsonb;review_count bigint;
begin
 select * into d from rm_private.operator_delegations where token_hash=extensions.digest(p_operator_token,'sha256') and auth_user_id=auth.uid() and not revoked and expires_at>clock_timestamp();
 if d.operator_id is null or rm_private.current_rm_user_id() is distinct from d.tablet_user_id or not exists(select 1 from public.rm_users where id=d.operator_id and status='ativo') then raise exception 'Identifique novamente o mesmo operador neste dispositivo.' using errcode='28000';end if;
 select * into a from public.rm_celulas_projeto where id=p_allocation_id;
 if a.id is null then raise exception 'A etapa do projeto não está disponível.' using errcode='P0002';end if;
 perform rm_private.assert_cell_access(d.operator_id,a.celula_id);
 select id into sid from rm_private.execution_sessions where allocation_id=a.id and operator_id=d.operator_id order by(state in('running','paused')) desc,updated_at desc,id desc limit 1;
 select s.id into running from rm_private.execution_sessions s join public.rm_celulas_projeto other on other.id=s.allocation_id where s.operator_id=d.operator_id and s.state='running' and rm_private.operator_can_access_cell(d.operator_id,other.celula_id);
 if sid is not null then
  begin detail:=rm_private.execution_session_detail_v1(sid);
  exception when sqlstate 'PT413' then
   detail:=jsonb_build_object('session',rm_private.execution_session_summary_v1(sid),'events','[]'::jsonb,
    'events_total',(select count(*) from rm_private.execution_events where session_id=sid),'events_complete',not exists(select 1 from rm_private.execution_events where session_id=sid),
    'reviews','[]'::jsonb,'reviews_total',(select count(*) from rm_private.execution_reviews where session_id=sid),'reviews_complete',not exists(select 1 from rm_private.execution_reviews where session_id=sid));
  end;
 end if;
 select count(*) into review_count from rm_private.execution_sessions where allocation_id=a.id and operator_id=d.operator_id and needs_review;
 select coalesce(jsonb_agg(rm_private.execution_session_summary_v1(s.id) order by s.updated_at,s.id),'[]') into reviews from(select * from rm_private.execution_sessions where allocation_id=a.id and operator_id=d.operator_id and needs_review order by updated_at desc,id desc limit 50)s;
 select jsonb_build_object('as_of',statement_timestamp(),'operator_id',d.operator_id,
  'allocation',jsonb_build_object('id',a.id,'project_id',a.projeto_id,'cell_id',a.celula_id,'numero_projeto',coalesce(a.numero_projeto,p.numero),'cell_name',c.nome,
   'status',a.status,'retired',a.retirada,'project_closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false),
   'visible',a.visibilidade,'blocked',coalesce(a.bloqueada='sim',false),'updated_at',a.updated_at),
  'running_session',case when running is null then null else rm_private.execution_session_summary_v1(running) end,
  'session',detail->'session','events',coalesce(detail->'events','[]'),'events_total',coalesce(detail->'events_total','0'),'events_complete',coalesce(detail->'events_complete','true'),
  'reviews',coalesce(detail->'reviews','[]'),'reviews_total',coalesce(detail->'reviews_total','0'),'reviews_complete',coalesce(detail->'reviews_complete','true'),
  'review_sessions',reviews,'review_sessions_total',review_count,'review_sessions_complete',review_count<=50) into result
 from public.rm_projetos p join public.rm_celulas c on c.id=a.celula_id where p.id=a.projeto_id;
 if octet_length(result::text)>2097152 then
  result:=result||jsonb_build_object('events','[]'::jsonb,'events_complete',coalesce((result->>'events_total')::bigint=0,true),
   'reviews','[]'::jsonb,'reviews_complete',coalesce((result->>'reviews_total')::bigint=0,true));
 end if;
 if octet_length(result::text)>2097152 then
  result:=result||jsonb_build_object('review_sessions','[]'::jsonb,'review_sessions_complete',review_count=0);
 end if;
 if octet_length(result::text)>2097152 then raise exception 'Os metadados excedem o limite de consulta do dispositivo.' using errcode='PT413';end if;
 return result;
end$$;
revoke all on function public.rm_mobile_execution_snapshot_v1(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rm_mobile_execution_snapshot_v1(text,uuid) to authenticated;

create function public.rm_web_execution_snapshot_v1(p_filters jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare pid uuid;cid uuid;sid uuid;closed boolean;allocation_ids uuid[];session_ids uuid[];n bigint;result jsonb;detail jsonb;estimated bigint;
begin
 if not coalesce(rm_private.web_gantt_read_allowed_v1(),false) then raise exception 'Acesso aos apontamentos não autorizado.' using errcode='42501';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or not p_filters?&array['project_id','cell_id','session_id','include_closed']
  or exists(select 1 from jsonb_object_keys(p_filters)k where k not in('project_id','cell_id','session_id','include_closed'))
  or jsonb_typeof(p_filters->'project_id') not in('null','string') or jsonb_typeof(p_filters->'cell_id') not in('null','string') or jsonb_typeof(p_filters->'session_id') not in('null','string')
  or jsonb_typeof(p_filters->'include_closed') is distinct from 'boolean' then raise exception 'Filtros de execução inválidos.' using errcode='22023';end if;
 pid:=(p_filters->>'project_id')::uuid;cid:=(p_filters->>'cell_id')::uuid;sid:=(p_filters->>'session_id')::uuid;closed:=(p_filters->>'include_closed')::boolean;
 select coalesce(array_agg(a.id order by a.id),'{}'),count(*) into allocation_ids,n from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id
 where(pid is null or a.projeto_id=pid) and(cid is null or a.celula_id=cid) and(pid is not null or closed or
  (not a.retirada and p.data_real_de_entrega is null and coalesce(p.status_pcp not in('cancelado','finalizando_para_faturar'),true)) or
  exists(select 1 from rm_private.execution_sessions s where s.allocation_id=a.id and(s.state in('running','paused','review') or s.needs_review or s.id=sid
   or(s.clock_warning and not exists(select 1 from rm_private.execution_reviews r where r.session_id=s.id)))));
 result:=jsonb_build_object('as_of',statement_timestamp(),'filters',p_filters,'complete',false,'total',n,'allocations','[]'::jsonb,'sessions','[]'::jsonb,'detail',null);
 if n>2000 then return result;end if;
 select coalesce(array_agg(s.id order by s.id),'{}') into session_ids from rm_private.execution_sessions s where s.allocation_id=any(allocation_ids) and
  (s.state in('running','paused','review') or s.needs_review or s.id=sid or(s.clock_warning and not exists(select 1 from rm_private.execution_reviews r where r.session_id=s.id))
   or s.id=(select latest.id from rm_private.execution_sessions latest where latest.operator_id=s.operator_id and latest.allocation_id=s.allocation_id order by latest.updated_at desc,latest.id desc limit 1));
 if cardinality(session_ids)>4000 then return result;end if;
 select coalesce((select sum(octet_length(coalesce(a.numero_projeto,''))+octet_length(coalesce(a.cliente_nome_export,''))+octet_length(coalesce(p.numero,''))+octet_length(coalesce(p.cliente_nome_exportacao,''))+octet_length(coalesce(c.nome,''))+1200)
  from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id where a.id=any(allocation_ids)),0)
  +coalesce((select sum(octet_length(coalesce(u.nome,''))+octet_length(coalesce(p.numero,''))+octet_length(coalesce(a.numero_projeto,''))+octet_length(coalesce(c.nome,''))+1500)
  from rm_private.execution_sessions s join public.rm_users u on u.id=s.operator_id join public.rm_celulas_projeto a on a.id=s.allocation_id
  join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id where s.id=any(session_ids)),0) into estimated;
 if estimated>10485760 then return result;end if;
 if sid is not null then
  if not exists(select 1 from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id where s.id=sid and(pid is null or a.projeto_id=pid) and(cid is null or a.celula_id=cid)) then raise exception 'O apontamento não está disponível neste contexto.' using errcode='P0002';end if;
  begin detail:=rm_private.execution_session_detail_v1(sid);exception when sqlstate 'PT413' then return result;end;
 end if;
 result:=result||jsonb_build_object('complete',true,'allocations',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'project_id',a.projeto_id,'cell_id',a.celula_id,
  'numero_projeto',coalesce(a.numero_projeto,p.numero),'cliente_nome',coalesce(a.cliente_nome_export,p.cliente_nome_exportacao),'cell_name',c.nome,'status',a.status,
  'retired',a.retirada,'project_closed',p.data_real_de_entrega is not null or coalesce(p.status_pcp in('cancelado','finalizando_para_faturar'),false),
  'visible',a.visibilidade,'blocked',coalesce(a.bloqueada='sim',false),'planned_start',a.data_inicio,'planned_end',a.data_limite,'updated_at',a.updated_at) order by a.projeto_id,a.indice nulls last,a.id)
  from public.rm_celulas_projeto a join public.rm_projetos p on p.id=a.projeto_id join public.rm_celulas c on c.id=a.celula_id where a.id=any(allocation_ids)),'[]'),
  'sessions',coalesce((select jsonb_agg(rm_private.execution_session_summary_v1(s.id) order by s.updated_at desc,s.id) from rm_private.execution_sessions s where s.id=any(session_ids)),'[]'),'detail',detail);
 if octet_length(result::text)>10485760 then return jsonb_build_object('as_of',statement_timestamp(),'filters',p_filters,'complete',false,'total',n,'allocations','[]'::jsonb,'sessions','[]'::jsonb,'detail',null);end if;
 return result;
exception when invalid_text_representation then raise exception 'Filtros de execução inválidos.' using errcode='22023';
end$$;
revoke all on function public.rm_web_execution_snapshot_v1(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.rm_web_execution_snapshot_v1(jsonb) to authenticated;

-- Reviews and events belong to their project; shared capacity resources survive.
alter function rm_private.project_delete_scope_v1(uuid) rename to project_delete_scope_before_execution_v1;
create function rm_private.project_delete_scope_v1(p_project uuid) returns table(schema_name text,table_name text,ids uuid[])
language sql stable security definer set search_path='' as $$
 select * from rm_private.project_delete_scope_before_execution_v1(p_project)
 union all select 'rm_private','execution_reviews',array(select r.id from rm_private.execution_reviews r join rm_private.execution_sessions s on s.id=r.session_id join public.rm_celulas_projeto a on a.id=s.allocation_id where a.projeto_id=p_project)
 union all select 'rm_private','execution_events',array(select e.id from rm_private.execution_events e join rm_private.execution_sessions s on s.id=e.session_id join public.rm_celulas_projeto a on a.id=s.allocation_id where a.projeto_id=p_project)
 union all select 'rm_private','execution_sessions',array(select s.id from rm_private.execution_sessions s join public.rm_celulas_projeto a on a.id=s.allocation_id where a.projeto_id=p_project);
$$;
revoke all on function rm_private.project_delete_scope_v1(uuid),rm_private.project_delete_scope_before_execution_v1(uuid) from public,anon,authenticated,service_role;
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('rm_private.web_mutate_before_route_config_v1(uuid,text,jsonb)'::regprocedure);
 needle:='foreach label in array array[''rm_private.capacity_bookings''';
 if strpos(definition,needle)=0 then raise exception 'Unexpected execution deletion order';end if;
 definition:=replace(definition,needle,'foreach label in array array[''rm_private.execution_reviews'',''rm_private.execution_events'',''rm_private.execution_sessions'',''rm_private.capacity_bookings''');
 needle:='for s in select * from rm_private.project_delete_scope_v1(pid) order by schema_name,table_name loop';
 if strpos(definition,needle)=0 then raise exception 'Unexpected execution deletion locks';end if;
 execute replace(definition,needle,'for s in select distinct es.operator_id from rm_private.execution_sessions es join public.rm_celulas_projeto a on a.id=es.allocation_id where a.projeto_id=pid order by es.operator_id loop
  perform pg_advisory_xact_lock(hashtextextended(s.operator_id::text,51));
 end loop;
 '||needle);
 execute pg_get_functiondef('rm_private.project_delete_context_v1(uuid)'::regprocedure);
end$$;

alter function rm_private.web_mutate_core_v1(uuid,text,jsonb) rename to web_mutate_before_execution_v1;
create function rm_private.web_mutate_core_v1(p_client_submission_id uuid,p_operation text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='10s' as $$
declare actor public.rm_users%rowtype;receipt rm_private.web_mutation_receipts%rowtype;s rm_private.execution_sessions%rowtype;
 a public.rm_celulas_projeto%rowtype;review_id uuid:=gen_random_uuid();reported timestamptz;effort int;result jsonb;
begin
 if p_operation is distinct from 'review_execution_session' then return rm_private.web_mutate_before_execution_v1(p_client_submission_id,p_operation,p_payload);end if;
 select * into actor from public.rm_users where auth_user_id=auth.uid() and status='ativo';
 if actor.id is null or not coalesce(actor.perfil in('administrador','padr_o'),false) then raise exception 'A revisão de execução exige acesso de gestão.' using errcode='42501';end if;
 if exists(select 1 from auth.mfa_factors where user_id=auth.uid() and factor_type='totp' and status='verified') and(auth.jwt()->>'aal') is distinct from 'aal2' then raise exception 'Conclua a autenticação de dois fatores.' using errcode='42501';end if;
 if p_client_submission_id is null or p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>65536 then raise exception 'Revisão do apontamento inválida.' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_client_submission_id::text,14));
 select * into receipt from rm_private.web_mutation_receipts where client_submission_id=p_client_submission_id;
 if found then
  if receipt.auth_user_id<>auth.uid() or receipt.actor_id<>actor.id or receipt.operation<>p_operation then raise exception 'Este protocolo já foi utilizado com outro conteúdo.' using errcode='23505';end if;
  if receipt.result->'resource_deleted'='true'::jsonb then
   if receipt.payload->>'original_sha256' is distinct from encode(sha256(convert_to(p_payload::text,'UTF8')),'hex') then raise exception 'Este protocolo já foi utilizado com outro conteúdo.' using errcode='23505';end if;
   raise exception 'Este projeto foi excluído. Preserve o envio para reconciliação.' using errcode='PT410';
  elsif receipt.payload<>p_payload then raise exception 'Este protocolo já foi utilizado com outro conteúdo.' using errcode='23505';end if;
  return receipt.result||jsonb_build_object('idempotent_replay',true);
 end if;
 if not p_payload?&array['session_id','expected_version','action','reported_finished_at','effort_minutes','note','reason']
  or exists(select 1 from jsonb_object_keys(p_payload)k where k not in('session_id','expected_version','action','reported_finished_at','effort_minutes','note','reason'))
  or jsonb_typeof(p_payload->'session_id') is distinct from 'string' or jsonb_typeof(p_payload->'expected_version') is distinct from 'string' or p_payload->>'expected_version' !~ '^[0-9a-f]{64}$'
  or jsonb_typeof(p_payload->'action') is distinct from 'string' or p_payload->>'action' not in('confirm_finished','void')
  or jsonb_typeof(p_payload->'reported_finished_at') not in('null','string') or jsonb_typeof(p_payload->'effort_minutes') not in('null','number')
  or jsonb_typeof(p_payload->'note') is distinct from 'string' or length(p_payload->>'note')>1000
  or jsonb_typeof(p_payload->'reason') is distinct from 'string' or length(btrim(p_payload->>'reason')) not between 3 and 2000 then raise exception 'Confira os campos da revisão do apontamento.' using errcode='22023';end if;
 if p_payload->>'effort_minutes' is not null then
  if p_payload->>'effort_minutes' !~ '^\d{1,7}$' or(p_payload->>'effort_minutes')::int>1000000 then raise exception 'Informe uma quantidade válida de minutos trabalhados.' using errcode='22023';end if;
  effort:=(p_payload->>'effort_minutes')::int;
 end if;
 if p_payload->>'action'='void' then
  if p_payload->>'reported_finished_at' is not null or effort is not null then raise exception 'Um apontamento desconsiderado não pode informar término ou minutos.' using errcode='22023';end if;
 else
  if p_payload->>'reported_finished_at' is null or p_payload->>'reported_finished_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then raise exception 'Informe a data e hora do término.' using errcode='22023';end if;
  reported:=(p_payload->>'reported_finished_at')::timestamptz;
  if not isfinite(reported) or reported>clock_timestamp()+interval '15 minutes' or(reported at time zone 'UTC')::date not between '1900-01-01'::date and '2200-12-31'::date then raise exception 'O término informado é inválido.' using errcode='22023';end if;
 end if;
 select * into s from rm_private.execution_sessions where id=(p_payload->>'session_id')::uuid;
 if s.id is null then raise exception 'O apontamento não está disponível.' using errcode='P0002';end if;
 select * into a from public.rm_celulas_projeto where id=s.allocation_id;
 perform pg_advisory_xact_lock(hashtextextended(a.projeto_id::text,11));
 perform 1 from public.rm_projetos where id=a.projeto_id for update;
 perform 1 from public.rm_celulas_projeto where projeto_id=a.projeto_id order by id for update;
 perform pg_advisory_xact_lock(hashtextextended(s.operator_id::text,51));
 select * into s from rm_private.execution_sessions where id=(p_payload->>'session_id')::uuid for update;
 if s.id is null then raise exception 'O apontamento não está disponível.' using errcode='P0002';end if;
 if rm_private.execution_session_version_v1(s.id) is distinct from p_payload->>'expected_version' then raise exception 'Os apontamentos foram alterados. Recarregue antes de revisar.' using errcode='PT409';end if;
 insert into rm_private.execution_reviews(id,session_id,action,reported_finished_at,effort_minutes,note,reason,actor_id,through_event_id)
  values(review_id,s.id,p_payload->>'action',reported,effort,p_payload->>'note',btrim(p_payload->>'reason'),actor.id,s.last_received_event_id);
 update rm_private.execution_sessions set state=case when p_payload->>'action'='void' then 'void' else 'finished' end,needs_review=false,updated_at=clock_timestamp() where id=s.id;
 result:=jsonb_build_object('operation',p_operation,'id',s.id,'projeto_id',a.projeto_id,'updated_at',clock_timestamp(),'record',jsonb_build_object('review_id',review_id),'idempotent_replay',false);
 insert into rm_private.web_mutation_receipts(client_submission_id,auth_user_id,actor_id,operation,payload,result,before_record)
  values(p_client_submission_id,auth.uid(),actor.id,p_operation,p_payload,result,jsonb_build_object('session',to_jsonb(s)));
 return result;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
 if p_operation is distinct from 'review_execution_session' then raise;end if;
 raise exception 'Confira os identificadores, horários e minutos da revisão.' using errcode='22023';
end$$;
revoke all on function rm_private.web_mutate_core_v1(uuid,text,jsonb),rm_private.web_mutate_before_execution_v1(uuid,text,jsonb) from public,anon,authenticated,service_role;

do $$declare definition text;constraint_definition text;needle text:='when ''save_gantt_plan'' then ''em.planning.manage''';begin
 select pg_get_constraintdef(oid) into constraint_definition from pg_constraint where conrelid='rm_private.sso_action_permits'::regclass and conname='sso_action_permits_operation_check';
 if strpos(constraint_definition,'''save_capacity_resource''::text')=0 then raise exception 'Migration050 required';end if;
 constraint_definition:=replace(constraint_definition,'''save_capacity_resource''::text','''save_capacity_resource''::text, ''review_execution_session''::text');
 alter table rm_private.sso_action_permits drop constraint sso_action_permits_operation_check;
 execute 'alter table rm_private.sso_action_permits add constraint sso_action_permits_operation_check '||constraint_definition;
 definition:=pg_get_functiondef('public.rm_sso_action_permit_v1(text,uuid,text,jsonb,text)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected execution SSO capability map';end if;
 execute replace(definition,needle,needle||' when ''review_execution_session'' then ''em.planning.manage''');
 execute pg_get_functiondef('public.rm_web_mutate_v1(uuid,text,jsonb)'::regprocedure);
end$$;
notify pgrst,'reload schema';
commit;
